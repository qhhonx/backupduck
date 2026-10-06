#!/usr/bin/env python3
"""Repeatable native UI acceptance on a disposable emulator, never a real receiver."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--serial", required=True, help="Already booted, disposable emulator serial")
args = parser.parse_args()
if not args.serial.startswith("emulator-"):
    parser.error("Only disposable Android emulators are allowed")
sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
adb = shutil.which("adb") or (str(Path(sdk) / "platform-tools/adb") if sdk else None)
if not adb:
    parser.error("Set ANDROID_HOME or put adb on PATH")

def run(command):
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=240)
    if result.returncode:
        print(result.stdout, flush=True)
        raise RuntimeError(f"Command failed ({result.returncode}): {command[0]}\n{result.stdout[-12000:]}")
    return result.stdout

def device(*command):
    return run([adb, "-s", args.serial, *command])

model = device("shell", "getprop", "ro.product.model").strip()
fingerprint = device("shell", "getprop", "ro.build.fingerprint").strip()
if "sdk_gphone" not in model and "generic" not in fingerprint:
    parser.error("Target is not an emulator; no data or configuration was changed")
out = ROOT / "build/design-review/android-native"
out.mkdir(parents=True, exist_ok=True)
report = {"time": datetime.now(timezone.utc).isoformat(), "commit": run(["git", "rev-parse", "HEAD"]).strip(),
          "workingTree": "uncommitted changes may be present", "device": model, "fingerprint": fingerprint,
          "data": "synthetic emulator data only", "status": "running", "checks": [], "userAcceptance": "pending"}
original = {"size": device("shell", "wm", "size"), "density": device("shell", "wm", "density"),
            "font": device("shell", "settings", "get", "system", "font_scale").strip()}

def check(mode, folder, dark=None):
    command = ["shell", "am", "instrument", "-w", "-e", "mode", mode]
    if dark is not None:
        command += ["-e", "dark", str(dark).lower()]
    command += ["app.backupduck.validation.test/app.backupduck.ReceiverInstrumentation"]
    result = device(*command)
    (folder / f"{mode}.log").write_text(result)
    if "INSTRUMENTATION_RESULT: result=PASS:" not in result or "INSTRUMENTATION_CODE: -1" not in result:
        (folder / f"{mode}-crash.log").write_text(device("logcat", "-d", "-v", "brief", "-s", "AndroidRuntime", "TestRunner"))
        result = subprocess.run([adb, "-s", args.serial, "exec-out", "screencap", "-p"], stdout=subprocess.PIPE)
        if result.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
            (folder / f"{mode}-failure.png").write_bytes(result.stdout)
        raise RuntimeError(f"{mode} failed; see {folder / (mode + '.log')}")
    print(result.strip(), flush=True)

try:
    build = run([str(ROOT / "apps/android/gradlew"), "-p", "apps/android", "-PvalidationApp",
                 "assembleDebug", "assembleDebugAndroidTest", "testDebugUnitTest", "--offline", "--max-workers=2"])
    (out / "build.log").write_text(build)
    apk = ROOT / "apps/android/app/build/outputs/apk/debug/app-debug.apk"
    report["apkSHA256"] = hashlib.sha256(apk.read_bytes()).hexdigest()
    device("install", "-r", str(apk))
    device("install", "-r", str(ROOT / "apps/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"))
    for width, size, font in [(411, "822x1462", "1.0"), (320, "640x1280", "2.0")]:
        for dark in (False, True):
            name = f"{width}dp-font{font}-{'dark' if dark else 'light'}"
            folder = out / name
            folder.mkdir(exist_ok=True)
            print(f"Checking {name}", flush=True)
            device("shell", "wm", "size", size)
            device("shell", "wm", "density", "320")
            device("shell", "settings", "put", "system", "font_scale", font)
            check("component_flow", folder, dark)
            check("full_replica", folder, dark)
            for screen in ("code-default", "reset-default", "revoke-default", "access-masked", "access-copied", "browser-page"):
                source = f"cache/component-{screen}-{'dark' if dark else 'light'}.png"
                result = subprocess.run([adb, "-s", args.serial, "exec-out", "run-as", "app.backupduck.validation", "cat", source],
                                        check=True, stdout=subprocess.PIPE)
                if not result.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
                    raise RuntimeError(f"Missing actual-window screenshot: {source}")
                (folder / f"{screen}.png").write_bytes(result.stdout)
            for screen in ("thermal", "conversion", "device-name", "devices", "storage-limits", "log-limits", "relay-scope", "archive", "diagnostics", "stop", "storage", "settings", "experiments", "cleanup", "bind", "progress", "cleanup-consent", "photos-diagnostics", "updates"):
                source = f"cache/full-{screen}-{'dark' if dark else 'light'}.png"
                result = subprocess.run([adb, "-s", args.serial, "exec-out", "run-as", "app.backupduck.validation", "cat", source], check=True, stdout=subprocess.PIPE)
                if not result.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
                    raise RuntimeError(f"Missing native workflow screenshot: {source}")
                (folder / f"full-{screen}.png").write_bytes(result.stdout)
            report["checks"].append({"variant": name, "result": "pass"})
    device("shell", "wm", "size", "822x1462")
    device("shell", "wm", "density", "320")
    device("shell", "settings", "put", "system", "font_scale", "1.0")
    check("storage_ui", out, False)
    check("design_review", out, False)
    check("receiver_help", out, False)
    check("dashboard_ui", out)
    report["nativeOperations"] = "pass; original emulator access code restored"
    report["status"] = "pass"
except Exception as error:
    report["status"] = "fail"
    report["failure"] = str(error)
    raise
finally:
    restoration = []
    for key in ("size", "density"):
        override = next((line.split(":", 1)[1].strip() for line in original[key].splitlines() if line.startswith("Override")), "reset")
        restoration.append(["shell", "wm", key, override])
    restoration.append(["shell", "settings", "delete", "system", "font_scale"] if original["font"] == "null" else
                       ["shell", "settings", "put", "system", "font_scale", original["font"]])
    for command in restoration:
        try:
            device(*command)
        except Exception as error:
            report.setdefault("restorationErrors", []).append(str(error))
    (out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"Native acceptance evidence: {out}", flush=True)

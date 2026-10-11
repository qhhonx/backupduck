#!/usr/bin/env python3
"""Stamp a built Apple bundle from the single release manifest."""
import argparse, json, plistlib
from pathlib import Path
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('path', type=Path)
parser.add_argument('--ios', action='store_true', help='Use the numeric store version and retain release metadata.')
args = parser.parse_args()
release = json.loads((Path(__file__).resolve().parent.parent / "release.json").read_text())
path = args.path
data = plistlib.loads(path.read_bytes())
data["CFBundleShortVersionString"] = release["version"].split('-')[0] if args.ios else release["version"]
data["CFBundleVersion"] = str(release["build"])
if args.ios:
    data["BackupDuckReleaseVersion"] = release["version"]
path.write_bytes(plistlib.dumps(data))

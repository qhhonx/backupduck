#!/usr/bin/env python3
"""Create one Xcode Cloud release marker per successfully tested main version."""
import json
import os
import re
import subprocess
from pathlib import Path


def api(endpoint, *arguments):
    result = subprocess.run(["gh", "api", endpoint, *arguments], check=True,
                            capture_output=True, text=True)
    return json.loads(result.stdout)


def report(message):
    print(message)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as output:
            output.write(message + "\n")


def main():
    repository = os.environ["GITHUB_REPOSITORY"]
    tested_sha = os.environ["TESTED_SHA"]
    current = api(f"repos/{repository}/git/ref/heads/main")["object"]["sha"]
    if current != tested_sha:
        report("A newer main commit exists; wait for its checks before distribution.")
        return
    version = json.loads(Path("release.json").read_text())["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.\d+)?", version):
        raise ValueError("Invalid release version")
    tag = f"testflight/v{version}"
    refs = api(f"repos/{repository}/git/matching-refs/tags/testflight/")
    if any(item["ref"] == f"refs/tags/{tag}" for item in refs):
        report(f"{tag} already exists; ordinary commits do not repeat distribution.")
        return
    api(f"repos/{repository}/git/refs", "--method", "POST",
        "-f", f"ref=refs/tags/{tag}", "-f", f"sha={tested_sha}")
    report(f"Created {tag} at the tested commit. Xcode Cloud handles signing and TestFlight delivery.")


if __name__ == "__main__":
    main()

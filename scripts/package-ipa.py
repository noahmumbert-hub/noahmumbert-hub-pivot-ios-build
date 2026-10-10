"""Package an unsigned Xcode device archive for SideStore to re-sign."""

import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile


def package(app: Path, output: Path) -> Path:
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info["CFBundleIdentifier"] != "com.noahmumbert.PIVOT":
        raise ValueError("The archive contains the wrong application")
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("A device build is required; simulator apps cannot be installed")
    executable = app / info["CFBundleExecutable"]
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("The app executable is missing or is not executable")
    widget = app / "PlugIns/PIVOTLiveActivityWidget.appex"
    with (widget / "Info.plist").open("rb") as stream:
        widget_info = plistlib.load(stream)
    if widget_info["CFBundleIdentifier"] != "com.noahmumbert.PIVOT.LiveActivityWidget":
        raise ValueError("The Live Activity extension is missing or has the wrong identifier")
    if widget_info["CFBundleVersion"] != info["CFBundleVersion"]:
        raise ValueError("App and extension build numbers must match")

    output.mkdir(parents=True, exist_ok=True)
    filename = f'PIVOT-{info["CFBundleShortVersionString"]}-{info["CFBundleVersion"]}.ipa'
    ipa = output / filename
    # ditto preserves executable modes, framework symlinks, and the embedded
    # extension. This avoids manufacturing an IPA from a simulator binary.
    with tempfile.TemporaryDirectory(prefix="payload-", dir=output) as directory:
        staging = Path(directory)
        payload = staging / "Payload"
        payload.mkdir()
        subprocess.run(["ditto", str(app), str(payload / "PIVOT.app")], check=True)
        subprocess.run(
            ["ditto", "-c", "-k", "--norsrc", "--keepParent", "Payload", str(ipa.resolve())],
            cwd=staging,
            check=True,
        )
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise ValueError("IPA failed ZIP integrity verification")
        required = [
            "Payload/PIVOT.app/Info.plist",
            f'Payload/PIVOT.app/{info["CFBundleExecutable"]}',
            "Payload/PIVOT.app/PlugIns/PIVOTLiveActivityWidget.appex/Info.plist",
        ]
        for entry in required:
            if entry not in archive.namelist():
                raise ValueError(f"Missing IPA entry: {entry}")
    checksum = hashlib.sha256()
    with ipa.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    digest = checksum.hexdigest()
    (output / "SHA256SUMS").write_text(f"{digest}  {filename}\n")
    metadata = {
        "filename": filename,
        "sha256": digest,
        "size": ipa.stat().st_size,
        "bundleIdentifier": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "minimumOSVersion": info.get("MinimumOSVersion"),
        "signed": False,
        "commit": os.environ.get("GITHUB_SHA"),
        "run": os.environ.get("GITHUB_RUN_ID"),
    }
    (output / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))
    return ipa


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: package-ipa.py <PIVOT.app> <output-directory>")
    package(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())

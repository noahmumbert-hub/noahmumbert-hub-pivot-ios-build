#!/usr/bin/env python3
"""Publish a verified PIVOT build to the existing public SideStore source.

No workflow permissions, signing credentials, main-branch merge, or release API
are needed. Without --publish, prepare local commits and report the source URL.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile

REPOSITORY = "noahmumbert-hub/noahmumbert-hub-pivot-ios-build"
BRANCH = "ipa-builds"
RAW = f"https://raw.githubusercontent.com/{REPOSITORY}"
SOURCE_URL = f"{RAW}/{BRANCH}/source.json"
BUNDLE_ID = "com.noahmumbert.PIVOT"


def command(*args, data=None, env=None):
    return subprocess.check_output(args, input=data, env=env).decode().strip()


def numeric_version(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError(f"Unsupported version: {value!r}")
    return tuple(int(part) for part in value.split(".")) + (0,) * (3 - len(value.split(".")))


def verify_ipa(ipa, info):
    payload = ipa.read_bytes()
    if len(payload) != info["size"] or hashlib.sha256(payload).hexdigest() != info["sha256"]:
        raise ValueError("IPA checksum/size does not match the verified build metadata")
    if ipa.name != info["filename"] or info["bundleIdentifier"] != BUNDLE_ID:
        raise ValueError("Unexpected filename or app identity")
    numeric_version(info["version"])
    numeric_version(info["build"])
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise ValueError("Corrupt IPA")
        names = archive.namelist()
        if any("_CodeSignature/" in name or name.endswith("embedded.mobileprovision") for name in names):
            raise ValueError("Expected the unsigned SideStore artifact")
        privacy = {}
        for name, identity in [
            ("Payload/PIVOT.app/Info.plist", BUNDLE_ID),
            ("Payload/PIVOT.app/PlugIns/PIVOTLiveActivityWidget.appex/Info.plist", BUNDLE_ID + ".LiveActivityWidget"),
        ]:
            plist = plistlib.loads(archive.read(name))
            expected = {"CFBundleIdentifier": identity, "CFBundleShortVersionString": info["version"],
                        "CFBundleVersion": info["build"], "MinimumOSVersion": info["minimumOSVersion"]}
            if any(plist.get(key) != value for key, value in expected.items()):
                raise ValueError(f"App/extension metadata mismatch: {name}")
            if plist.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
                raise ValueError("IPA is not a device build")
            privacy.update({key: value for key, value in plist.items() if key.startswith("NS") and key.endswith("UsageDescription")})
    return payload, privacy


def assert_advances(info, previous):
    if previous and (numeric_version(info["version"]) < numeric_version(previous["version"])
                     or numeric_version(info["build"]) <= numeric_version(previous["buildVersion"])):
        raise ValueError("Refusing a downgrade or an already-published build")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--info", type=Path, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--publish", action="store_true", help="Push the prepared source and IPA to the public branch")
    args = parser.parse_args()
    info = json.loads(args.info.read_text())
    if info.get("signed") is not False:
        raise ValueError("Expected unsigned build metadata")
    payload, privacy = verify_ipa(args.ipa, info)
    run = json.loads(command("gh", "api", f"repos/{REPOSITORY}/actions/runs/{info['run']}"))
    if run["conclusion"] != "success" or run["head_sha"] != info["commit"] or run["status"] != "completed":
        raise ValueError("Build metadata does not match a successful completed GitHub Actions run")
    jobs = json.loads(command("gh", "api", f"repos/{REPOSITORY}/actions/runs/{info['run']}/jobs"))
    required = {"Run Xcode unit and simulator UI tests", "Build and validate unsigned IPA"}
    if not any(job["conclusion"] == "success" and required <= {
        step["name"] for step in job["steps"] if step["conclusion"] == "success"
    } for job in jobs["jobs"]):
        raise ValueError("The build must have passed native tests and device archive validation")
    project = command("git", "show", f"{info['commit']}:PIVOT.xcodeproj/project.pbxproj")
    if "CODE_SIGN_ENTITLEMENTS" in project:
        raise ValueError("Review new app entitlements before publishing source permissions")
    if command("git", "remote", "get-url", "origin").removesuffix(".git") != f"https://github.com/{REPOSITORY}":
        raise ValueError("Run from the PIVOT public iOS repository")
    command("git", "fetch", "origin", BRANCH)
    parent = command("git", "rev-parse", "FETCH_HEAD")
    paths = command("git", "ls-tree", "-r", "--name-only", parent).splitlines()
    if info["filename"] in paths:
        raise ValueError("Refusing to overwrite an existing IPA")
    old_source = json.loads(command("git", "show", f"{parent}:source.json")) if "source.json" in paths else None
    old_versions = old_source["apps"][0]["versions"] if old_source else []
    if old_source and (old_source["sourceURL"] != SOURCE_URL or old_source["apps"][0]["bundleIdentifier"] != BUNDLE_ID):
        raise ValueError("Existing source identity differs")
    assert_advances(info, old_versions[0] if old_versions else None)
    notes = args.notes.read_text().strip()
    if not notes:
        raise ValueError("Release notes are required")
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with tempfile.TemporaryDirectory(prefix="pivot-source-") as temp:
        env = {**os.environ, "GIT_INDEX_FILE": str(Path(temp) / "index")}
        command("git", "read-tree", parent, env=env)

        def stage(path, content):
            blob = command("git", "hash-object", "-w", "--stdin", data=content)
            command("git", "update-index", "--add", "--cacheinfo", f"100644,{blob},{path}", env=env)

        def commit(message, base):
            tree = command("git", "write-tree", env=env)
            return command("git", "commit-tree", tree, "-p", base, data=(message + "\n").encode())

        stage(info["filename"], payload)
        stage("icon.png", Path("PIVOT/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png").read_bytes())
        stage(f"build-info-{info['version']}-{info['build']}.json", args.info.read_bytes())
        stage(f"SHA256SUMS-{info['version']}-{info['build']}", f"{info['sha256']}  {info['filename']}\n".encode())
        asset_commit = commit(f"Host verified PIVOT {info['version']} ({info['build']}) IPA", parent)
        version = {"version": info["version"], "buildVersion": info["build"], "date": date,
                   "localizedDescription": notes, "downloadURL": f"{RAW}/{asset_commit}/{info['filename']}",
                   "size": info["size"], "minOSVersion": info["minimumOSVersion"]}
        app = {"name": "PIVOT", "bundleIdentifier": BUNDLE_ID, "developerName": "Noah Mumbert",
               "subtitle": "Theme park companion", "localizedDescription": "Park wait times, ride status, weather observations, planning, shows and Live Activities.",
               "iconURL": f"{RAW}/{asset_commit}/icon.png", "tintColor": "70DFC0",
               "version": version["version"], "versionDate": date, "versionDescription": notes,
               "downloadURL": version["downloadURL"], "size": version["size"],
               "versions": [version, *old_versions], "appPermissions": {"entitlements": [], "privacy": privacy}}
        description = "PIVOT updates for SideStore. Uses the existing PIVOT app identity."
        source = {"name": "PIVOT", "identifier": "com.noahmumbert.PIVOT.Source", "sourceURL": SOURCE_URL,
                  "subtitle": "PIVOT for SideStore", "description": description, "localizedDescription": description,
                  "website": f"https://github.com/{REPOSITORY}", "websiteURL": f"https://github.com/{REPOSITORY}",
                  "iconURL": app["iconURL"], "tintColor": "70DFC0", "apps": [app], "news": []}
        stage("source.json", (json.dumps(source, ensure_ascii=False, indent=2) + "\n").encode())
        stage("README.md", f"""# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

{SOURCE_URL}

Current update: **{info['version']} / build {info['build']}**, iOS {info['minimumOSVersion']}+.

{notes}

IPA SHA-256: `{info['sha256']}`. [Tested build](https://github.com/{REPOSITORY}/actions/runs/{info['run']}).
The unsigned IPA preserves `com.noahmumbert.PIVOT` and its Live Activity extension.
Install as an update using the same signing identity; keep the existing app installed to retain saved data.
Native unit and simulator UI tests passed for this build. Physical SideStore installation remains untested.
This update contains native changes; installing it does not deploy backend fixes.

This branch hosts downloads permanently, independently of expiring Actions artifacts.
The source URL remains constant; IPA URLs are pinned to immutable Git commits.
The old 1.13.0 file is retained for history but is not listed in the source.

## Publish a future update

Build/test a newer native version with the existing Actions workflow, download its IPA and build-info.json,
then run `scripts/publish-sidestore.py` from the public source checkout with those files and a release-notes file.
Use `--publish` only when publishing is authorized. The helper verifies archive identity, app/extension versions,
checksum, successful build provenance and increasing versions before updating this branch.
No automatic publishing, workflow permission changes or signing credentials are configured.
""".encode())
        tip = commit(f"Publish PIVOT {info['version']} SideStore source", asset_commit)
        if args.publish:
            command("git", "push", "origin", f"{tip}:refs/heads/{BRANCH}")
        print(json.dumps({"published": args.publish, "commit": tip, "assetCommit": asset_commit,
                          "sourceURL": SOURCE_URL, "downloadURL": version["downloadURL"], "sha256": info["sha256"]}, indent=2))


if __name__ == "__main__":
    main()

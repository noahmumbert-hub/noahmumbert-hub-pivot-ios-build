"""Resolve one immutable app checkout from a single SideStore feed revision."""
import json
import re
import sys
from pathlib import Path

BUNDLE = "com.noahmumbert.PIVOT"
BASE = "https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/"


def resolve(directory):
    feed = json.loads((directory / "source.json").read_text())
    if feed.get("sourceURL") != BASE + "ipa-builds/source.json":
        raise ValueError("Unexpected SideStore source")
    app, = (app for app in feed["apps"] if app["bundleIdentifier"] == BUNDLE)
    latest = app["versions"][0]
    version, build = latest["version"], latest["buildVersion"]
    if not all(re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value) for value in (version, build)):
        raise ValueError("Invalid release version or build")
    manifest = json.loads((directory / f"build-info-{version}-{build}.json").read_text())
    filename = f"PIVOT-{version}-{build}.ipa"
    if (manifest["bundleIdentifier"] != BUNDLE or manifest["filename"] != filename
            or manifest["version"] != version or manifest["build"] != build
            or latest["size"] != manifest["size"] or latest["size"] <= 0
            or not re.fullmatch(re.escape(BASE) + r"[a-f0-9]{40}/" + re.escape(filename), latest["downloadURL"])
            or not re.fullmatch(r"[a-f0-9]{40}", manifest["commit"])):
        raise ValueError("SideStore release and build manifest disagree")
    return manifest["commit"]


if __name__ == "__main__":
    print(resolve(Path(sys.argv[1])))

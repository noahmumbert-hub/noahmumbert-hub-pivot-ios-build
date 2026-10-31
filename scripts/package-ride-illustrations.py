#!/usr/bin/env python3
"""Package already generated, pixel-reviewed artwork; this never generates art.

ImageMagick only downscales and JPEG-encodes copies for the app. Original
built-in ImageGen PNGs, prompts and source-photo checksums remain in the supplied
work directory. The user's private UI reference is never copied into the repo.
"""
import argparse
import datetime
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work_directory", type=Path)
    args = parser.parse_args()
    work = args.work_directory.resolve()
    inventory = json.loads((work / "inventory.json").read_text())
    rides = {r["key"]: r for r in inventory["rides"]}
    photos = {r["key"]: r for r in json.loads((work / "photo-fetch-results.json").read_text())}
    additional_references = work / "verified-photo-references.json"
    if additional_references.exists():
        for reference in json.loads(additional_references.read_text())["records"]:
            assert reference["pixelReviewed"] and reference["sourceReviewed"], "Additional references require individual source and pixel review"
            assert reference["key"] not in photos, "Do not silently replace an existing verified reference"
            assert reference["key"] in rides and reference["review"], "Missing ride identity or reference review"
            photos[reference["key"]] = reference
    accepted = []
    docs = REPO / "docs/ride-artwork"
    direction = json.loads((docs / "direction.json").read_text())
    active_style = direction["requestedStyleRevision"]
    blocked = json.loads((docs / "blocked-rides.json").read_text())["records"]
    blocked_keys = {r["key"] for r in blocked}
    for path in sorted(work.glob("accepted-*.json")):
        accepted.extend(r for r in json.loads(path.read_text())["records"] if r.get("styleRevision", 1) == active_style)
    assert len({r["key"] for r in accepted}) == len(accepted), "Duplicate reviewed ride IDs"
    output = REPO / "PIVOT/Resources/RideIllustrations"
    output.mkdir(exist_ok=True)
    originals = work / "originals"; originals.mkdir(exist_ok=True)
    # Retain existing bundled assets while updating reviewed rides individually.
    # Earlier unbundled drafts must never be imported under the new direction.
    records = json.loads((output / "index.json").read_text())["records"] if (output / "index.json").exists() else []
    provenance = json.loads((docs / "provenance.json").read_text())["records"] if (docs / "provenance.json").exists() else []
    for item in sorted(accepted, key=lambda r: tuple(map(int, r["key"].split("-")))):
        key = item["key"]; ride = rides[key]
        assert key not in blocked_keys, f"Generation remains blocked; do not import or retry: {key}"
        assert item["review"].startswith("Accepted:") and item["prompt"], f"Missing pixel review or prompt: {key}"
        source = Path(item["generatedPath"])
        sha = digest(source)
        preserved = originals / f"{key}-{sha[:16]}.png"
        if preserved.exists(): assert digest(preserved) == sha
        else: shutil.copyfile(source, preserved)
        photo = photos[key]
        reference = photo["photo"]
        assert digest(Path(photo["path"])) == photo["sha256"], f"Reference changed: {key}"
        generated_at = datetime.datetime.fromtimestamp(source.stat().st_mtime, datetime.timezone.utc).isoformat()
        record = {
            "parkId": ride["parkID"], "rideId": ride["rideID"], "rideName": ride["rideName"],
            "alt": f"Illustrated {ride['rideName']} at {ride['parkName']}",
            "kind": "ai-generated-illustration", "generator": "built-in-imagegen", "generatedAt": generated_at,
            "originalSHA256": sha, "review": item["review"],
            "styleRevision": active_style,
            "references": [dict(reference, sha256=photo["sha256"], pixelReviewed=True)],
            "license": reference["license"], "licenseURL": reference["licenseURL"],
        }
        for variant, bounds, quality in [("thumbnail", "256x320", "82"), ("detail", "768x960", "84")]:
            filename = f"{key}-{variant}.jpg"; destination = output / filename
            subprocess.run(["magick", str(source), "-thumbnail", bounds, "-strip", "-quality", quality,
                            "-sampling-factor", "4:2:0", str(destination)], check=True)
            width, height = map(int, subprocess.check_output(["magick", "identify", "-format", "%w %h", str(destination)], text=True).split())
            record[variant + "File"] = filename
            record[variant + "SHA256"] = digest(destination)
            record[variant + "Bytes"] = destination.stat().st_size
            record[variant + "Pixels"] = [width, height]
        records = [r for r in records if (r["parkId"], r["rideId"]) != (ride["parkID"], ride["rideID"])] + [record]
        provenance = [r for r in provenance if r["key"] != key] + [dict(record, key=key, prompt=item["prompt"], promptSHA256=hashlib.sha256(item["prompt"].encode()).hexdigest(), generationSteps=item.get("generationSteps", []))]
    records.sort(key=lambda r: (r["parkId"], r["rideId"]))
    provenance.sort(key=lambda r: (r["parkId"], r["rideId"]))
    (output / "index.json").write_text(json.dumps({"schemaVersion": 1, "records": records}, indent=2, ensure_ascii=False) + "\n")
    docs = REPO / "docs/ride-artwork"; docs.mkdir(exist_ok=True)
    (docs / "provenance.json").write_text(json.dumps({"schemaVersion": 1,
        "styleReferenceSHA256": "b2a32c5ec68fca0b95303a250bf888072ad15588740e16a9f1e24213f179aa4f",
        "records": provenance}, indent=2, ensure_ascii=False) + "\n")
    keys = {f"{r['parkId']}-{r['rideId']}" for r in records}
    current_keys = {f"{r['parkId']}-{r['rideId']}" for r in records if r.get("styleRevision", 1) == active_style}
    for ride in inventory["rides"]:
        if ride["key"] in keys:
            ride.update(referenceReview="pixels-reviewed", generationStatus="accepted", integrationStatus="bundled")
        ride["requestedStyleStatus"] = "accepted" if ride["key"] in current_keys else "blocked" if ride["key"] in blocked_keys else "needs-revision" if ride["key"] in keys else "pending"
    inventory["counts"].update(acceptedIllustrations=len(keys), pendingIllustrations=len(rides) - len(keys),
                              acceptedForRequestedStyle=len(current_keys), unfinishedForRequestedStyle=len(rides)-len(current_keys), blocked=len(blocked_keys))
    direction["acceptedForRequestedStyle"] = len(current_keys)
    (docs / "direction.json").write_text(json.dumps(direction, indent=2) + "\n")
    (docs / "coverage.json").write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"accepted": len(records), "pending": len(rides)-len(records),
                      "packagedBytes": sum(r["thumbnailBytes"] + r["detailBytes"] for r in records)}, indent=2))

if __name__ == "__main__":
    main()

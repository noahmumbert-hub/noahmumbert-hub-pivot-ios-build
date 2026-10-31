#!/usr/bin/env python3
"""Validate shipped artwork identity, provenance, byte budgets and coverage."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def jpeg_size(data):
    if data[:2] != b"\xff\xd8": raise ValueError("Not a JPEG")
    offset = 2
    while offset + 4 <= len(data):
        if data[offset] != 255: raise ValueError("Invalid JPEG marker")
        while data[offset] == 255: offset += 1
        marker = data[offset]; offset += 1
        length = struct.unpack_from(">H", data, offset)[0]
        if marker in [0xC0, 0xC1, 0xC2]:
            height, width = struct.unpack_from(">HH", data, offset + 3)
            return [width, height]
        if length < 2: raise ValueError("Invalid JPEG segment")
        offset += length
    raise ValueError("JPEG has no image dimensions")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-complete", action="store_true", help="Fail while any in-scope catalog entry remains unfinished")
    args = parser.parse_args()
    folder = ROOT / "PIVOT/Resources/RideIllustrations"
    manifest = json.loads((folder / "index.json").read_text())
    coverage = json.loads((ROOT / "docs/ride-artwork/coverage.json").read_text())
    provenance = json.loads((ROOT / "docs/ride-artwork/provenance.json").read_text())
    rides = {r["key"]: r for r in coverage["rides"]}
    proof = {r["key"]: r for r in provenance["records"]}
    keys, expected_files, hashes = set(), {"index.json"}, set()
    total_bytes = 0
    for record in manifest["records"]:
        key = f"{record['parkId']}-{record['rideId']}"
        assert key not in keys, f"Duplicate artwork: {key}"
        keys.add(key)
        assert key in rides and record["rideName"] == rides[key]["rideName"], f"Wrong ride identity: {key}"
        assert record["kind"] == "ai-generated-illustration" and record["generator"] == "built-in-imagegen"
        assert record["review"].startswith("Accepted:") and proof[key]["review"] == record["review"]
        assert proof[key]["originalSHA256"] == record["originalSHA256"]
        assert hashlib.sha256(proof[key]["prompt"].encode()).hexdigest() == proof[key]["promptSHA256"]
        assert record["originalSHA256"] not in hashes, f"Artwork reused across distinct ride IDs: {key}"
        hashes.add(record["originalSHA256"])
        assert record["references"], f"Missing real-photo reference: {key}"
        for ref in record["references"]:
            assert ref["pixelReviewed"] and ref["credit"] and ref["license"]
            assert ref["sourceURL"].startswith("https://") and ref["licenseURL"].startswith("https://")
            assert len(ref["sha256"]) == 64
        for variant, bounds, max_bytes in [("thumbnail", [256, 320], 50_000), ("detail", [768, 960], 350_000)]:
            filename = record[variant + "File"]
            assert filename == f"{key}-{variant}.jpg", f"Unexpected resource filename: {filename}"
            expected_files.add(filename)
            data = (folder / filename).read_bytes()
            assert hashlib.sha256(data).hexdigest() == record[variant + "SHA256"], filename
            assert len(data) == record[variant + "Bytes"] <= max_bytes, f"Asset byte budget: {filename}"
            width, height = jpeg_size(data)
            assert [width, height] == record[variant + "Pixels"]
            assert 0 < width <= bounds[0] and 0 < height <= bounds[1]
            assert abs(width / height - 0.8) < 0.01, f"Portrait aspect ratio: {filename}"
            total_bytes += len(data)
        assert rides[key]["generationStatus"] == "accepted" and rides[key]["integrationStatus"] == "bundled"
    assert keys == set(proof), "Manifest and provenance differ"
    assert expected_files == {p.name for p in folder.iterdir()}, "Untracked/missing bundle resources"
    assert len(rides) == coverage["counts"]["unionEntries"]
    assert len(keys) == coverage["counts"]["acceptedIllustrations"]
    pending = [key for key, ride in rides.items() if key not in keys and ride["catalogStatus"] != "excluded-retired"]
    summary = {"validatedIllustrations": len(keys), "catalogEntries": len(rides), "unfinishedEntries": len(pending),
               "parksWithArtwork": len({r["parkId"] for r in manifest["records"]}), "packagedBytes": total_bytes,
               "complete": not pending}
    print(json.dumps(summary, indent=2))
    if args.require_complete and pending:
        raise SystemExit(f"Artwork coverage incomplete: {len(pending)} entries remain; see docs/ride-artwork/coverage.json")

if __name__ == "__main__":
    main()

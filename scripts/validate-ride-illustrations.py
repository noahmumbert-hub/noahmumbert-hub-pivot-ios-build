#!/usr/bin/env python3
"""Validate shipped artwork identity, provenance, byte budgets and coverage."""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FIXTURE_LIST_DIRECTORY = "PIVOT/Resources/RideArtworkTestFixtures"
FIXTURE_INPUT_PREFIX = "$(SRCROOT)/PIVOT/Resources/RideIllustrations/"
FIXTURE_OUTPUT_PREFIX = "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/PIVOTArtworkTestOriginals/"
# Run 290's single phase exceeded sandbox-exec's 65,535-byte compiled-profile
# limit (108,178 bytes). Bound each independent phase rather than aggregating
# lists in one profile. These are declaration limits, not a measurement of the
# native compiled profile; Xcode/macOS acceptance must still be tested in CI.
FIXTURE_MAX_FILES_PER_PHASE = 256
FIXTURE_MAX_LIST_BYTES_PER_PHASE = 48 * 1024
FIXTURE_PHASE_PATTERN = r"(?m)^\t\tC[0-9A-F]{23} /\* Debug artwork test originals(?: [0-9]+)? \*/ = \{.*?\};"
FIXTURE_REFERENCE_PATTERN = r"(?:C[0-9A-F]{23} /\* Debug artwork test originals(?: [0-9]+)? \*/,\s*)+"
FIXTURE_TARGET_PATTERN = r'(A00000000000000000000002 /\* PIVOT \*/ = \{.*?buildPhases = \()(.*?)(\);)'


def fixture_list_payload(names, prefix):
    return "".join(prefix + name + "\n" for name in names).encode()


def fixture_list_bytes(names):
    return sum(len(fixture_list_payload(names, prefix)) for prefix in (FIXTURE_INPUT_PREFIX, FIXTURE_OUTPUT_PREFIX))


def fixture_partitions(jpeg_files):
    assert FIXTURE_MAX_FILES_PER_PHASE > 0 and FIXTURE_MAX_LIST_BYTES_PER_PHASE > 0
    names = sorted(jpeg_files)
    assert names and len(names) == len(set(names)), "Fixture filenames must be nonempty and unique"
    groups, group, size = [], [], 0
    for name in names:
        assert re.fullmatch(r"[0-9]+-[0-9]+-(?:detail|thumbnail)\.jpg", name), "Invalid fixture filename: " + name
        cost = fixture_list_bytes([name])
        assert cost <= FIXTURE_MAX_LIST_BYTES_PER_PHASE, "A single fixture exceeds the phase byte bound"
        if group and (len(group) == FIXTURE_MAX_FILES_PER_PHASE or size + cost > FIXTURE_MAX_LIST_BYTES_PER_PHASE):
            groups.append(tuple(group))
            group, size = [], 0
        group.append(name)
        size += cost
    groups.append(tuple(group))
    return groups


def fixture_list_paths(index):
    return tuple(f"{FIXTURE_LIST_DIRECTORY}/{kind}-{index + 1:02d}.xcfilelist" for kind in ("Inputs", "Outputs"))


def fixture_phase_id(index):
    return f"C{0x140 + index:023X}"


def fixture_phase_name(index):
    return f"Debug artwork test originals {index + 1:02d}"


def fixture_phase_reference(index):
    return f"{fixture_phase_id(index)} /* {fixture_phase_name(index)} */, "


def fixture_marker(index):
    return f"$(TEMP_DIR)/PIVOTArtworkTestFixtures-{index + 1:02d}.ready"


def expected_fixture_copy_script(index):
    # Xcode provides SCRIPT_INPUT_FILE_LIST_0 for the sole declared input list:
    # https://developer.apple.com/documentation/xcode/running-custom-scripts-during-a-build
    # Both unresolved and resolved lists have the same validated basenames.
    # Only the first phase creates the directory. Exact completion-file
    # dependencies serialize later phases even in Release, where JPEGs are
    # deliberately absent. Markers live alongside Xcode's intermediate script
    # files in TEMP_DIR, never in the app bundle, and have a single producer.
    script = '''set -e
if [ "$CONFIGURATION" = "Debug" ]; then
  fixture_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/PIVOTArtworkTestOriginals"
'''
    if index == 0:
        script += '  /bin/mkdir -p "$fixture_dir"\n'
    script += '''  test -s "$SCRIPT_INPUT_FILE_LIST_0"
  while IFS= read -r source_file; do
    filename=${source_file##*/}
    source_file="$SRCROOT/PIVOT/Resources/RideIllustrations/$filename"
    test -f "$source_file"
    /bin/cat "$source_file" > "$fixture_dir/$filename"
  done < "$SCRIPT_INPUT_FILE_LIST_0"
fi
'''
    return script + f': > "$TEMP_DIR/PIVOTArtworkTestFixtures-{index + 1:02d}.ready"\n'


def fixture_phase_definition(index):
    input_list, output_list = fixture_list_paths(index)
    dependency = f'"{fixture_marker(index - 1)}",' if index else ""
    outputs = (f'"{FIXTURE_OUTPUT_PREFIX.rstrip("/")}", ' if index == 0 else "") + f'"{fixture_marker(index)}",'
    return (f"\t\t{fixture_phase_id(index)} /* {fixture_phase_name(index)} */ = {{isa = PBXShellScriptBuildPhase; "
        "alwaysOutOfDate = 1; buildActionMask = 2147483647; files = (); "
        f'inputFileListPaths = ("$(SRCROOT)/{input_list}",); inputPaths = ({dependency}); '
        f'name = "{fixture_phase_name(index)}"; '
        f'outputFileListPaths = ("$(SRCROOT)/{output_list}",); outputPaths = ({outputs}); '
        'runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = '
        + json.dumps(expected_fixture_copy_script(index)) + "; };")


def fixture_build_phases(project):
    return re.findall(FIXTURE_PHASE_PATTERN, project)


def fixture_copy_script(phase):
    matches = re.findall(r'\bshellScript = ("(?:\\.|[^"])*");', phase)
    assert len(matches) == 1, "Exactly one Debug fixture copy script is required"
    return json.loads(matches[0])


def validate_fixture_files(jpeg_files):
    groups = fixture_partitions(jpeg_files)
    expected_paths = set()
    for index, names in enumerate(groups):
        assert len(names) <= FIXTURE_MAX_FILES_PER_PHASE
        assert fixture_list_bytes(names) <= FIXTURE_MAX_LIST_BYTES_PER_PHASE
        for path, prefix in zip(fixture_list_paths(index), (FIXTURE_INPUT_PREFIX, FIXTURE_OUTPUT_PREFIX)):
            expected_paths.add(path)
            assert (ROOT / path).is_file(), f"Missing fixture list: {path}"
            assert (ROOT / path).read_bytes() == fixture_list_payload(names, prefix), (
                f"Debug fixture list {path} must map its bounded partition exactly once, "
                "in sorted order, with no directories, wildcards, metadata or extra files")
    assert {str(path.relative_to(ROOT)) for path in (ROOT / FIXTURE_LIST_DIRECTORY).iterdir()} == expected_paths, (
        "The fixture list directory must contain only the exact generated partitions")
    for legacy in ("RideArtworkTestOriginals.xcfilelist", "RideArtworkTestOutputs.xcfilelist"):
        assert not (ROOT / "PIVOT/Resources" / legacy).exists(), "Remove the obsolete unbounded fixture list"
    project = (ROOT / "PIVOT.xcodeproj/project.pbxproj").read_text()
    assert fixture_build_phases(project) == [fixture_phase_definition(i) for i in range(len(groups))], (
        "Use separate exact bounded phases, direct final-path copies, first-phase directory creation, "
        "serial intermediate-file dependencies, fail-fast behavior and the Debug guard")
    targets = re.findall(FIXTURE_TARGET_PATTERN, project, re.S)
    assert len(targets) == 1
    references = "".join(fixture_phase_reference(i) for i in range(len(groups)))
    assert targets[0][1].count(references) == 1
    assert re.findall(FIXTURE_REFERENCE_PATTERN, targets[0][1]) == [references], "Fixture phases must be contiguous and ordered"
    for i in range(len(groups)):
        assert len(re.findall(r"\b" + fixture_phase_id(i) + r"\b", project)) == 2, "Each fixture phase belongs only to the app target"
    assert project.count("ENABLE_USER_SCRIPT_SANDBOXING = YES;") == 2
    assert "ENABLE_USER_SCRIPT_SANDBOXING = NO" not in project
    return {"phases": len(groups), "maxFilesPerPhase": max(map(len, groups)),
        "maxListBytesPerPhase": max(map(fixture_list_bytes, groups)),
        "fileLimitPerPhase": FIXTURE_MAX_FILES_PER_PHASE,
        "listByteLimitPerPhase": FIXTURE_MAX_LIST_BYTES_PER_PHASE}

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
    coverage = json.loads((ROOT / "docs/ride-artwork/coverage.json").read_text())
    downloads = coverage.get("deliveryMode") == "persistent-original-downloads"
    fixture_summary = {}
    metadata = ROOT / "PIVOT/Resources/RideIllustrationMetadata/catalog.json"
    manifest = json.loads((metadata if downloads else folder / "index.json").read_text())
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
        assert proof[key].get("styleRevision", 1) == record.get("styleRevision", 1)
        assert hashlib.sha256(proof[key]["prompt"].encode()).hexdigest() == proof[key]["promptSHA256"]
        if proof[key].get("generationSteps"):
            assert proof[key]["generationSteps"][-1]["outputSHA256"] == record["originalSHA256"]
            assert proof[key]["generationSteps"][-1]["prompt"] == proof[key]["prompt"]
        assert record["originalSHA256"] not in hashes, f"Artwork reused across distinct ride IDs: {key}"
        hashes.add(record["originalSHA256"])
        assert record["references"], f"Missing real-photo reference: {key}"
        assert bool(record.get("license")) == bool(record.get("licenseURL")), f"Incomplete artwork license: {key}"
        if record.get("licenseURL"):
            assert record["licenseURL"].startswith("https://")
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
        assert rides[key]["generationStatus"] == "accepted"
        assert rides[key]["integrationStatus"] == ("downloadable" if downloads else "bundled")
        if downloads:
            assert record["downloadSourceCommit"] == "77191e42fb6dde600e6bc9a3ab948c7ce09ed4c2"
            assert all(proof[key].get(field) == value for field, value in record.items() if field != "downloadSourceCommit"), key
    selection_name = None if downloads else coverage.get("bundleSelection")
    if selection_name:
        assert Path(selection_name).name == selection_name
    selection_path = ROOT / "docs/ride-artwork" / selection_name if selection_name else None
    selection = json.loads(selection_path.read_text()) if selection_path else None
    if selection:
        accepted_keys = set(proof)
        assert keys == set(selection["selectedKeys"]), "Stage bundle differs from its exact selection"
        assert len(keys) == selection["bundledCount"] == coverage["counts"]["bundledIllustrations"]
        assert set(selection["priorReleasedKeys"]) <= keys, "Previously released artwork must remain bundled"
        assert len(selection["priorReleasedKeys"]) == selection["previouslyReleasedCount"] == 119
        deferred = accepted_keys - keys
        assert deferred == set(selection["deferredKeys"])
        assert len(deferred) == selection["deferredAcceptedCount"] == coverage["counts"]["deferredAcceptedIllustrations"]
        assert len(accepted_keys) == selection["acceptedCount"] == coverage["counts"]["acceptedIllustrations"]
        assert selection["addedCount"] == len(keys) - len(selection["priorReleasedKeys"])
        full_delivery = json.loads((ROOT / "docs/ride-artwork/global-delivery-selection-2026-11-02.json").read_text())
        assert accepted_keys == set(full_delivery["selectedKeys"]), "Keep every accepted provenance record"
        assert set(selection["priorReleasedKeys"]) == set(full_delivery["baseRecordKeys"])
        assert selection["JPEGCount"] == 2 * len(keys) and selection["JPEGBytes"] == total_bytes
        assert selection["parksWithBundledArtwork"] == len({r["parkId"] for r in manifest["records"]})
        for key in deferred:
            assert rides[key]["generationStatus"] == "accepted" and rides[key]["integrationStatus"] == "deferred-stage"
        for record in manifest["records"]:
            key = f"{record['parkId']}-{record['rideId']}"
            assert all(proof[key].get(field) == value for field, value in record.items()), key
    else:
        accepted_keys = keys
        assert keys == set(proof), "Manifest and provenance differ"
    if downloads:
        delivery = json.loads((ROOT / "docs/ride-artwork/download-delivery-selection-2026-11-05.json").read_text())
        previous = json.loads((folder / "index.json").read_text())
        assert len(previous["records"]) == 445
        assert hashlib.sha256((folder / "index.json").read_bytes()).hexdigest() == delivery["previous445IndexSHA256"]
        assert {f"{r['parkId']}-{r['rideId']}" for r in previous["records"]} <= keys
        assert len(keys) == delivery["downloadableIllustrations"] == 1082
        assert 2 * len(keys) == delivery["originalJPEGCount"] == 2164
        assert total_bytes == delivery["originalJPEGBytes"] == 218526843
        assert coverage["counts"]["bundledIllustrations"] == 0
        assert coverage["counts"]["downloadableIllustrations"] == len(keys)
        assert set(p.name for p in metadata.parent.iterdir()) == {"catalog.json"}
        fixture_summary = validate_fixture_files(expected_files - {"index.json"})
    assert expected_files == {p.name for p in folder.iterdir()}, "Untracked/missing bundle resources"
    assert len(rides) == coverage["counts"]["unionEntries"]
    assert len(accepted_keys) == coverage["counts"]["acceptedIllustrations"]
    direction = json.loads((ROOT / "docs/ride-artwork/direction.json").read_text())
    current_keys = {f"{r['parkId']}-{r['rideId']}" for r in manifest["records"] if r.get("styleRevision", 1) == direction["requestedStyleRevision"]}
    accepted_current_keys = {key for key in accepted_keys if proof[key].get("styleRevision", 1) == direction["requestedStyleRevision"]}
    assert len(accepted_current_keys) == direction["acceptedForRequestedStyle"]
    assert len(accepted_current_keys) == coverage["counts"]["acceptedForRequestedStyle"]
    blocked_keys = {r["key"] for r in json.loads((ROOT / "docs/ride-artwork/blocked-rides.json").read_text())["records"]}
    assert not accepted_current_keys & blocked_keys, "Blocked artwork cannot count as accepted"
    pending = [key for key, ride in rides.items() if key not in accepted_current_keys and ride["catalogStatus"] != "excluded-retired"]
    summary = {"validatedIllustrations": len(keys), "catalogEntries": len(rides), "unfinishedEntries": len(pending),
               "parksWithArtwork": len({r["parkId"] for r in manifest["records"]}), "packagedBytes": 0 if downloads else total_bytes,
               "sourceOriginalJPEGBytes": total_bytes,
               "acceptedForRequestedStyle": len(accepted_current_keys),
               "bundledForRequestedStyle": 0 if downloads else len(current_keys),
               "downloadableIllustrations": len(keys) if downloads else 0,
               "debugFixtureJPEGInputs": 2 * len(keys) if downloads else 0,
               "debugFixtureJPEGOutputs": 2 * len(keys) if downloads else 0,
               "debugFixtureCopyPhases": fixture_summary.get("phases", 0),
               "debugFixtureMaxPairsPerPhase": fixture_summary.get("maxFilesPerPhase", 0),
               "debugFixtureMaxListBytesPerPhase": fixture_summary.get("maxListBytesPerPhase", 0),
               "deferredAcceptedIllustrations": len(accepted_keys - keys), "complete": not pending}
    print(json.dumps(summary, indent=2))
    if args.require_complete and pending:
        raise SystemExit(f"Artwork coverage incomplete: {len(pending)} entries remain; see docs/ride-artwork/coverage.json")

if __name__ == "__main__":
    main()

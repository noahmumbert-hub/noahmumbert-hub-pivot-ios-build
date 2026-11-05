#!/usr/bin/env python3
"""Generate bounded Debug-only fixture phases/lists; never change any artwork."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("artwork_validator", ROOT / "scripts/validate-ride-illustrations.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
PROJECT = "PIVOT.xcodeproj/project.pbxproj"


def replace_phases(project, groups):
    matches = list(re.finditer(validator.FIXTURE_PHASE_PATTERN, project))
    assert matches, "The existing fixture phase must be present before regenerating it"
    region = project[matches[0].start():matches[-1].end()]
    assert not re.sub(validator.FIXTURE_PHASE_PATTERN, "", region).strip(), "Fixture definitions must be contiguous"
    definitions = "\n".join(validator.fixture_phase_definition(i) for i in range(len(groups)))
    result = project[:matches[0].start()] + definitions + project[matches[-1].end():]
    references = "".join(validator.fixture_phase_reference(i) for i in range(len(groups)))

    def replace_target(match):
        phases, count = re.subn(validator.FIXTURE_REFERENCE_PATTERN, lambda _: references, match[2])
        assert count == 1, "The app target must contain one contiguous fixture phase group"
        return match[1] + phases + match[3]

    result, count = re.subn(validator.FIXTURE_TARGET_PATTERN, replace_target, result, flags=re.S)
    assert count == 1

    def outside_fixture_phases(text):
        objects = list(re.finditer(validator.FIXTURE_PHASE_PATTERN, text))
        text = text[:objects[0].start()] + "<FIXTURE_DEFINITIONS>" + text[objects[-1].end():]
        return re.sub(validator.FIXTURE_REFERENCE_PATTERN, "<FIXTURE_PHASES>", text)

    assert outside_fixture_phases(result) == outside_fixture_phases(project), "Unrelated project settings changed"
    ids = re.findall(r"(?m)^\s*([0-9A-F]{24}) .*? = \{", result)
    assert len(ids) == len(set(ids)), "Generated phase identifiers collide with existing project objects"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check generated files without writing")
    args = parser.parse_args()
    catalog = json.loads((ROOT / "PIVOT/Resources/RideIllustrationMetadata/catalog.json").read_text())
    names = [record[variant + "File"] for record in catalog["records"] for variant in ("thumbnail", "detail")]
    assert set(names) == {p.name for p in (ROOT / "PIVOT/Resources/RideIllustrations").glob("*.jpg")}
    groups = validator.fixture_partitions(names)
    project_path = ROOT / PROJECT
    project = project_path.read_text()
    generated = replace_phases(project, groups)
    payloads = {path: validator.fixture_list_payload(group, prefix)
        for i, group in enumerate(groups)
        for path, prefix in zip(validator.fixture_list_paths(i), (validator.FIXTURE_INPUT_PREFIX, validator.FIXTURE_OUTPUT_PREFIX))}
    if args.check:
        assert generated == project, "Fixture project phases must be regenerated"
    else:
        directory = ROOT / validator.FIXTURE_LIST_DIRECTORY
        directory.mkdir(exist_ok=True)
        for path, payload in payloads.items():
            (ROOT / path).write_bytes(payload)
        for path in directory.iterdir():
            if str(path.relative_to(ROOT)) not in payloads:
                assert re.fullmatch(r"(?:Inputs|Outputs)-[0-9]+\.xcfilelist", path.name), "Unexpected file in the generated fixture-list directory"
                path.unlink()
        for legacy in ("RideArtworkTestOriginals.xcfilelist", "RideArtworkTestOutputs.xcfilelist"):
            (ROOT / "PIVOT/Resources" / legacy).unlink(missing_ok=True)
        project_path.write_text(generated)
    summary = validator.validate_fixture_files(names)
    print(json.dumps({**summary, "files": len(names), "partitionFiles": [len(group) for group in groups],
        "partitionListBytes": [validator.fixture_list_bytes(group) for group in groups],
        "artworkModified": False, "nativeCompiledProfileSize": "requires macOS/Xcode verification"}, indent=2))


if __name__ == "__main__":
    main()

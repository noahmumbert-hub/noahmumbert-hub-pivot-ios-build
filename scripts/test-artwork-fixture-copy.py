#!/usr/bin/env python3
"""Check fixture sandbox declarations and exercise the actual PBX copy script."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
PROJECT = "PIVOT.xcodeproj/project.pbxproj"
spec = importlib.util.spec_from_file_location("artwork_validator", ROOT / "scripts/validate-ride-illustrations.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def with_script(project, script):
    phase = validator.fixture_build_phase(project)
    updated, count = re.subn(r'\bshellScript = "(?:\\.|[^"])*";',
        lambda _: "shellScript = " + json.dumps(script) + ";", phase)
    assert count == 1
    return project.replace(phase, updated, 1)


class FixtureDeclarationsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.project = (ROOT / PROJECT).read_text()
        catalog = json.loads((ROOT / "PIVOT/Resources/RideIllustrationMetadata/catalog.json").read_text())
        cls.names = {r[v + "File"] for r in catalog["records"] for v in ("thumbnail", "detail")}
        cls.lists = {path: (ROOT / path).read_text() for path in (
            validator.FIXTURE_INPUT_LIST, validator.FIXTURE_OUTPUT_LIST)}

    def test_each_original_maps_to_one_final_output(self):
        self.assertEqual(len(self.names), 2164)
        self.assertEqual(self.names, {p.name for p in (ROOT / "PIVOT/Resources/RideIllustrations").glob("*.jpg")})
        validator.validate_fixture_files(self.names)

    def assert_invalid(self, label, lists, project):
        with self.subTest(label=label), tempfile.TemporaryDirectory(prefix="fixture-declarations-") as temporary:
            root = Path(temporary)
            for name, contents in {**lists, PROJECT: project}.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents)
            with patch.object(validator, "ROOT", root), self.assertRaises(AssertionError):
                validator.validate_fixture_files(self.names)

    def test_invalid_input_and_output_membership_and_mapping_are_rejected(self):
        for path, prefix in [(validator.FIXTURE_INPUT_LIST, validator.FIXTURE_INPUT_PREFIX),
                             (validator.FIXTURE_OUTPUT_LIST, validator.FIXTURE_OUTPUT_PREFIX)]:
            payload = self.lists[path]
            lines = payload.splitlines(keepends=True)
            invalid = {
                "missing JPEG": "".join(lines[1:]),
                "duplicate JPEG": payload + lines[0],
                "extra JPEG": payload + prefix + "0-0-detail.jpg\n",
                "directory": payload + prefix + "\n",
                "wildcard": payload + prefix + "*.jpg\n",
                "metadata": payload + prefix + "index.json\n",
                "wrong path mapping": payload.replace(prefix, "$(SRCROOT)/Other/", 1),
                "unsorted mapping": "".join([lines[1], lines[0], *lines[2:]]),
            }
            for label, contents in invalid.items():
                self.assert_invalid(path + ": " + label, {**self.lists, path: contents}, self.project)

    def test_invalid_phase_wiring_or_copy_strategy_is_rejected(self):
        project = self.project
        script = validator.fixture_copy_script(project)
        input_list = 'inputFileListPaths = ("$(SRCROOT)/' + validator.FIXTURE_INPUT_LIST + '",);'
        output_list = 'outputFileListPaths = ("$(SRCROOT)/' + validator.FIXTURE_OUTPUT_LIST + '",);'
        directory_input = 'inputPaths = ("' + validator.FIXTURE_INPUT_PREFIX.rstrip("/") + '",);'
        directory_output = 'outputPaths = ("' + validator.FIXTURE_OUTPUT_PREFIX.rstrip("/") + '",);'
        copy_line = '    /bin/cat "$source_file" > "$fixture_dir/${source_file##*/}"'
        invalid = {
            "detached input list": project.replace(input_list, "inputFileListPaths = ();"),
            "detached output list": project.replace(output_list, "outputFileListPaths = ();"),
            "broader source directory": project.replace(directory_input, 'inputPaths = ("$(SRCROOT)",);'),
            "broader output directory": project.replace(directory_output, 'outputPaths = ("$(TARGET_BUILD_DIR)",);'),
            "duplicate output declaration": project.replace(directory_output, directory_output + " " + directory_output),
            "unquoted additional output": project.replace(directory_output, directory_output.replace(",);", ", /tmp,);")),
            "incremental phase skipped": project.replace("alwaysOutOfDate = 1;", "alwaysOutOfDate = 0;"),
            "sandbox disabled": project.replace("ENABLE_USER_SCRIPT_SANDBOXING = YES;", "ENABLE_USER_SCRIPT_SANDBOXING = NO;", 1),
            "rsync temporary file strategy": with_script(project, script.replace(copy_line,
                '    /usr/bin/rsync -rt "$source_file" "$fixture_dir/"')),
            "undeclared temporary output": with_script(project, script.replace(copy_line,
                '    /bin/cat "$source_file" > "$fixture_dir/.temporary.jpg"')),
            "Release fixture copy": with_script(project, script.replace('[ "$CONFIGURATION" = "Debug" ]', "true")),
            "copy failures ignored": with_script(project, script.replace("set -e\n", "set +e\n")),
        }
        for label, configuration in invalid.items():
            self.assert_invalid(label, self.lists, configuration)


class FixtureCopyScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = validator.fixture_copy_script((ROOT / PROJECT).read_text())
        originals = sorted((ROOT / "PIVOT/Resources/RideIllustrations").glob("*.jpg"), key=lambda p: p.stat().st_size)[:3]
        cls.originals = {path.name: path.read_bytes() for path in originals}

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="PIVOT fixture copy ")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.source = root / "source checkout"
        self.inputs = self.source / "PIVOT/Resources/RideIllustrations"
        self.inputs.mkdir(parents=True)
        for name, data in self.originals.items():
            (self.inputs / name).write_bytes(data)
        (self.inputs / "index.json").write_text("{}")
        (self.inputs / "not-artwork.txt").write_text("Not a fixture")
        self.products = root / "build products"
        self.outputs = self.products / "PIVOT Fixture.app/PIVOTArtworkTestOriginals"

    def copy(self, configuration="Debug"):
        env = dict(os.environ, CONFIGURATION=configuration, SRCROOT=str(self.source),
            TARGET_BUILD_DIR=str(self.products), UNLOCALIZED_RESOURCES_FOLDER_PATH="PIVOT Fixture.app", LC_ALL="C")
        return subprocess.run(["/bin/sh", "-c", self.script], env=env, capture_output=True, text=True, timeout=10)

    def assert_original_outputs(self):
        self.assertEqual({p.name for p in self.outputs.iterdir()}, set(self.originals))
        for name, data in self.originals.items():
            self.assertEqual((self.outputs / name).read_bytes(), data)
            self.assertEqual((self.inputs / name).read_bytes(), data)

    def test_clean_build_copies_only_original_jpeg_bytes_with_spaces_in_paths(self):
        self.assertFalse(self.products.exists())
        result = self.copy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_original_outputs()

    def test_incremental_build_repairs_same_size_missing_and_partial_files(self):
        self.assertEqual(self.copy().returncode, 0)
        same_size, missing, partial = sorted(self.originals)
        path = self.outputs / same_size
        timestamp = (self.inputs / same_size).stat().st_mtime_ns
        path.write_bytes(b"\0" * len(self.originals[same_size]))
        os.utime(path, ns=(timestamp, timestamp))
        (self.outputs / missing).unlink()
        (self.outputs / partial).write_bytes(self.originals[partial][:10])
        result = self.copy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_original_outputs()

    @unittest.skipIf(os.geteuid() == 0, "Root bypasses temporary-directory mode restrictions")
    def test_incremental_copy_needs_no_new_temporary_filename(self):
        self.assertEqual(self.copy().returncode, 0)
        name = sorted(self.originals)[0]
        (self.outputs / name).write_bytes(b"\0" * len(self.originals[name]))
        self.outputs.chmod(0o555)
        try:
            result = self.copy()
        finally:
            self.outputs.chmod(0o755)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_original_outputs()

    def test_failed_copy_stops_the_build_and_the_next_build_repairs_it(self):
        self.outputs.mkdir(parents=True)
        blocked = self.outputs / sorted(self.originals)[0]
        blocked.mkdir()
        self.assertNotEqual(self.copy().returncode, 0)
        blocked.rmdir()
        result = self.copy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_original_outputs()

    def test_empty_source_stops_the_build(self):
        for name in self.originals:
            (self.inputs / name).unlink()
        self.assertNotEqual(self.copy().returncode, 0)
        self.assertEqual(list(self.outputs.iterdir()), [])

    def test_release_build_creates_no_fixture_outputs(self):
        result = self.copy(configuration="Release")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.products.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)

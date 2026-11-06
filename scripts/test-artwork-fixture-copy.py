#!/usr/bin/env python3
"""Check bounded sandbox declarations and exercise the actual PBX copy scripts."""
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
INVALID_CONFIGURATIONS = 0


def with_script(project, index, script):
    phase = validator.fixture_build_phases(project)[index]
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
        cls.groups = validator.fixture_partitions(cls.names)
        cls.lists = {str(p.relative_to(ROOT)): p.read_text() for p in (ROOT / validator.FIXTURE_LIST_DIRECTORY).iterdir()}

    def test_all_originals_have_one_disjoint_bounded_source_and_output_pair(self):
        self.assertEqual(len(self.names), 2164)
        self.assertEqual(self.names, {p.name for p in (ROOT / "PIVOT/Resources/RideIllustrations").glob("*.jpg")})
        validator.validate_fixture_files(self.names)
        self.assertEqual([len(group) for group in self.groups], [256] * 8 + [116])
        self.assertEqual([name for group in self.groups for name in group], sorted(self.names))
        inputs, outputs = [], []
        for index, group in enumerate(self.groups):
            self.assertLessEqual(len(group), 256)
            input_path, output_path = validator.fixture_list_paths(index)
            source_lines = self.lists[input_path].splitlines()
            output_lines = self.lists[output_path].splitlines()
            self.assertLessEqual(len((self.lists[input_path] + self.lists[output_path]).encode()), 48 * 1024)
            self.assertEqual([p.rsplit("/", 1)[1] for p in source_lines], [p.rsplit("/", 1)[1] for p in output_lines])
            inputs.extend(source_lines)
            outputs.extend(output_lines)
        self.assertEqual(len(inputs), len(set(inputs)))
        self.assertEqual(len(outputs), len(set(outputs)))
        phases = validator.fixture_build_phases(self.project)
        directory = f"$({validator.FIXTURE_DIRECTORY_OUTPUT_SETTING})"
        self.assertEqual(sum(f'outputPaths = ("{directory}",' in p for p in phases), 1)
        self.assertNotIn('inputPaths = ("$(SRCROOT)', "\n".join(phases))

    def assert_invalid(self, label, lists=None, project=None):
        global INVALID_CONFIGURATIONS
        with self.subTest(label=label), tempfile.TemporaryDirectory(prefix="fixture-declarations-") as temporary:
            root = Path(temporary)
            for name, contents in {**(self.lists if lists is None else lists), PROJECT: self.project if project is None else project}.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents)
            with patch.object(validator, "ROOT", root), self.assertRaises(AssertionError):
                validator.validate_fixture_files(self.names)
            INVALID_CONFIGURATIONS += 1

    def test_invalid_membership_and_mapping_in_every_partition_are_rejected(self):
        for index in range(len(self.groups)):
            for path, prefix in zip(validator.fixture_list_paths(index), (validator.FIXTURE_INPUT_PREFIX, validator.FIXTURE_OUTPUT_PREFIX)):
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
                    self.assert_invalid(path + ": " + label, {**self.lists, path: contents})

    def test_missing_stale_legacy_and_cross_partition_lists_are_rejected(self):
        first, second = [validator.fixture_list_paths(i)[0] for i in range(2)]
        missing = dict(self.lists)
        del missing[first]
        self.assert_invalid("missing list", missing)
        self.assert_invalid("stale list", {**self.lists, validator.FIXTURE_LIST_DIRECTORY + "/Inputs-99.xcfilelist": self.lists[first]})
        for legacy in ("RideArtworkTestOriginals.xcfilelist", "RideArtworkTestOutputs.xcfilelist"):
            self.assert_invalid("legacy aggregate", {**self.lists, "PIVOT/Resources/" + legacy: self.lists[first]})
        self.assert_invalid("duplicate entire partition", {**self.lists, second: self.lists[first]})
        mixed = self.lists[first].splitlines(keepends=True)
        mixed[0] = self.lists[second].splitlines(keepends=True)[0]
        self.assert_invalid("cross-partition JPEG", {**self.lists, first: "".join(mixed)})

    def test_invalid_phase_wiring_and_shared_directory_producers_are_rejected(self):
        phases = validator.fixture_build_phases(self.project)
        for index, phase in enumerate(phases):
            input_path, output_path = validator.fixture_list_paths(index)
            changes = {
                "detached input": phase.replace(f'inputFileListPaths = ("$(SRCROOT)/{input_path}",);', "inputFileListPaths = ();"),
                "detached output": phase.replace(f'outputFileListPaths = ("$(SRCROOT)/{output_path}",);', "outputFileListPaths = ();"),
                "aggregated input lists": phase.replace(f'inputFileListPaths = ("$(SRCROOT)/{input_path}",);',
                    f'inputFileListPaths = ("$(SRCROOT)/{input_path}", "$(SRCROOT)/{validator.fixture_list_paths((index + 1) % len(phases))[0]}",);'),
                "aggregated output lists": phase.replace(f'outputFileListPaths = ("$(SRCROOT)/{output_path}",);',
                    f'outputFileListPaths = ("$(SRCROOT)/{output_path}", "$(SRCROOT)/{validator.fixture_list_paths((index + 1) % len(phases))[1]}",);'),
                "broader source input": re.sub(r'inputPaths = \(.*?\);', 'inputPaths = ("$(SRCROOT)",);', phase),
                "broader output": re.sub(r'outputPaths = \(.*?\);', 'outputPaths = ("$(TARGET_BUILD_DIR)",);', phase),
                "skipped incremental repair": phase.replace("alwaysOutOfDate = 1;", "alwaysOutOfDate = 0;"),
            }
            if index:
                changes["second directory producer"] = phase.replace('outputPaths = (', f'outputPaths = ("{validator.FIXTURE_OUTPUT_PREFIX.rstrip("/")}", ')
                changes["missing ordering dependency"] = re.sub(r'inputPaths = \(.*?\);', 'inputPaths = ();', phase)
                changes["future marker dependency"] = phase.replace(validator.fixture_marker(index - 1), validator.fixture_marker(index))
            for label, replacement in changes.items():
                self.assert_invalid(f"phase {index + 1}: {label}", project=self.project.replace(phase, replacement, 1))
        references = [validator.fixture_phase_reference(i) for i in range(len(phases))]
        self.assert_invalid("reversed order", project=self.project.replace("".join(references), "".join(reversed(references)), 1))
        self.assert_invalid("unattached phase", project=self.project.replace(references[-1], "", 1))
        self.assert_invalid("duplicate reference", project=self.project.replace(references[0], references[0] * 2, 1))
        self.assert_invalid("duplicate phase definition", project=self.project + "\n" + phases[-1])
        self.assert_invalid("sandbox disabled", project=self.project.replace("ENABLE_USER_SCRIPT_SANDBOXING = YES;", "ENABLE_USER_SCRIPT_SANDBOXING = NO;", 1))

    def test_configuration_specific_fixture_directory_outputs_are_required(self):
        setting = validator.FIXTURE_DIRECTORY_OUTPUT_SETTING
        debug = f'{setting} = "{validator.FIXTURE_DEBUG_DIRECTORY_OUTPUT}";'
        release = f'{setting} = "{validator.FIXTURE_RELEASE_DIRECTORY_OUTPUT}";'
        self.assert_invalid("Release fixture directory in app bundle", project=self.project.replace(release, debug, 1))
        self.assert_invalid("Debug fixture directory in temporaries", project=self.project.replace(debug, release, 1))

    def test_undeclared_writes_scans_and_unsafe_copy_strategies_are_rejected(self):
        for index in (0, len(self.groups) - 1):
            script = validator.fixture_copy_script(validator.fixture_build_phases(self.project)[index])
            copy_line = '    /bin/cat "$source_file" > "$fixture_dir/$filename"'
            changes = {
                "rsync temporary names": script.replace(copy_line, '    /usr/bin/rsync -rt "$source_file" "$fixture_dir/"'),
                "undeclared temporary output": script.replace(copy_line, '    /bin/cat "$source_file" > "$fixture_dir/.temporary.jpg"'),
                "directory scan": script.replace('while IFS= read -r source_file; do', 'for source_file in "$SRCROOT/PIVOT/Resources/RideIllustrations/"*.jpg; do'),
                "wrong list": script.replace("SCRIPT_INPUT_FILE_LIST_0", "SCRIPT_INPUT_FILE_LIST_1"),
                "Release copy": script.replace('[ "$CONFIGURATION" = "Debug" ]', "true"),
                "ignored errors": script.replace("set -e\n", "set +e\n"),
            }
            for label, replacement in changes.items():
                self.assert_invalid(f"phase {index + 1}: {label}", project=with_script(self.project, index, replacement))

    def test_count_and_byte_boundaries_partition_deterministically(self):
        names = [f"1-{n:03d}-detail.jpg" for n in range(257)]
        groups = validator.fixture_partitions(names)
        self.assertEqual([len(group) for group in groups], [256, 1])
        self.assertEqual(groups, validator.fixture_partitions(reversed(names)))
        small = names[:3]
        cost = validator.fixture_list_bytes(small[:2])
        with patch.object(validator, "FIXTURE_MAX_LIST_BYTES_PER_PHASE", cost):
            self.assertEqual([len(group) for group in validator.fixture_partitions(small)], [2, 1])
        with patch.object(validator, "FIXTURE_MAX_LIST_BYTES_PER_PHASE", cost - 1):
            self.assertEqual([len(group) for group in validator.fixture_partitions(small)], [1, 1, 1])

    def test_empty_duplicate_invalid_and_oversize_partition_inputs_are_rejected(self):
        for names in ([], ["1-1-detail.jpg"] * 2, ["../1-1-detail.jpg"], ["*.jpg"], ["index.json"],
                      ["1-1-detail.jpg\n"], ["1-" + "1" * (48 * 1024) + "-detail.jpg"]):
            with self.subTest(names=str(names)[:80]), self.assertRaises(AssertionError):
                validator.fixture_partitions(names)
        for key in ("FIXTURE_MAX_FILES_PER_PHASE", "FIXTURE_MAX_LIST_BYTES_PER_PHASE"):
            with patch.object(validator, key, 0), self.assertRaises(AssertionError):
                validator.fixture_partitions(["1-1-detail.jpg"])

    def test_generator_check_is_idempotent_and_read_only(self):
        before = {p: (ROOT / p).read_bytes() for p in [*self.lists, PROJECT]}
        result = subprocess.run([sys.executable, str(ROOT / "scripts/prepare-artwork-fixtures.py"), "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {p: (ROOT / p).read_bytes() for p in before})


class FixtureCopyScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scripts = [validator.fixture_copy_script(p) for p in validator.fixture_build_phases((ROOT / PROJECT).read_text())]
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
        self.groups = [sorted(self.originals)[:2], sorted(self.originals)[2:]]
        self.input_lists = [root / f"phase {index} inputs.xcfilelist" for index in range(2)]
        self.write_lists(resolved=False)
        self.products = root / "build products"
        self.outputs = self.products / "PIVOT Fixture.app/PIVOTArtworkTestOriginals"
        self.intermediates = root / "build intermediates"
        self.intermediates.mkdir()

    def write_lists(self, resolved):
        prefix = str(self.inputs) + "/" if resolved else validator.FIXTURE_INPUT_PREFIX
        for path, group in zip(self.input_lists, self.groups):
            path.write_bytes(validator.fixture_list_payload(group, prefix))

    def copy_phase(self, index, configuration="Debug"):
        env = dict(os.environ, CONFIGURATION=configuration, SRCROOT=str(self.source),
            SCRIPT_INPUT_FILE_LIST_0=str(self.input_lists[index]), TARGET_BUILD_DIR=str(self.products),
            UNLOCALIZED_RESOURCES_FOLDER_PATH="PIVOT Fixture.app", TEMP_DIR=str(self.intermediates), LC_ALL="C")
        return subprocess.run(["/bin/sh", "-c", self.scripts[index]], env=env, capture_output=True, text=True, timeout=10)

    def copy(self, configuration="Debug"):
        for index in range(2):
            result = self.copy_phase(index, configuration)
            if result.returncode:
                return result
        return result

    def assert_original_outputs(self):
        self.assertEqual({p.name for p in self.outputs.iterdir()}, set(self.originals))
        for name, data in self.originals.items():
            self.assertEqual((self.outputs / name).read_bytes(), data)
            self.assertEqual((self.inputs / name).read_bytes(), data)

    def test_clean_build_copies_only_original_bytes_with_spaces_in_paths(self):
        self.assertFalse(self.products.exists())
        result = self.copy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_original_outputs()

    def test_resolved_xcode_lists_use_the_same_exact_basenames(self):
        self.write_lists(resolved=True)
        result = self.copy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_original_outputs()

    def test_each_phase_writes_only_its_declared_partition(self):
        self.assertEqual(self.copy_phase(0).returncode, 0)
        self.assertEqual({p.name for p in self.outputs.iterdir()}, set(self.groups[0]))
        first_bytes = {name: (self.outputs / name).read_bytes() for name in self.groups[0]}
        self.assertEqual(self.copy_phase(1).returncode, 0)
        self.assertEqual(first_bytes, {name: (self.outputs / name).read_bytes() for name in first_bytes})
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
        for name in self.originals:
            (self.outputs / name).write_bytes(b"\0" * len(self.originals[name]))
        self.outputs.chmod(0o555)
        try:
            result = self.copy()
        finally:
            self.outputs.chmod(0o755)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_original_outputs()

    def test_first_phase_failure_stops_copy_and_next_build_repairs_it(self):
        self.outputs.mkdir(parents=True)
        blocked = self.outputs / self.groups[0][0]
        blocked.mkdir()
        self.assertNotEqual(self.copy().returncode, 0)
        self.assertFalse((self.outputs / self.groups[1][0]).exists())
        self.assertEqual(list(self.intermediates.iterdir()), [])
        blocked.rmdir()
        result = self.copy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_original_outputs()

    def test_later_phase_failure_is_not_ignored_and_next_build_repairs_it(self):
        self.outputs.mkdir(parents=True)
        blocked = self.outputs / self.groups[1][0]
        blocked.mkdir()
        self.assertNotEqual(self.copy().returncode, 0)
        self.assertTrue((self.intermediates / "PIVOTArtworkTestFixtures-01.ready").exists())
        self.assertFalse((self.intermediates / "PIVOTArtworkTestFixtures-02.ready").exists())
        blocked.rmdir()
        result = self.copy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_original_outputs()

    def test_empty_or_missing_input_list_stops_the_build(self):
        self.input_lists[0].write_text("")
        self.assertNotEqual(self.copy().returncode, 0)
        self.assertEqual(list(self.outputs.iterdir()), [])
        self.input_lists[0].unlink()
        self.assertNotEqual(self.copy().returncode, 0)

    def test_missing_listed_source_stops_the_build(self):
        (self.inputs / self.groups[0][0]).unlink()
        self.assertNotEqual(self.copy().returncode, 0)
        self.assertEqual(list(self.outputs.iterdir()), [])

    def test_later_phase_cannot_create_an_undeclared_directory(self):
        self.assertNotEqual(self.copy_phase(1).returncode, 0)
        self.assertFalse(self.products.exists())

    def test_release_build_creates_no_fixture_outputs(self):
        for index, script in enumerate(self.scripts):
            env = dict(os.environ, CONFIGURATION="Release", TEMP_DIR=str(self.intermediates))
            env.pop("SCRIPT_INPUT_FILE_LIST_0", None)
            result = subprocess.run(["/bin/sh", "-c", script], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, f"phase {index}: {result.stderr}")
        self.assertFalse(self.products.exists())
        self.assertEqual({p.name for p in self.intermediates.iterdir()}, {f"PIVOTArtworkTestFixtures-{i + 1:02d}.ready" for i in range(9)})


if __name__ == "__main__":
    result = unittest.main(verbosity=2, exit=False).result
    print(f"Rejected {INVALID_CONFIGURATIONS} invalid list, wiring and copy configurations.")
    sys.exit(not result.wasSuccessful())

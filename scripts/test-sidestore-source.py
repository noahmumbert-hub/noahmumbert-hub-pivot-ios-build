#!/usr/bin/env python3
"""Publishing validation checks; these are not iPhone installation tests."""
import hashlib
import importlib.util
import io
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
import zipfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("publisher", Path(__file__).with_name("publish-sidestore.py"))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class SourceValidationTests(unittest.TestCase):
    def artifact(self, directory, **overrides):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            for path, identity in [("Payload/PIVOT.app/Info.plist", publisher.BUNDLE_ID),
                                   ("Payload/PIVOT.app/PlugIns/PIVOTLiveActivityWidget.appex/Info.plist", publisher.BUNDLE_ID + ".LiveActivityWidget")]:
                plist = {"CFBundleIdentifier": identity, "CFBundleVersion": "100.3.1",
                         "CFBundleShortVersionString": "1.14.1", "MinimumOSVersion": "17.0",
                         "CFBundleSupportedPlatforms": ["iPhoneOS"]}
                if ".appex" in path:
                    plist.update(overrides)
                else:
                    plist["NSLocationWhenInUseUsageDescription"] = "Choose a nearby park."
                archive.writestr(path, plistlib.dumps(plist))
        payload = data.getvalue()
        path = Path(directory) / "PIVOT-1.14.1-100.3.1.ipa"
        path.write_bytes(payload)
        return path, {"filename": path.name, "bundleIdentifier": publisher.BUNDLE_ID, "size": len(payload),
                      "sha256": hashlib.sha256(payload).hexdigest(), "version": "1.14.1", "build": "100.3.1",
                      "minimumOSVersion": "17.0"}

    def test_accepts_matching_app_extension_and_derives_privacy(self):
        with tempfile.TemporaryDirectory() as directory:
            path, info = self.artifact(directory)
            _, privacy = publisher.verify_ipa(path, info)
            self.assertEqual(privacy, {"NSLocationWhenInUseUsageDescription": "Choose a nearby park."})

    def test_rejects_tampered_download(self):
        with tempfile.TemporaryDirectory() as directory:
            path, info = self.artifact(directory)
            path.write_bytes(path.read_bytes() + b"tampered")
            with self.assertRaisesRegex(ValueError, "checksum/size"):
                publisher.verify_ipa(path, info)

    def test_rejects_changed_extension_identity_or_version_and_simulator(self):
        for changes in [{"CFBundleIdentifier": "another.app"}, {"CFBundleVersion": "22"},
                        {"CFBundleShortVersionString": "1.13.0"}, {"CFBundleSupportedPlatforms": ["iPhoneSimulator"]}]:
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as directory:
                path, info = self.artifact(directory, **changes)
                with self.assertRaises(ValueError):
                    publisher.verify_ipa(path, info)

    def test_rejects_app_identity_change(self):
        with tempfile.TemporaryDirectory() as directory:
            path, info = self.artifact(directory)
            info["bundleIdentifier"] = "another.app"
            with self.assertRaisesRegex(ValueError, "app identity"):
                publisher.verify_ipa(path, info)

    def test_rejects_downgrades_and_duplicate_builds(self):
        previous = {"version": "1.14.1", "buildVersion": "100.3.1"}
        for version, build in [("1.13.0", "100.4.1"), ("1.14.1", "100.3.1"), ("1.15.0", "22")]:
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                publisher.assert_advances({"version": version, "build": build}, previous)
        publisher.assert_advances({"version": "1.14.1", "build": "100.4.1"}, previous)

    def test_compares_numeric_versions(self):
        self.assertEqual(publisher.numeric_version("1.14"), publisher.numeric_version("1.14.0"))
        self.assertGreater(publisher.numeric_version("100.10.1"), publisher.numeric_version("100.9.1"))
        with self.assertRaises(ValueError):
            publisher.numeric_version("1.14-beta")


if __name__ == "__main__":
    unittest.main()

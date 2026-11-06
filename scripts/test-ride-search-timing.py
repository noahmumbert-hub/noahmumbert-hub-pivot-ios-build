#!/usr/bin/env python3
"""Boundary checks for the native-event Ride search release gate."""

import importlib.util
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location(
    "ride_search_timing", Path(__file__).with_name("validate-ride-search-timing.py"))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


def fixture(native_begin=300, keyboard=2_600, native_g=5_700,
            query_g=5_750, native_guardians=7_000, query_guardians=7_100):
    events = [
        ("native-begin-editing isRideSearch=true", native_begin),
        ("keyboard-did-show", keyboard),
        ("native-exact-G", native_g),
        ("query-exact-G", query_g),
        ("native-exact-Guardians", native_guardians),
        ("query-exact-Guardians", query_guardians),
    ]
    return (
        "ARTWORK_RIDE_SEARCH_ACTION firstTapUptimeMs=0 tapCompletedUptimeMs=2400 "
        "keyboardObservedUptimeMs=3500 inputCompletedUptimeMs=5917 "
        "readbackCompletedUptimeMs=6300 visibleKey=true shiftUsed=true "
        "exactPrefixReceived=true oldFiveSecondBreached=true\n"
        "ARTWORK_RIDE_SEARCH_APP_TIMING_BEGIN\n"
        + "".join(f"event={name} uptimeMs={when}\n" for name, when in events)
        + "ARTWORK_RIDE_SEARCH_APP_TIMING_END\n"
    )


class RideSearchTimingTests(unittest.TestCase):
    def test_old_end_to_end_breach_is_reported_but_not_gating(self):
        report = gate.validate(fixture(), 1)[0]
        self.assertIn("tapToFirstGMs=5917 oldFiveSecondBreached=true", report)
        self.assertIn("exactGResponseMs=50", report)

    def test_native_editing_and_keyboard_five_second_boundaries(self):
        gate.validate(fixture(native_begin=5_000, keyboard=5_000), 1)
        for late in (fixture(native_begin=5_001, keyboard=5_002),
                     fixture(keyboard=5_001)):
            with self.assertRaises(ValueError):
                gate.validate(late, 1)

    def test_exact_app_response_boundaries(self):
        gate.validate(fixture(query_g=10_700, native_guardians=11_000,
                              query_guardians=16_000), 1)
        with self.assertRaises(ValueError):
            gate.validate(fixture(query_g=10_701, native_guardians=11_000), 1)
        with self.assertRaises(ValueError):
            gate.validate(fixture(query_guardians=12_001, native_guardians=7_000), 1)

    def test_missing_evidence_or_iteration_fails_closed(self):
        for log, expected in ((fixture().replace("event=native-exact-G", "event=other"), 1),
                              (fixture().replace("ARTWORK_RIDE_SEARCH_APP_TIMING_BEGIN", ""), 1),
                              (fixture(), 3)):
            with self.assertRaises(ValueError):
                gate.validate(log, expected)


if __name__ == "__main__":
    unittest.main()

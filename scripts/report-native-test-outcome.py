#!/usr/bin/env python3
"""Expose bounded native-test results in the Actions check, independent of artifacts."""

import argparse
from collections import Counter
import os
from pathlib import Path
import re


CASE = re.compile(r"Test Case '-\[(?P<suite>[^ ]+) (?P<name>[^\]]+)\]' failed")
TEST_ERROR = re.compile(
    r"^(?P<path>.+?\.swift):(?P<line>\d+): error: "
    r"-\[(?P<suite>[^ ]+) (?P<name>[^\]]+)\] : (?P<reason>.*)$"
)
SWIFT_ERROR = re.compile(r"^(?P<path>.+?\.swift):(?P<line>\d+)(?::\d+)?: error: (?P<reason>.*)$")
SUITE = re.compile(r"Test Suite '(PIVOTTests|PIVOTUITests)\.xctest' (?:passed|failed)")
TOTAL = re.compile(r"Executed (?P<tests>\d+) tests?, with (?P<failures>\d+) failures?")


def short(value: str, length: int = 260) -> str:
    return " ".join(value.split())[:length]


def command(value: str) -> str:
    return short(value).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def summarize(text: str, outcome: str) -> tuple[list[str], list[str]]:
    cases: Counter[str] = Counter()
    errors: dict[str, tuple[str, str, str]] = {}
    compile_errors: list[str] = []
    timing_errors: list[str] = []
    totals: dict[str, tuple[str, str]] = {}
    suite = ""

    for line in text.splitlines():
        match = TEST_ERROR.search(line)
        if match:
            errors[match["name"]] = (
                Path(match["path"]).name,
                match["line"],
                short(match["reason"]),
            )
        match = CASE.search(line)
        if match:
            cases[match["name"]] += 1
        match = SWIFT_ERROR.search(line)
        if match and not TEST_ERROR.search(line) and len(compile_errors) < 5:
            compile_errors.append(
                f'{Path(match["path"]).name}:{match["line"]}: {short(match["reason"])}'
            )
        if "RIDE_SEARCH_TIMING_GATE_FAILED" in line and len(timing_errors) < 5:
            timing_errors.append(short(line[line.index("RIDE_SEARCH_TIMING_GATE_FAILED") :]))
        if "MAP_GESTURE_TARGET_FAILURE" in line and len(timing_errors) < 5:
            timing_errors.append(short(line[line.index("MAP_GESTURE_TARGET_FAILURE") :], 1400))
        if "MAP_TAB_TRANSITION_FAILURE" in line and len(timing_errors) < 5:
            timing_errors.append(short(line[line.index("MAP_TAB_TRANSITION_FAILURE") :], 1400))
        match = SUITE.search(line)
        if match:
            suite = match[1]
        match = TOTAL.search(line)
        if match and suite:
            totals[suite] = (match["tests"], match["failures"])
            suite = ""

    details = []
    for name, count in cases.most_common(12):
        location, line, reason = errors.get(name, ("", "", "XCTest reported failure"))
        source = f" at {location}:{line}" if location else ""
        details.append(f"{name} failed {count} time(s){source}: {reason}")
    for name in errors.keys() - cases.keys():
        location, line, reason = errors[name]
        details.append(f"{name} at {location}:{line}: {reason}")
    details.extend(compile_errors)
    details.extend(timing_errors)
    if outcome == "failure" and not details:
        details.append("Native test step failed; no failed XCTest case or compiler error was found in the log")
    details = details[:15]

    counts = [
        f"{name}: {totals[name][0]} executed, {totals[name][1]} failures"
        for name in ("PIVOTTests", "PIVOTUITests")
        if name in totals
    ]
    if not counts:
        counts = ["Suite execution totals unavailable in native test log"]
    return counts, details


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    outcome = os.environ.get("PIVOT_NATIVE_TEST_OUTCOME", "unknown")
    content = args.log.read_text(errors="replace") if args.log.is_file() else ""
    counts, details = summarize(content, outcome)

    print(f"NATIVE_TEST_CHECK_SUMMARY outcome={outcome}; " + "; ".join(counts))
    for detail in details:
        print(f"::error title=PIVOT native test failure::{command(detail)}")

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.write(f"### PIVOT native test result: {outcome}\n\n")
            for count in counts:
                summary.write(f"- {count}\n")
            for detail in details:
                summary.write(f"- {detail.replace('|', '/')}\n")
            if not content:
                summary.write("- Native test log is missing or empty.\n")


if __name__ == "__main__":
    main()

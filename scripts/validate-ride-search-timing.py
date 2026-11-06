#!/usr/bin/env python3
"""Gate fixture Ride search using app event times, not XCTest read latency."""

import re
import sys
from pathlib import Path


ACTION = re.compile(
    r"ARTWORK_RIDE_SEARCH_ACTION firstTapUptimeMs=(\d+) .*?"
    r"inputCompletedUptimeMs=(\d+) .*?oldFiveSecondBreached=(true|false)"
)
EVENT = re.compile(r"event=([\w-]+) .*?uptimeMs=(\d+)")
def validate(log: str, expected: int) -> list[str]:
    actions = [(int(tap), int(input_end), breach == "true")
               for tap, input_end, breach in ACTION.findall(log)]
    if len(actions) != expected:
        raise ValueError(f"expected {expected} Ride search actions; found {len(actions)}")
    if "ARTWORK_RIDE_SEARCH_APP_TIMING_BEGIN" not in log or "ARTWORK_RIDE_SEARCH_APP_TIMING_END" not in log:
        raise ValueError("app timing log was not collected")
    app_log = log.split("ARTWORK_RIDE_SEARCH_APP_TIMING_BEGIN", 1)[1].split(
        "ARTWORK_RIDE_SEARCH_APP_TIMING_END", 1)[0]
    events = []
    for line in app_log.splitlines():
        match = EVENT.search(line)
        if match and (match.group(1) != "native-begin-editing" or "isRideSearch=true" in line):
            events.append((match.group(1), int(match.group(2))))

    reports = []
    for index, (tap, input_end, old_breach) in enumerate(actions):
        next_tap = actions[index + 1][0] if index + 1 < len(actions) else float("inf")
        window = [(name, when) for name, when in events if tap <= when < next_tap]

        def first(name: str, after: int = tap) -> int:
            matches = [when for event, when in window if event == name and when >= after]
            if not matches:
                raise ValueError(f"iteration {index + 1}: missing {name}")
            return min(matches)

        def exact_response(name: str, native_time: int) -> int:
            # SwiftUI's binding callback can precede UIKit's change
            # notification for the same keystroke. Allow at most 250 ms of
            # that posting-order difference; any slower response still fails.
            matches = [when for event, when in window if event == name
                       and native_time - 250 <= when <= native_time + 5_000]
            if not matches:
                raise ValueError(f"iteration {index + 1}: {name} was missing or outside its five-second native-input window")
            return max(0, min(matches) - native_time)

        native_begin = first("native-begin-editing")
        keyboard = first("keyboard-did-show", native_begin)
        native_g = first("native-exact-G", native_begin)
        g_response = exact_response("query-exact-G", native_g)
        native_guardians = first("native-exact-Guardians", native_g)
        guardians_response = exact_response("query-exact-Guardians", native_guardians)
        if native_begin - tap > 5_000 or keyboard - tap > 5_000:
            raise ValueError(f"iteration {index + 1}: native editing or keyboard exceeded five seconds from tap")
        if native_g > input_end:
            raise ValueError(f"iteration {index + 1}: native G event followed completed key action")
        reports.append(
            f"RIDE_SEARCH_TIMING_GATE iteration={index + 1} "
            f"nativeEditingMs={native_begin - tap} keyboardMs={keyboard - tap} "
            f"exactGResponseMs={g_response} "
            f"exactGuardiansResponseMs={guardians_response} "
            f"tapToFirstGMs={input_end - tap} oldFiveSecondBreached={str(old_breach).lower()}"
        )
    return reports


if __name__ == "__main__":
    try:
        for report in validate(Path(sys.argv[1]).read_text(), int(sys.argv[2])):
            print(report)
    except (OSError, ValueError, IndexError) as error:
        print(f"RIDE_SEARCH_TIMING_GATE_FAILED {error}", file=sys.stderr)
        sys.exit(1)

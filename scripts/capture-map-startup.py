"""Bounded read-only simulator frames when XCTest's own recording is unavailable."""
import datetime
import json
from pathlib import Path
import subprocess
import sys
import time

simulator = sys.argv[1]
folder = Path("build/map-startup-diagnostics")
folder.mkdir(parents=True, exist_ok=True)
stop = Path("build/map-startup-observer.stop")
log = Path("build/native-tests.log")
started = time.monotonic()
offset = 0
pending = ""
case_start = None
frames = []
state = {"simulator": simulator, "readOnly": True, "maximumFrames": 36,
         "maximumBytes": 64 * 1024 * 1024, "frames": frames}
try:
    while not stop.exists() and time.monotonic() - started < 1800:
        if log.exists():
            with log.open(errors="replace") as stream:
                stream.seek(offset)
                pending += stream.read()
                offset = stream.tell()
            lines = pending.split("\n")
            pending = lines.pop()
            if case_start is None and any(
                "testMapCategoryChangesAndInterruptedSearchRemainUsable]' started" in line
                for line in lines
            ):
                case_start = time.monotonic()
                state["observedCaseStartUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        if case_start is not None:
            elapsed = time.monotonic() - case_start
            if elapsed >= 180 or len(frames) >= 36:
                break
            if elapsed >= len(frames) * 5:
                name = f"frame-{len(frames):02d}.png"
                record = {"filename": name, "observedCaseElapsedSeconds": elapsed,
                          "requestedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat()}
                try:
                    result = subprocess.run(
                        ["xcrun", "simctl", "io", simulator, "screenshot", "--type=png", str(folder / name)],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False)
                    record["exitCode"] = result.returncode
                    record["bytes"] = (folder / name).stat().st_size if (folder / name).exists() else 0
                except subprocess.TimeoutExpired:
                    record["captureTimedOutSeconds"] = 10
                record["completedUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                frames.append(record)
                state["bytes"] = sum(p.stat().st_size for p in folder.glob("*.png"))
                (folder / "manifest.json").write_text(json.dumps(state, indent=2) + "\n")
                if state["bytes"] >= state["maximumBytes"]:
                    break
        time.sleep(0.5)
finally:
    state["caseStartObserved"] = case_start is not None
    state["finishedUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (folder / "manifest.json").write_text(json.dumps(state, indent=2) + "\n")

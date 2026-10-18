#!/usr/bin/env bash
# Run from the pinned application's checkout, not the monitoring checkout.
set -euo pipefail
phase="${1:?build, fixtures, live-ui, or export required}"
mkdir -p build/monitor

if [[ "$phase" == export ]]; then
  for group in fixtures live-ui; do
    bundle="build/$group.xcresult"
    if [[ -d "$bundle" ]]; then
      xcrun xcresulttool get test-results summary --path "$bundle" \
        > "build/monitor/$group-summary.json" 2> "build/monitor/$group-export-errors.log" || true
      xcrun xcresulttool export attachments --path "$bundle" \
        --output-path "build/monitor/$group-screenshots" \
        >> "build/monitor/$group-export-errors.log" 2>&1 || true
    fi
  done
  exit 0
fi

if [[ "$phase" == build ]]; then
  xcrun simctl list devices available -j > build/monitor/simulators.json
  python3 - <<'PY' > build/monitor/simulator-id.txt
import json
from pathlib import Path
devices = json.loads(Path('build/monitor/simulators.json').read_text())['devices']
for runtime, entries in sorted(devices.items(), reverse=True):
    if 'iOS' in runtime:
        for device in entries:
            if device.get('isAvailable') and device['name'].startswith('iPhone'):
                print(device['udid'])
                raise SystemExit(0)
raise SystemExit('No available iPhone simulator')
PY
fi

simulator_id="$(cat build/monitor/simulator-id.txt)"
args=(-project PIVOT.xcodeproj -scheme PIVOT
  -destination "platform=iOS Simulator,id=$simulator_id"
  -derivedDataPath build/MonitorDerivedData
  -parallel-testing-enabled NO -jobs 3
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=)
case "$phase" in
  build) args+=(build-for-testing) ;;
  fixtures)
    args+=(test-without-building -resultBundlePath build/fixtures.xcresult
      -only-testing:PIVOTTests
      -only-testing:PIVOTUITests/PIVOTUITests/testWaitForecastShowsHourlyPlanCrowdAndLearningState
      -only-testing:PIVOTUITests/PIVOTUITests/testSavedForecastDoesNotSuggestRidingNow
      -only-testing:PIVOTUITests/PIVOTUITests/testHHNFavoritesCompletionUndoAndRelaunch
      -only-testing:PIVOTUITests/PIVOTUITests/testHHNSavedAndEmptyFeedsNeverShowLiveWaits) ;;
  live-ui)
    args+=(test-without-building -resultBundlePath build/live-ui.xcresult
      -only-testing:PIVOTUITests/PIVOTUITests/testPlanOwnsCrowdAndPredictedWaitControls
      -only-testing:PIVOTUITests/PIVOTUITests/testExpandedParkCanBeFoundAndSelected) ;;
  *) echo "Unknown phase: $phase" >&2; exit 2 ;;
esac

started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
result=0
xcodebuild "${args[@]}" 2>&1 | tee "build/monitor/$phase.log" || result=$?
python3 - "$phase" "$started" "$result" <<'PY'
import datetime, json, sys
from pathlib import Path
phase, started, result = sys.argv[1:]
record = dict(phase=phase, startedAt=started,
    endedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(), exitCode=int(result))
Path(f'build/monitor/{phase}-execution.json').write_text(json.dumps(record, indent=2))
PY
exit "$result"

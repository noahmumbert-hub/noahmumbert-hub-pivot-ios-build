#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 scripts/validate-ride-illustrations.py
xcrun simctl list devices available -j > build/simulators.json
xcrun simctl list runtimes -j > build/simulator-runtimes.json
xcrun simctl list devicetypes -j > build/simulator-device-types.json
simulator_id="$(python3 - <<'PY'
import json
import os
import subprocess
with open('build/simulators.json') as f:
    devices = json.load(f)['devices']
with open('build/simulator-runtimes.json') as f:
    runtimes = json.load(f)['runtimes']
with open('build/simulator-device-types.json') as f:
    device_types = json.load(f)['devicetypes']
requested = os.environ.get('PIVOT_SIMULATOR_NAME', '').strip()
available_runtimes = sorted(
    (r for r in runtimes if r.get('isAvailable') and '.iOS-' in r['identifier']),
    key=lambda r: tuple(int(part) for part in r['version'].split('.')), reverse=True)
selected = None
for runtime in available_runtimes:
    for device in devices.get(runtime['identifier'], []):
        if device.get('isAvailable') and (device['name'] == requested if requested else device['name'].startswith('iPhone')):
            selected = dict(device=device, runtime=runtime, created=False)
            break
    if selected:
        break
if selected is None and requested:
    device_type = next((d for d in device_types if d['name'] == requested), None)
    if device_type is None:
        raise SystemExit(f'Requested simulator device type is unavailable: {requested}')
    if not available_runtimes:
        raise SystemExit('No available iOS simulator runtime')
    runtime = available_runtimes[0]
    identifier = subprocess.check_output(
        ['xcrun', 'simctl', 'create', requested, device_type['identifier'], runtime['identifier']], text=True).strip()
    selected = dict(device=dict(name=requested, udid=identifier), runtime=runtime, created=True)
if selected is None:
    raise SystemExit('No available iPhone simulator')
record = dict(name=selected['device']['name'], identifier=selected['device']['udid'],
              runtime=selected['runtime']['name'], runtimeIdentifier=selected['runtime']['identifier'],
              created=selected['created'])
with open('build/simulator-selection.json', 'w') as f:
    json.dump(record, f, indent=2)
    f.write('\n')
print(record['identifier'])
PY
)"
cat build/simulator-selection.json
test_options=(
  -parallel-testing-enabled NO
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 180
  -maximum-test-execution-time-allowance 240
)
case "${PIVOT_TEST_SCOPE:-all}" in
  all) ;;
  reference-ui)
    test_options+=(
      -only-testing:PIVOTUITests/PIVOTUITests/testGeneratedRideIllustrationLoadsWithCreditsAndPreservesWaits
      -only-testing:PIVOTUITests/PIVOTUITests/testReferenceEPCOTCardsSearchFiltersAndPhotoCredits
      -only-testing:PIVOTUITests/PIVOTUITests/testReferenceCardsKeepEachParksIdentityAndNativeTabs
      -only-testing:PIVOTUITests/PIVOTUITests/testAccentSettingsPersistAfterRelaunch
    ) ;;
  native-design)
    test_options+=(
      -only-testing:PIVOTUITests/PIVOTUITests/testReferenceEPCOTCardsSearchFiltersAndPhotoCredits
      -only-testing:PIVOTUITests/PIVOTUITests/testReferenceCardsKeepEachParksIdentityAndNativeTabs
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeMapFillsWindowAndSupportsPinchPanZoomWithoutCameraReset
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeBrowseFocusesRideAndRootWaitDetailsStayCurrent
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeClustersZoomAndCoLocatedPlacesRemainSelectable
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeSurfacesPreserveHoursShowsAlertsAndPlanProgress
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeDarkAndLargeTextSurfacesRemainReachable
    ) ;;
  large-text)
    test_options+=(-only-testing:PIVOTUITests/PIVOTUITests/testNativeDarkAndLargeTextSurfacesRemainReachable) ;;
  map-gestures)
    test_options+=(
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeMapFillsWindowAndSupportsPinchPanZoomWithoutCameraReset
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeBrowseFocusesRideAndRootWaitDetailsStayCurrent
      -only-testing:PIVOTUITests/PIVOTUITests/testNativeClustersZoomAndCoLocatedPlacesRemainSelectable
    ) ;;
  *)
    echo 'Unsupported PIVOT_TEST_SCOPE; use all, reference-ui, native-design, large-text, or map-gestures.' >&2
    exit 1 ;;
esac
python3 - <<'PY'
import json, os
scope = os.environ.get('PIVOT_TEST_SCOPE', 'all')
with open('build/test-scope.json', 'w') as f:
    json.dump(dict(scope=scope, completeRegression=scope == 'all'), f, indent=2)
    f.write('\n')
PY
test_exit=0
xcodebuild -project PIVOT.xcodeproj -scheme PIVOT \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/TestDerivedData \
  -resultBundlePath build/native-tests.xcresult \
  "${test_options[@]}" -jobs 3 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  test 2>&1 | tee build/native-tests.log || test_exit=$?
export_exit=0
if [[ -d build/native-tests.xcresult ]]; then
  xcrun xcresulttool export attachments --path build/native-tests.xcresult --output-path build/ui-screenshots || export_exit=$?
fi
if [[ "$test_exit" -ne 0 ]]; then
  exit "$test_exit"
fi
exit "$export_exit"

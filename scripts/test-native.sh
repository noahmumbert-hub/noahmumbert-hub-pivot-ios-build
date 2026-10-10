#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun simctl list devices available -j > build/simulators.json
simulator_id="$(python3 - <<'PY'
import json
with open('build/simulators.json') as f:
    devices = json.load(f)['devices']
for runtime, entries in devices.items():
    if 'iOS' not in runtime:
        continue
    for device in entries:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            print(device['udid'])
            raise SystemExit(0)
raise SystemExit('No available iPhone simulator')
PY
)"
test_exit=0
xcodebuild -project PIVOT.xcodeproj -scheme PIVOT \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/TestDerivedData \
  -resultBundlePath build/native-tests.xcresult \
  -parallel-testing-enabled NO -jobs 3 \
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

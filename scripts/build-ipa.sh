#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This build requires macOS and Xcode; use the Build SideStore IPA workflow.' >&2
  exit 1
fi

build_number="${PIVOT_BUILD_NUMBER:-100.1.1}"
if [[ ! "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo 'PIVOT_BUILD_NUMBER must contain one to three numeric components.' >&2
  exit 1
fi

mkdir -p build
xcodebuild \
  -project PIVOT.xcodeproj \
  -scheme PIVOT \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$project_root/build/PIVOT.xcarchive" \
  -derivedDataPath "$project_root/build/DerivedData" \
  -jobs 3 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  CURRENT_PROJECT_VERSION="$build_number" \
  archive 2>&1 | tee build/xcodebuild.log

python3 scripts/package-ipa.py \
  build/PIVOT.xcarchive/Products/Applications/PIVOT.app \
  build/ipa

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo '### PIVOT IPA built'
    echo
    echo 'Download the **PIVOT-SideStore** artifact below, extract its ZIP, and import the contained **.ipa** into SideStore.'
    echo
    echo 'The IPA is unsigned. SideStore must sign it using your Apple account before installation.'
    echo
    echo 'This build includes the Live Activity extension. It requires iOS 17 or later.'
  } >> "$GITHUB_STEP_SUMMARY"
fi

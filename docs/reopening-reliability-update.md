# Reopening guidance — PIVOT 1.15.2

PIVOT now withholds numeric reopening guidance when its observations or ride-specific evidence cannot support it. Saved/failed refreshes, incomplete weather evidence, unobserved closure starts and expired windows show why timing is uncertain. A historical range is distinguished from a supported point estimate. Active lightning and a conditional clear clock cannot promise the park's reopening time.

The native safeguards apply to Radar, ride rows/details and Live Activities, including responses from the existing older backend. Current weather ranges require matching verified mapped clearance, complete fresh observations and supported restart history. Weather guidance never shows an exact best guess. Operational point estimates require the newer calibration contract that retains missed forecasts in coverage accounting. Legacy push payloads cannot restore unsupported numbers. ActivityKit's stale date is bounded by the window end so a window can expire without another push.

Users may see fewer numeric predictions until enough comparable observations and calibration outcomes exist. This is a reliability safeguard, not a claim that a newly trained model is more accurate. The associated backend history/calibration changes require review against the current deployment and its saved forecast outcomes; installing this IPA does not deploy those changes.

The update advances **1.15.1 → 1.15.2**, retaining `com.noahmumbert.PIVOT`, its Live Activity extension, preference keys, saved plans/favorites/offline packs and the existing SideStore source. Install as an update with the same signing identity and keep the current app installed.

Changed native files:

- `PivotModels.swift`: optional, backward-compatible reliability metadata.
- `PivotFormatting.swift`: shared evidence/freshness/expiry gates and consistent closure status text.
- `RadarCardView.swift` and `RideListView.swift`: use the shared guidance and check time between refreshes.
- `LiveActivityService.swift`, `PIVOTLiveActivityAttributes.swift` and the widget: supported range/point fields, optional guidance contract version and bounded expiry.
- Xcode project and tests: app/widget version continuity and seven reopening regression methods, plus the existing simulator UI suite.

## Validation

Final native source `438bcbdee7c21e647b745f4c217be29e94f9632f` passed **174 Xcode unit tests, 13 iPhone 16 Pro simulator UI tests, and the Release device archive** in [run 38392069570](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38392069570), using Xcode 26.3. The earlier source `16376e1` also passed the full workflow in run `38390430598`; only the final build is published. Subsequent commits update documentation only; the app/project/test files match the tested source.

Earlier attempts remain visible: run `38388365870` failed compilation because the new code treated required weather data as optional; that access was corrected. Run `38389035686` compiled but failed 14 assertions in the new tests because the fixture's outer timestamp was updated while its provider timestamp remained stale; the fixture now updates both, preserving the real freshness guard. Its 13 existing simulator UI tests passed. These failed attempts produced no published IPA.

Native tests cover sparse support, legacy and poor calibration, expiry between refreshes, failed/stale/future data, active/missing/GLM lightning, matching verified clearance, supported ranges without point guesses, ActivityKit expiry and legacy payload decoding. The simulator UI suite exercises existing navigation/HHN/Plan behavior; it does not measure real forecast accuracy. Six local SideStore publisher tests pass. No SwiftLint is configured.

Archive inspection verified app/widget version and build, `iPhoneOS` platform, unsigned packaging, checksum, binary headers and absence of DEBUG fixture launch flags. The final Plan simulator screenshot was inspected: the crowd meter and predicted-wait entry remain on Plan, and missing observations do not turn into a numeric crowd rating. Existing CLLocationManagerDelegate/MainActor, interface-orientation and AppIntents metadata warnings remain; this is not a warning-free build.

Physical iPhone/SideStore installation, real-storm calibration, prospective forecast accuracy and current-backend integration remain unrun. No backend deployment, main-branch merge, GitHub release, service purchase or permission change is included.

## Published SideStore update

- Version/build: **1.15.2 / 100.26.1**, unsigned device IPA, iOS **17.0+**.
- File: `PIVOT-1.15.2-100.26.1.ipa`, **2,968,830 bytes**.
- SHA-256: `59e313250f3f72961f78e96b09f351fb2030b5e46bb9f5f0ddd3003fa421ca7b`.
- Source commit: `5dfea2520a5de1588cf8425397cc8a4e3924d1d2`; immutable asset commit: `8a15780c6163ba1e8f861b8fce57d12c4b0c50dd`.
- [Existing SideStore source](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json).
- [Verified IPA](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/8a15780c6163ba1e8f861b8fce57d12c4b0c50dd/PIVOT-1.15.2-100.26.1.ipa).

The source, IPA and icon returned HTTP 200 after publication. Downloaded IPA bytes and SHA-256 match the tested archive. The original source/app/widget identifiers, existing permissions and all six prior source versions are preserved. Refresh the existing source in SideStore and install PIVOT as an update with the same signing identity.

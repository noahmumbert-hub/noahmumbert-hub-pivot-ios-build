# Crowd and wait predictions on Plan — PIVOT 1.15.1

Moves the crowd meter and park/day comparison from Waits into Plan, directly beneath Your day. A compact Predicted waits entry on Plan opens a ride selector and that ride's hourly estimates and lowest-wait suggestion. Waits and ride information retain posted waits and timestamped observation history.

Forecast calculations, coverage requirements, confidence labels, learning thresholds, and the existing versioned history storage are unchanged. The forecast browser dismisses when the main park changes; a ride absent from the current snapshot cannot receive a ride-now suggestion. Favorites, day plans, offline packs, alerts, original app/widget identities, and SideStore compatibility are preserved. App/widget versions advance from 1.15.0 to 1.15.1; no backend deployment, feed purchase, permission change, main merge, or GitHub release is involved.

Changed files: NativeDayPlannerView.swift integrates the Plan controls; NativeWaitForecastView.swift adds ride selection and navigation; RideListView.swift removes the forecast controls from Waits/ride information. The Xcode project increments the version/build, and PIVOTUITests.swift verifies the version plus actual tab placement. Source is mirrored to the private repository's public/PIVOT-iOS with baseline equality checks.

The existing Xcode test/archive workflow **passed on attempt 2** for native source fcd1486a81e363b834e731d4065f0d7528442215, run [38332103121](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38332103121). The final attempt passed **167 unit tests, 13 iPhone simulator UI tests, and the Release device archive**. The new UI check navigates the real app between Waits and Plan, confirms the controls belong to Plan, and captures a simulator screenshot. It does not depend on a live API successfully returning rides. Existing model and HHN regressions also run. Six SideStore publisher tests and git diff --check passed locally.

Physical iPhone/SideStore installation and prospective forecast calibration remain unrun. Existing web/backend lint/TypeScript failures are not reclassified as passes; that runtime code is unchanged. No SwiftLint is configured; native checks run on the public macOS/Xcode workflow.

The [original model and delivery report](wait-crowd-forecast.md) documents the local-history warmup, preliminary confidence, queue-based crowd proxy, and previous validation history.

The first attempt passed all 167 unit tests and the Plan placement UI check, but two existing UI tests failed at app launch with XCTest's “Timed out while acquiring background assertion” error. The overall attempt failed and produced no published IPA. A fresh-runner retry of the failed job passed with the same immutable source. Both the failed attempt and passing retry remain in the workflow history. The first attempt's simulator screenshot was inspected and confirms both controls beneath Your day with Plan selected; no missing crowd data was presented as a numeric rating.

The final simulator attachment was inspected with Plan selected and shows the crowd meter, Compare parks & days, and Predicted waits beneath Your day. The placement test verifies these controls are absent from Waits. The screenshot is simulator evidence, not a physical installation or accuracy test. Existing CLLocationManagerDelegate/MainActor and orientation/AppIntents warnings remain documented; no warning-free claim is made. Release binary inspection confirmed the DEBUG fixture launch flags and screen are excluded.

## Published SideStore update

- Version/build: **1.15.1 / 100.22.2**, unsigned device IPA, minimum iOS 17.0
- File: `PIVOT-1.15.1-100.22.2.ipa` · 2,959,787 bytes
- SHA-256: `07b39c083f1c94e096896f1767c9c9b0e8036df21eb98394c605251279ac182f`
- Source publication commit: `9acbd793164676a85cdf0e9b1202faf9d3759910`
- Immutable asset commit: `06d3b8a4ff80fa98b273bff17d52c3a99b3eeff2`
- [Existing SideStore source](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json)
- [Verified IPA](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/06d3b8a4ff80fa98b273bff17d52c3a99b3eeff2/PIVOT-1.15.1-100.22.2.ipa)

Canonical source, icon, and IPA read-back returned HTTP 200. Downloaded bytes and SHA-256 match the tested archive; the original source/app/widget identifiers and version history are preserved. No backend deployment, main merge, GitHub release, purchase, or permissions change was made.

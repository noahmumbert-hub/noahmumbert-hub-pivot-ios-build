# Crowd and wait predictions on Plan — PIVOT 1.15.1

Moves the crowd meter and park/day comparison from Waits into Plan, directly beneath Your day. A compact Predicted waits entry on Plan opens a ride selector and that ride's hourly estimates and lowest-wait suggestion. Waits and ride information retain posted waits and timestamped observation history.

Forecast calculations, coverage requirements, confidence labels, learning thresholds, and the existing versioned history storage are unchanged. The forecast browser dismisses when the main park changes; a ride absent from the current snapshot cannot receive a ride-now suggestion. Favorites, day plans, offline packs, alerts, original app/widget identities, and SideStore compatibility are preserved. App/widget versions advance from 1.15.0 to 1.15.1; no backend deployment, feed purchase, permission change, main merge, or GitHub release is involved.

Changed files: NativeDayPlannerView.swift integrates the Plan controls; NativeWaitForecastView.swift adds ride selection and navigation; RideListView.swift removes the forecast controls from Waits/ride information. The Xcode project increments the version/build, and PIVOTUITests.swift verifies the version plus actual tab placement. Source is mirrored to the private repository's public/PIVOT-iOS with baseline equality checks.

The existing Xcode test/archive workflow is running for native source fcd1486a81e363b834e731d4065f0d7528442215, run 38332103121. The new UI check navigates the real app between Waits and Plan, confirms the controls belong to Plan, and captures a simulator screenshot. It does not depend on a live API successfully returning rides. Existing model and HHN regressions also run. Six SideStore publisher tests and git diff --check passed locally.

Physical iPhone/SideStore installation and prospective forecast calibration remain unrun. Existing web/backend lint/TypeScript failures are not reclassified as passes; that runtime code is unchanged. No SwiftLint is configured; native checks run on the public macOS/Xcode workflow.

The [original model and delivery report](wait-crowd-forecast.md) documents the local-history warmup, preliminary confidence, queue-based crowd proxy, and previous validation history.

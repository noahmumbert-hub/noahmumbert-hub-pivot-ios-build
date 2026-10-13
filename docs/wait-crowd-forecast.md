# Hourly ride waits and park crowds — PIVOT 1.15.0

**Current placement:** [PIVOT 1.15.1 moves these controls to Plan](plan-crowd-update.md); the model below is unchanged. This report retains the original 1.15.0 delivery history.

Adds a wait-based crowd meter to Waits, a browser for all supported parks and dates, and an hourly forecast with the lowest estimated remaining wait in each ride's details. This native update retains the compact HHN UI and all previous audit fixes, identities, preference keys, and SideStore compatibility.

## What the estimates mean

There is no attendance feed. The crowd meter is a queue-pressure proxy: median valid open-ride posted wait, converted to a bounded 1–10 index (ceiling of minutes/10). Labels are Quiet (<15 minutes), Moderate (15–29), Busy (30–59), Very busy (60+). It never represents attendance or percent capacity. At least five rides and 35% of eligible rides must report; missing, closed, duplicate, invalid, or future-version records are excluded. Live ratings require an active park and fresh healthy observation, with no failed refresh or stale provider cache.

Observed daily ratings summarize only sampled operating hours, with rides weighted equally within each hour and hours weighted equally. They are not full-day attendance measurements. Future ratings require at least three observed days, prefer the same weekday when available, and show limited confidence. Past days without observations stay unavailable. The browser offers the last 55 days and next 14 days; selected local calendar dates survive switching between park time zones. Browsing or refreshing another park does not change the main park, GPS selection, alerts, or favorites.

## Ride forecasts

Each park/ride/day/hour stores up to four genuine quarter-hour observations. Repeated polls have one vote per quarter-hour and each historical day has one vote in an hourly forecast. Recent timestamped API wait history can seed the current session; untimestamped legacy trends are never assigned invented observation times. Conflicting observations with identical timestamps and duplicate ride IDs are excluded. Provider version timestamps may be older when a fresh observation verifies an unchanged posted wait; missing or future-dated versions cannot make a current wait usable.

Hourly forecasts require three distinct previous operating days for that ride and hour. Three observations of the same weekday take precedence; otherwise recent days are used and labeled accordingly. Today's observations do not train today's baseline. With enough current park coverage and five rides with historical baselines, the median ratio of current-to-normal waits adjusts future estimates, bounded to 0.5–2.0. Every value remains within 0–1440 minutes, rounded to five minutes. The range describes the observed 20th–80th percentile spread plus five minutes, not a calibrated probability interval.

Only verified regular operating periods are projected. Schedule checks must be under 36 hours old and neither stale nor future-dated; feed observations must be under 15 minutes old. Forecast slots stop at closing, including after midnight, and the previous day's opening anchors overnight learning. Missing hours remain gaps. The suggested lowest wait covers only remaining hours with sufficient evidence and requires the ride currently open and the main feed healthy; it does not predict reopening. Saved or failed feeds can display historical estimates but cannot adjust them with today's crowds or produce a ride-now suggestion.

## Availability and limits

The existing production backend is unchanged. Learning is local to this device and occurs from successful observations while using PIVOT or checking parks in the crowd browser. There is no background or all-park attendance collection, shared historical service, new subscription, or paid feed. The first use can show a live crowd meter, but future crowd ratings and ride forecasts show Learning until sufficient observed days accumulate. Different parks/hours require their own coverage. History uses a separate versioned UserDefaults key, retains at most 56 days and 40,000 bins, and survives app restart; older bins can be evicted before 56 days if the storage cap is reached.

Holiday/event/seasonal/calendar demand, weather, ride capacity, and unseen operating changes are not separately modeled. The feature remains labeled Preliminary / limited confidence. Synthetic regression fixtures validate behavior, not forecast accuracy; no real-world calibration or prospective accuracy study has been performed. Regular rides during ticketed HHN events retain existing monitoring policy; this change does not redefine it or add haunted-house forecasts.

## Validation and delivery

Native Xcode checks and the Release device archive **passed** on the existing public GitHub Actions workflow for source `1b0ef3fe0bbce78c02bce9824a1cb66309cd1bda`, run [38330317542](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38330317542). The final run passed **167 unit tests and 12 iPhone 16 Pro / iOS 18.5 simulator UI tests**, including the updated cache and version assertions. The six existing SideStore publisher validation tests passed locally. The final simulator attachment was manually inspected: all four forecast columns render from zero with their numeric estimates, the lowest-wait suggestion is visible, and insufficient history shows Learning. Release binary inspection confirmed that both HHN and forecast DEBUG fixtures and their launch flags are absent. Existing compiler warnings remain: CLLocationManagerDelegate/MainActor isolation (Swift 5 mode), interface-orientation configuration, and AppIntents metadata extraction without that dependency. No SwiftLint is configured, and Linux cannot run Xcode. This task changes no web/backend runtime code, so earlier web lint/TypeScript baseline failures are not reclassified as passes. Physical iPhone installation and prospective forecast accuracy are unrun.

Validation history is retained: attempts 12–14, 16–17, and 19–20 were canceled/superseded and are not clean passes or published updates. Attempt 15 failed compilation because the new files were absent from the app target's sources; target membership was corrected. Attempt 18 passed all 167 unit tests and 11 of 12 UI tests; the existing settings test still asserted version 1.14.4 and was updated to require 1.15.0. Both new forecast UI checks passed. Manual inspection of that simulator attachment also exposed a blank date-based chart; the final source renders explicit time-range columns with a zero wait baseline. Neither failed attempt was published.

Regression coverage includes hourly patterns, distinct-day thresholds, same-weekday and general-day histories, missing hours, park isolation, midnight sessions and closing boundaries, local-date preservation across park time zones, stale/future schedules, invalid/missing/future waits, future source timestamps combined with fetch skew, duplicate/conflicting observations, poll deduplication, current crowd adjustment versus failed feeds, sparse coverage, daily/future crowd aggregation, persisted data restoration, preference preservation, independent park browsing, and failed per-park caches through repeated switching and revalidation. New simulator checks cover the estimate presentation, hourly details, and removal of ride-now suggestions for saved data. These use deterministic synthetic fixtures; they are not physical-device or live-production checks.

Changed files: `PIVOT/Models/NativeWaitForecast.swift` adds the model and persistence; `PIVOT/Store/DashboardStore.swift` collects observations and isolates crowd browsing; `PIVOT/Views/NativeWaitForecastView.swift` supplies the meter, browser, and chart; `PIVOT/Views/RideListView.swift` integrates them. The project updates app/widget to 1.15.0 and registers the new sources. `PIVOT/App/PIVOTApp.swift` adds a DEBUG-only simulator fixture. Regression changes are in `NativeWaitForecastTests.swift`, `PIVOTTests.swift`, and `PIVOTUITests.swift`. Native source is mirrored into the private repository's `public/PIVOT-iOS` without backend deployment.

## Published update

The existing authorized SideStore source was updated after all final checks passed; no main branch merge, backend deployment, paid feed, permission change, purchase, or GitHub release was made.

- Version/build: **1.15.0 / 100.21.1**, unsigned device IPA, minimum iOS 17.0
- File: `PIVOT-1.15.0-100.21.1.ipa` · 2,946,530 bytes
- SHA-256: `d1b581966bac1a6fcab5871df234992195527d12bdd739eb77a033a9db3e30ad`
- Source publication commit: `e3f49d0cbed1ebf10c31c364ea08bbd491b15207`
- Immutable asset commit: `c4465c71d4a27bdb4752554a616e2105463626a0`
- [Existing SideStore source](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json)
- [Verified IPA](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/c4465c71d4a27bdb4752554a616e2105463626a0/PIVOT-1.15.0-100.21.1.ipa)

Read-back verification returned HTTP 200 for the canonical source, icon, and IPA; the downloaded IPA's bytes and hash equal the tested artifact. Source/app identifiers, main and widget bundle identifiers, and previous 1.14.4 history are preserved. The private repository's native mirror contains the same 36 files. The source runs were not used as physical installation tests.

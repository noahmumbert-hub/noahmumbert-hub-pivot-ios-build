# Hourly ride waits and park crowds — PIVOT 1.15.0

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

Native Xcode unit/UI tests and device archive are running on the existing public GitHub Actions workflow. Results and immutable IPA metadata will be recorded here before publication. The six existing SideStore publisher validation tests passed locally. No SwiftLint is configured, and Linux cannot run Xcode. This task changes no web/backend runtime code, so earlier web lint/TypeScript baseline failures are not reclassified as passes. Physical iPhone installation remains unrun.

Superseded workflow attempts 12–14 were canceled while tightening regression fixtures and date handling; none is a passed check or a published update.

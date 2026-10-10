# PIVOT 1.14.2 — Halloween Horror Nights UI

The Universal Studios Florida HHN screen has a purple and amber event header, clearer date/hours and ticket notice, larger wait numbers, readable house status labels, and a compact favorite-house completion summary. Search and All houses/Favorites/To do filters make long house lists easier to use. Other app tabs keep a compact event banner.

House favorites, sorting and completion use the existing stored keys. Completion stays attached to the event date across midnight. Missing favorites remain saved even when absent from the feed. There is no app identity change or migration.

Pre-event preview, live status observations, saved data and unavailable data have distinct labels. Waits still require fresh event and house observations, an open house and a nonnegative source value. A valid zero remains zero; absent/stale/future/failed observations remain unknown.

Regular ride monitoring during HHN and the backend/API are unchanged by this UI update.

## Validation

- Publisher validation: 6 tests passed locally.
- First run 38084807938: all 148 native unit tests passed; 6 of 10 simulator UI tests passed. Four new UI tests could not find controls because SwiftUI propagated container-level accessibility identifiers onto their children. Identifiers were moved to individual elements. No IPA was published from this failed run.
- Run 38085693316 was canceled and superseded after aligning the feed badge with deduplicated displayed houses.
- Run 38085885373: all 149 unit tests and 9/10 UI tests passed. Its remaining preview test exposed the same identifier propagation on expanded DisclosureGroup content. That container identifier was removed; the assertion and a preview-favorite interaction were retained. No IPA was published from this failed run.
- Run 38086797679 was superseded by run 38087339360 after screenshot review found a dim default search placeholder. The final source uses the readable muted text color for that prompt.
- Final [run 38087339360](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38087339360), source `63f2ca8b02833ed14e39ef8df7b0e9a0b3c430e1`: **149 unit tests and 10 simulator UI tests passed**, zero failures, on iPhone 16 Pro / iOS 18.5 using Xcode 26.3. The Release device archive and package validation passed.
- UI tests cover favorite/completion persistence and undo, search, filter empty states, preview, saved/empty feeds and accessibility text size.
- Color checks: body text contrast 8.90:1 on cards (including the final search prompt) and 7.70:1 on the hero; selected filter text 11.19:1.
- Screenshots use fictional house names in an explicit DEBUG-only test screen; this screen is excluded from release builds.
- Final screenshot review: normal text, accessibility text, favorite progress, saved waits and expanded pre-event preview checked. The corrected search prompt is legible; preview favorites work without showing live waits. Screenshots are simulator sample data, not actual park observations.
- ZIP integrity, SHA-256, unsigned device platform, unchanged app/widget identifiers, matching versions and iOS 17 minimum verified. DEBUG fixture names and launch arguments are absent from the Release app binary.
- Published source, IPA and icon read back over HTTPS with HTTP 200; downloaded bytes, SHA-256 and app/widget metadata match the tested artifact. Version 1.14.1 remains in source history.
- Local checks: six publisher tests, Python script parsing, Bash syntax and git diff whitespace passed. No web lint/typecheck rerun: no web/backend code changed.
- Physical iPhone/SideStore signing and installation: unrun.

## Delivery

Version **1.14.2 / build 100.8.1** is published to the [existing PIVOT SideStore source](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json). The source URL and app/widget identifiers remain the same. All 33 native files match the private app repository mirror. No main-branch merge or backend deployment is part of this change.

## Changed files

- `PIVOT/Views/NativeParkExtras.swift`: HHN presentation, filter/search/checklist controls, freshness labels and DEBUG-only simulator fixtures.
- `PIVOT/App/PIVOTApp.swift`: explicit DEBUG-only test screen entry point.
- `PIVOT/Views/PivotTheme.swift`: settings update instructions point to SideStore.
- `PIVOT.xcodeproj/project.pbxproj`: app/widget marketing version 1.14.2, project build 24; CI assigns increasing build numbers.
- `PIVOTTests/NativeParkExtrasTests.swift`: seven added presentation regression tests.
- `PIVOTUITests/PIVOTUITests.swift`: five added HHN interaction/accessibility tests and updated version expectation.
- `scripts/test-native.sh` and `.github/workflows/build-ipa.yml`: retain simulator screenshot attachments on both successful and failed test runs.
- `README.md` and this report: tested update provenance and delivery instructions.

## Limits

These checks exercise native presentation and simulator interactions, using explicit test fixtures for HHN. They do not validate live storm data, real house wait accuracy, a physical SideStore install, or the separate web/backend audit findings. The existing Swift 5 build emits inherited CLLocationManagerDelegate/MainActor warnings; those warnings are not being represented as a clean lint or Swift 6 pass. There is no configured SwiftLint check for this project. The previous web lint/TypeScript baseline failures remain documented in the October 8 report and were not changed by this native UI update.

## Artifact and release notes

- IPA: `PIVOT-1.14.2-100.8.1.ipa`, 2,841,167 bytes.
- SHA-256: `c016400d0b89fbf404f2b3666628a9e2cf4fdac9b3351444b6b5b808d78006da`.
- Source publication commit: `3a070c9288b28a60841442d001bffcfc7ca21fb4`; immutable asset commit: `6bb5b579c946039a3560fc2721bb69b9186a26a9`.
- [Direct IPA](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/6bb5b579c946039a3560fc2721bb69b9186a26a9/PIVOT-1.14.2-100.8.1.ipa).

Refresh the existing PIVOT source in SideStore, then update PIVOT. Keep the existing app installed and use the same signing identity to retain its data. The source URL remains unchanged. No GitHub release, main merge, backend deployment, permissions change or paid service was introduced.

Halloween Horror Nights gets a clearer purple-and-amber layout, larger wait numbers, readable house statuses, search, and All houses/Favorites/To do filters. A favorite-house checklist tracks your night; existing favorites, sorting and completed houses are preserved. Preview, saved and unavailable data have distinct labels, and stale or missing waits stay unknown. Large text layouts and touch targets were checked in the iPhone simulator. This native update includes the previous 1.14.1 fixes and preserves the existing app and Live Activity identity. Keep PIVOT installed and update it using the same SideStore signing identity. Physical SideStore installation remains untested.

# PIVOT 1.14.4 — HHN posted waits

A successful ThemeParks.wiki park response repeatedly observes each posted wait. The house lastUpdated value records when it changed. The HHN builder and native presentation both treated that value as a 15-minute expiry clock, wrongly dropping valid unchanged waits. The native RootView also gated HHN houses on the separate regular-ride feed health flag.

Both source gates now use freshness of the successful house snapshot while still rejecting invalid/future entity timestamps, missing/negative waits, failed polls and expired snapshots. Native HHN does not depend on regular-ride feed health. A primary app refresh failure still gates the retained HHN snapshot.

To restore waits omitted by the deployed backend, the native app can refresh USF event houses from the same free ThemeParks.wiki endpoint after event opening and only when the server HHN data is incomplete, expired or has aged entity versions. The parser validates park identity and explicit HHN house identities, rejects conflicting duplicate IDs, skips invalid timestamps and withholds invalid/future waits. It prefers the normal house STANDBY value, then the provider's HHN PAID_STANDBY value; it never uses an Express queue. Successful direct observations are cached for at most 60 seconds with their original check time; failed attempts back off for 30 seconds and do not renew saved data. Requests time out after 8 seconds. Regular rides, weather, notifications and operator reopening guidance retain their own health checks.

## Evidence and checks

- Public provider response inspected October 10 at 22:37 UTC: all 10 houses were OPERATING with numeric STANDBY waits. Hellraiser carried 10 minutes and a 20:38 UTC entity timestamp, almost two hours old; several other houses had versions older than 15 minutes. Those are usable values in a fresh response.
- Replayed the captured public response through the baseline and corrected builders: baseline dropped 5 of 10 waits; corrected builder preserved all 10, including Hellraiser at 10 minutes with its original timestamp. This is recorded-response reproduction, not a deployed PIVOT API result.
- The production PIVOT API request from this cloud returned HTTP 403, so the current production backend payload could not be inspected. Available source reproduces the omitted-wait behavior; no production API success is claimed.
- 46 targeted JavaScript tests passed: HHN, provider observations, ThemeParks.wiki parsing/cache and existing SQLite/D1 API integration. New HHN regressions cover old versions and valid zero, both sides of midnight, stale/failed recovery, invalid/future data and missing waits.
- Targeted ESLint for lib/halloween-horror-nights.ts passed. Web page ESLint failed with the same 2 errors and 4 warnings as the preceding source (identical rules/messages and import-line offsets). TypeScript failed with 318 diagnostics matching the stored baseline after normalizing missing-D1 spelling suggestions and source line offsets; no clean lint/typecheck pass is claimed.
- Web build: passed (pnpm run build, both client and server outputs). Existing route-classification and node:async_hooks compatibility warnings remain; the build exited successfully, not warning-free.
- Six publisher validation tests and git whitespace checks passed locally.
- Native [run 38092438641](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38092438641), source `9fa6a592fb18337017f46932b0d49e07613139f2`: **154 unit tests and 10 simulator UI tests passed**, zero failures, using Xcode 26.3 / iPhone 16 Pro / iOS 18.5. Release device archive and IPA validation passed. Added deterministic native regressions cover old-version wait/status/badges, source identity/queue parsing, future/invalid data, duplicate IDs, successful direct recovery, request caching and failed-attempt backoff. The normal simulator fixture includes a two-hour-old zero wait and asserts that it remains visible.
- Run 38092394979 was superseded to include the independently validated regular-ride health gate correction; no IPA was published from it.
- Physical iPhone/SideStore signing and installation: unrun.

## Delivery and limits

Version 1.14.4 retains the compact 1.14.3 UI, preferences and app/widget identifiers. **1.14.4 / build 100.11.1** is published to the [existing SideStore source](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json). Source, IPA and icon were read back over HTTPS with HTTP 200. Downloaded checksum, bytes, app/widget identities and versions match the tested artifact; older updates remain in feed history. Backend source fixes are prepared in the private repository; no backend deployment is authorized or performed. The newer audited backend source remains unavailable and must be reconciled before a backend rollout. HHN regular-ride monitoring policy is unchanged.

Changed native files: PIVOT/Networking/PivotAPIClient.swift, PIVOT/Views/NativeParkExtras.swift, PIVOT/Views/RootView.swift, PIVOTTests/NativeParkExtrasTests.swift, PIVOTTests/PIVOTTests.swift, PIVOTUITests/PIVOTUITests.swift and PIVOT.xcodeproj/project.pbxproj. Backend/web source/test: lib/halloween-horror-nights.ts, app/page.tsx and tests/halloween-horror-nights.test.mjs. README/report contain delivery provenance. DEBUG fixtures are excluded from Release builds.

IPA: `PIVOT-1.14.4-100.11.1.ipa`, 2,846,592 bytes. SHA-256: `7c32eb0dde29886ff88436f8df18b731163c71732ebb3f6713e23bcf993d702b`.

Source publication: `9d49d5bbfaad34b4f6916a4ceb5e04b0a5fe9dfd`. Immutable asset commit: `9133aef0157a92993a6e8491fb6b29cabde7e6cd`. [Direct IPA](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/9133aef0157a92993a6e8491fb6b29cabde7e6cd/PIVOT-1.14.4-100.11.1.ipa).

ZIP integrity, unchanged identifiers and iOS 17 minimum, unsigned device platform and absence of DEBUG fixture names/launch arguments in the Release binary were verified. Normal-size screenshot reviewed: the unchanged zero wait remains visible with a Live badge. Screenshots use simulator sample data, not actual park observations. All 33 native files match the private source mirror. Existing native CLLocationManagerDelegate/MainActor warnings remain; no configured SwiftLint pass is claimed. No GitHub release, main merge, backend deployment, paid feed or permissions change.

Refresh the existing PIVOT source in SideStore, then update the installed PIVOT app using the same signing identity to retain data.

Fixes HHN house waits disappearing when an unchanged posted wait has an older provider timestamp. Fresh house observations keep valid posted waits, including zero; missing, invalid, future-dated, failed and expired observations remain unavailable. HHN house feed health is independent of regular rides. The app can refresh houses from the same free ThemeParks.wiki provider when the server has omitted waits, with bounded requests and retry backoff. The compact Halloween layout and existing favorites/completion data are preserved. Update the existing PIVOT app with the same SideStore signing identity. Physical SideStore installation remains untested.

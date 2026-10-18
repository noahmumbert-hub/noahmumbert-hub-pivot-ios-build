# PIVOT 1.15.3 candidate

Prepared October 18, 2026. Draft source and an unsigned IPA are available; the SideStore source and published release are unchanged.

An elapsed reopening window now says it is waiting for a fresh ride update instead of declaring a final miss. A current, matching closed observation is labeled provisional while delayed source evidence may still arrive. The October 17 Figment regression preserves the original miss separately from the revision's in-window source reopening. This is an evidence/presentation correction, not a forecast calibration or accuracy claim.

## Build and identity

- Tested source: `97b0c478ac2f81bacce3700172f4150b7598291e`, based on `feat/reopening-reliability`. This note is a later documentation-only addition.
- Draft: [PR #5](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/pull/5).
- Successful [build 29, attempt 1](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/39096061012): macOS 15, Xcode 26.3.
- IPA: `PIVOT-1.15.3-100.29.1.ipa`, 2,972,788 bytes.
- SHA-256: `e67463c705e75d0204582f68e579a83d97efddd990fe6b522dd298ed9d86aa99`.
- App: `com.noahmumbert.PIVOT`; widget: `com.noahmumbert.PIVOT.LiveActivityWidget`.
- Both targets: version **1.15.3**, build **100.29.1**, iOS **17.0+**, iPhoneOS platform. Project build is 30; CI supplies the build number above.

Download the `PIVOT-SideStore-29-1` workflow artifact, extract it, and import the contained IPA into SideStore. Artifact retention is 14 days. The IPA is unsigned; SideStore must sign it with the existing account. Existing bundle IDs, persistence keys, signing/entitlement configuration and HHN/Plan features remain intact. Do not delete the installed app to apply an update.

## Validation

- **175/175 unit tests passed.** Includes the existing freshness, retained-cache, location and weather regressions plus the exact delayed-open boundary presentation fixture.
- **13/13 UI tests passed on the iPhone 16 Pro simulator.** Includes HHN preview/live/Saved states, favorite/completion persistence, large text, and Plan-owned crowd/prediction controls. Screenshots use fixture park data.
- **Release archive and IPA package checks passed.** Independently verified ZIP CRC, SHA-256, app/widget Info.plists, versions and platform. No embedded profile or code signature, as expected for SideStore signing.
- Existing build warnings remain: location delegate actor isolation under Swift 6, supported orientations and skipped AppIntents metadata extraction. Current project language mode builds successfully.
- **Unrun:** physical iPhone upgrade, saved-data retention through a physical upgrade, SideStore signing/install, VoiceOver and real network/park validation. Simulator/source fixtures are not physical-device testing.

Run 39094654738 passed 175 unit tests but encountered a stale settings assertion expecting version 1.15.2. The assertion now expects 1.15.3. That run and 39095708674 were superseded/canceled and are not counted as full passes. Run 39096061012 is the complete passing validation used for this candidate.

## Changed source

`PIVOT/Models/PivotModels.swift` adds optional observation/episode metadata for compatible decoding. `PIVOT/Models/PivotFormatting.swift` gates elapsed-window wording on evidence. `PIVOT/Views/RadarCardView.swift` describes post-window closure evidence as provisional. `PIVOTTests/PIVOTTests.swift` covers the exact boundary and updated wording. `PIVOTUITests/PIVOTUITests.swift` tracks the candidate version. `PIVOT.xcodeproj/project.pbxproj` advances the version/build without changing app identity.

No release publication, source-feed update, merge, deployment, production data rewrite, permission change, paid service or model retuning was performed.

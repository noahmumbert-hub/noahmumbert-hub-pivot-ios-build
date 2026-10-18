# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.15.4 / build 100.31.1**, iOS 17.0+.

EPCOT opening-hours protection

Scheduled and unverified preopening closures no longer produce breakdown forecasts or overnight closure timers in the iOS app. The verified October 18 openings for Figment, Living with the Land and Gran Fiesta remain separate from park-wide early entry. Missing attraction eligibility is shown as unverified; the scheduled opening time alone never marks a ride open.

Fresh source updates cannot validate forecasts or timers carried over from before the attraction's operating session. Existing saved preferences, plans, app identity and the prior native reliability improvements are preserved.

This release changes native presentation, including its inputs to Radar, planning, local alert processing and app-driven Live Activities. Separate server-side eligibility, evaluation and export changes are prepared for review; installing this IPA does not deploy them or rewrite historical forecasts.

IPA SHA-256: `b13da69f24949fb21fb4d239658e87d4857373cec1c6590997be51365055c15b`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/39136348588).
The unsigned IPA preserves `com.noahmumbert.PIVOT` and its Live Activity extension.
Install as an update using the same signing identity; keep the existing app installed to retain saved data.
Native unit and simulator UI tests passed for this build. Physical SideStore installation remains untested.
This update contains native changes; installing it does not deploy backend fixes.

This branch hosts downloads permanently, independently of expiring Actions artifacts.
The source URL remains constant; IPA URLs are pinned to immutable Git commits.
The old 1.13.0 file is retained for history but is not listed in the source.

## Publish a future update

Build/test a newer native version with the existing Actions workflow, download its IPA and build-info.json,
then run `scripts/publish-sidestore.py` from the public source checkout with those files and a release-notes file.
Use `--publish` only when publishing is authorized. The helper verifies archive identity, app/extension versions,
checksum, successful build provenance and increasing versions before updating this branch.
No automatic publishing, workflow permission changes or signing credentials are configured.

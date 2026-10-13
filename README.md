# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.15.1 / build 100.22.2**, iOS 17.0+.

PIVOT 1.15.1 — Crowd and wait forecasts on Plan

• Find the crowd meter and park/day comparisons beneath Your day on the Plan tab.
• Open Predicted waits on Plan and choose a ride to see its hourly estimates and lowest-wait suggestion.
• Waits and ride information focus on posted waits and recent observations.
• Existing learned history, favorites, plans, app identity, and SideStore compatibility are preserved.

Forecast calculations and learning thresholds are unchanged. Predictions remain preliminary and need sufficient historical observations.

IPA SHA-256: `07b39c083f1c94e096896f1767c9c9b0e8036df21eb98394c605251279ac182f`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38332103121).
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

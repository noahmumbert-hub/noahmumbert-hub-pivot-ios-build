# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.18.3 / build 100.177.1**, iOS 17.0+.

Waits uses less space between the park card and Current rides, with smaller Recent observed waits controls and less vertical padding. Text keeps its normal size and expands with Dynamic Type.

Map shows current waits when a fresh provider response confirms an unchanged value. Feed status and refresh are available on the map, and refresh continues in full screen and resumes when returning to the app. Failed or expired responses still withhold unverified waits.

IPA SHA-256: `c02d0b9f9e40abb5dfafde2c5ae960f10e752646efb74c545e007f1d3ffe4b3d`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41402012227).
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

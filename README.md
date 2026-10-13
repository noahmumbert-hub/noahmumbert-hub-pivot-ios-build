# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.15.2 / build 100.26.1**, iOS 17.0+.

Reopening guidance now shows uncertainty when ride history or current observations cannot support a time. Expired windows stop displaying as upcoming, and saved or failed refreshes cannot keep an exact reopening guess visible.

Weather guidance separates mapped lightning clearance from the park's reopening decision. Unsupported weather times and older push estimates are withheld. Lock Screen guidance expires with its supported window.

You may see fewer numeric forecasts while evidence is limited. This update improves forecast reliability and labeling; a more accurate timing model still needs validation against recent forecast outcomes. Favorites, plans, settings and the existing app identity are preserved.

IPA SHA-256: `59e313250f3f72961f78e96b09f351fb2030b5e46bb9f5f0ddd3003fa421ca7b`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38392069570).
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

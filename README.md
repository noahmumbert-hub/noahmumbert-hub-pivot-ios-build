# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.14.2 / build 100.8.1**, iOS 17.0+.

Halloween Horror Nights gets a clearer purple-and-amber layout, larger wait numbers, readable house statuses, search, and All houses/Favorites/To do filters. A favorite-house checklist tracks your night; existing favorites, sorting and completed houses are preserved. Preview, saved and unavailable data have distinct labels, and stale or missing waits stay unknown. Large text layouts and touch targets were checked in the iPhone simulator. This native update includes the previous 1.14.1 fixes and preserves the existing app and Live Activity identity. Keep PIVOT installed and update it using the same SideStore signing identity. Physical SideStore installation remains untested.

IPA SHA-256: `c016400d0b89fbf404f2b3666628a9e2cf4fdac9b3351444b6b5b808d78006da`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38087339360).
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

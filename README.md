# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.18.5 / build 100.328.1**, iOS 17.0+.

Illustrations now download separately so future app updates can stay small. All 1,082 accepted illustrations retain their original bytes, exact ride identities and credits.

Internet is needed once for artwork, including illustrations previously bundled in 1.18.4. The old app bundle is replaced during an update, so a direct upgrade cannot migrate those images. Photos or placeholders remain available while an illustration is not yet saved. In Settings → Artwork downloads, you can save all originals (about 219 MB), pause, and resume.

Verified downloads remain available offline across ordinary app updates and are reused without downloading them again. New artwork downloads pause when storage is tight; valid saved originals are kept. Keep PIVOT installed and use the same signing identity to retain saved artwork and app data. Existing park cards, live waits, Map behavior, planning, accessibility layouts and attribution remain included.

IPA SHA-256: `cca984c583ea412054b8148516aea2badca45d1f943e7d307faeac7c2175b879`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/42311737865).
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

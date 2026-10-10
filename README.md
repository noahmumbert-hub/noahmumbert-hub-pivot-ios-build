# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.14.4 / build 100.11.1**, iOS 17.0+.

Fixes HHN house waits disappearing when an unchanged posted wait has an older provider timestamp. Fresh house observations keep valid posted waits, including zero; missing, invalid, future-dated, failed and expired observations remain unavailable. HHN house feed health is independent of regular rides. The app can refresh houses from the same free ThemeParks.wiki provider when the server has omitted waits, with bounded requests and retry backoff. The compact Halloween layout and existing favorites/completion data are preserved. Update the existing PIVOT app with the same SideStore signing identity. Physical SideStore installation remains untested.

IPA SHA-256: `7c32eb0dde29886ff88436f8df18b731163c71732ebb3f6713e23bcf993d702b`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38092438641).
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

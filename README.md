# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.15.5 / build 100.32.1**, iOS 17.0+.

Fast & Furious – Supercharged has permanently closed and is removed from active Universal Studios Florida ride listings, temporary-closure forecasts, Radar, plans and active counts. Stale or incorrect provider entries cannot bring it back. Historical records and saved preferences remain intact.

This update preserves PIVOT 1.15.4 opening-hours protection and prior improvements. Native presentation works with the existing server; the separate backend retirement candidate is not deployed by this release. Old saved offline packs remain historical snapshots.

IPA SHA-256: `af2b95b60c821d177095a709761ff61c0c31836381fb721c68662c8ed070dba0`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/39140398941).
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

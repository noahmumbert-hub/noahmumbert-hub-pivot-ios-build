# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.15.6 / build 100.34.1**, iOS 17.0+.

Loading and responsiveness improvements

PIVOT reuses timestamp parsers during live-response decoding and reuses time-label formatters during view updates. Switching parks can start the new park request while an older request finishes. Crowd browsing shares an overlapping selected-park refresh, with its loading indicator preserved.

Freshness rules, the five-second foreground refresh cadence, last-good data, and failure labels remain unchanged. This release includes the Supercharged permanent-retirement removal and EPCOT opening-hours fixes from 1.15.5 and 1.15.4. Saved preferences and app identity are preserved. Backend and website deployment are separate.

IPA SHA-256: `b82d0d24ea8f2f04e6dd554f75996a20b4be7f8597cb2b5d9c755356dd7c8cad`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/39141813803).
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

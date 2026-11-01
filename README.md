# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.18.1 / build 100.138.1**, iOS 17.0+.

Adds 17 accepted Florida ride illustrations for EPCOT, Magic Kingdom and SeaWorld Orlando. All 29 existing illustrations remain, for 46 of 145 Florida catalog rides; 99 remain unfinished. Preserves native ride search, every observed-wait label, lowest-wait predictions, best reopening estimates and readability improvements. Illustrations retain their AI-generated labels and reference attribution. Remaining artwork continues independently.

IPA SHA-256: `4599e0ebfc3ce1cac001544a10a48177ff71f6349f62663263ae262d9f6df45f`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41306487772).
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

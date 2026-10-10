# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.14.3 / build 100.9.1**, iOS 17.0+.

Halloween Horror Nights uses a smaller event card and a slim favorites progress strip so houses appear sooner. The moon icon and purple/amber theme remain, with readable event date, hours, ticket notice and Live/Preview/Saved labels. Existing favorites, completion, sorting and previous fixes are preserved. Update the existing PIVOT app using the same SideStore signing identity. Physical SideStore installation remains untested.

IPA SHA-256: `9f060d998e29bd08298b9d3fdd701c44bfdb7ac4f3449a6fb536166d0097853e`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38088227371).
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

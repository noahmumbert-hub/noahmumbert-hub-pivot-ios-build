# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.17.0 / build 100.61.1**, iOS 17.0+.

Refreshed park and ride screens across all 32 parks, with the original PIVOT title restored at the top.

A dark layout with rounded cards, park and ride photos where available, clearer wait times, and convenient search, sorting and open/down filters. Park hours, early entry and ride details remain specific to each park.

Native map gestures, zoom and full-screen controls are retained, along with planning, favorites and progress controls. Light/System appearance and large-text layouts remain available.

IPA SHA-256: `e053795af448c53cba05fba4268bba0e9cdf0cf6e6a9a40850bef2e94a5f09a1`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41208980268).
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

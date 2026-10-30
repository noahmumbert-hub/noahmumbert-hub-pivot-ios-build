# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.16.0 / build 100.36.1**, iOS 17.0+.

PIVOT 1.16.0 — A simpler Plan and park maps

Plan now leads with your remaining route and a compact favorites/visit setup. Mark a ride Done or Skip today directly from the route. Fixed stops, full progress, crowd predictions, and offline packs remain available in expandable sections; timing and availability warnings stay visible.

Map replaces Radar in the tab bar. Explore every supported park, filter rides, food, and shows, search places, browse the list, and check fresh ride status. Restaurant pins are locations, not published operating hours. Closures, selected-ride reopening guidance, and park weather remain under More.

This update preserves the existing app identity, saved favorites/progress, manual starts, fixed show stops, offline packs, smart alerts, Live Activities, and the reliability/performance fixes in 1.15.6. The bundled source-backed map catalog was checked October 30. Retired rides remain excluded from active map browsing. Website and backend deployments are separate.

IPA SHA-256: `22aa2f25e7b68120b69a530153b7cd4ac59b3efe01215968cba3e9b4d9b58a7c`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41112611079).
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

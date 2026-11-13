# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.18.6 / build 100.344.1**, iOS 17.0+.

PIVOT's logo, alert and refresh controls, and park selector now start in the same place across Waits, Plan, Shows, Map, and More. Map keeps a compact park selector so the map remains usable. Long park names and larger text can wrap without clipping the controls.

The refresh circle and PIVOT wordmark have more room to render completely. Existing live waits, planning, shows, map controls, alerts, park schedules, illustration credits, and persistent artwork downloads remain available. Artwork still needs an initial internet download and then remains available offline; the app update does not bundle the 1,082 original illustrations again.

IPA SHA-256: `d1db9b0f569b43219f544a2806f7b0b41e0e86d215261a757e1c0ded936b014f`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/42642574966).
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

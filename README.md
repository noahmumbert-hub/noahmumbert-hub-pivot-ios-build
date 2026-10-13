# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.15.0 / build 100.21.1**, iOS 17.0+.

PIVOT 1.15.0 — Predicted waits and park crowds

• A compact crowd meter on Waits uses current posted waits to estimate how busy the park feels.
• Compare supported parks and visit dates, including observed past days and preliminary future estimates.
• Open a ride to see hourly wait estimates and the lowest estimated remaining wait, once enough history is available.
• Forecasts learn from real observations on this device and adjust for today's queue pressure when coverage allows.
• Learning states, confidence labels, missing-hour gaps, and failed-data handling keep unavailable data from looking like a quiet park.
• Existing app identity, saved choices, compact HHN design, and SideStore compatibility are preserved.

Crowds are a wait-based estimate, not attendance or park capacity. Ride forecasts and future crowd ratings need at least three previous observed days. This first model is preliminary and has not been calibrated against real-world outcomes; holidays, events, weather, and operations can change waits. No paid feeds or backend deployment were added.

IPA SHA-256: `d1b581966bac1a6fcab5871df234992195527d12bdd739eb77a033a9db3e30ad`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38330317542).
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

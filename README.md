# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.18.2 / build 100.149.1**, iOS 17.0+.

Compact ride search, sorting and status filters now share the Waits list with their results.

Unchanged posted waits remain visible when a fresh live response confirms them. Stale or failed feeds still withhold unverified waits.

Removed the artwork badge from thumbnails. Ride details retain truthful illustration credits and reference rights.

Added 73 accepted Florida ride illustrations, bringing the selected coverage to 119 of 145 catalog rides, with 26 remaining gaps. All previously published illustrations are preserved.

Observed-wait dot labels, lowest-wait predictions and best reopening estimates remain included.

IPA SHA-256: `f9092abdfcdef0001732ffacee0ea9c98b7f06885c7dad5bafde69b9cb40279d`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41344687017).
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

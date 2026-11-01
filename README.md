# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.18.0 / build 100.137.1**, iOS 17.0+.

PIVOT 1.18.0 brings the requested native wait updates together with accepted Florida artwork.

• Search rides by name while keeping current waits and ride status connected.
• See a wait label on every observed chart point, with complete local times.
• See the lowest-wait prediction when fresh, sufficient evidence supports it.
• See the best reopening prediction beside its supported window.
• Read full Radar selections and supporting descriptions at larger text sizes, with clearer chart labels and enlarged hourly views.

This release includes 29 accepted AI-generated Florida ride illustrations across ten parks, including Fyre Drill, Curse of the Werewolf and Hiccup’s Wing Gliders at Epic Universe. Coverage is partial: 29 of 145 Florida catalog rides are covered, with 116 remaining gaps. Other park artwork continues separately. Unaccepted drafts are excluded; generated-artwork labels and source attribution are retained.

Wait and reopening predictions are estimates. Stale, missing or insufficient evidence continues to withhold recommendations. Existing app identity and saved preferences are preserved.

Install as an update to the existing PIVOT app with the same signing identity. Keep the app installed to retain its data. The IPA is unsigned for SideStore to sign; physical-device installation remains untested.

IPA SHA-256: `b014a4be74d35ec81861f2266df8a7c650130ca50e8c8b50827ce0fb413e445e`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41288969074).
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

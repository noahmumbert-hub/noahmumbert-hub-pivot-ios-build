# PIVOT SideStore updates

Add this source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.14.1 / build 100.3.1**, iOS 17.0+.

Saved lightning observations now expire and clearly show saved or unavailable data. Empty or unhealthy ride feeds no longer report that all rides are clear. Failed refresh status stays saved when switching parks, and delayed GPS results no longer override manual park choices. Existing 1.14 features, saved-data keys and the Live Activity extension are preserved. Native update only; backend changes are separate.

IPA SHA-256: `6032370d60a08c2ae4dcb960477182b6a2d4395d15dcf3d05835ba52f04efe0d`. [Tested build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38080886085).
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

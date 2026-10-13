# PIVOT iOS builds

Public iOS source and GitHub-hosted macOS builds for installing PIVOT through
SideStore. The web application, backend implementation, and private repository
history are not included here. The app uses the existing PIVOT backend.

## Build an IPA

1. Open **Actions → Build SideStore IPA → Run workflow**.
2. Select the intended branch and wait for a successful run. The latest tested native wait/crowd update is on `feat/wait-crowd-forecast`, including the compact HHN UI and October 8 native audit fixes; `main` remains the older source until reviewed.
3. Download the **PIVOT-SideStore** artifact at the bottom of the run page.
4. Extract the downloaded ZIP. It contains an `.ipa`, `SHA256SUMS`, and
   `build-info.json` identifying the source commit and app version.
5. On your iPhone, open SideStore and import the `.ipa` using its **+** button.
   SideStore signs the app with your Apple account before installation. Follow
   SideStore's pairing and VPN requirements for your installed version.

The IPA requires iOS 17 or later and includes the Live Activity extension.
It is intentionally unsigned: no Apple ID, certificate, provisioning profile,
or signing password is stored in this repository or needed by its workflow.
SideStore's Apple-account, App ID, extension, and periodic-refresh limits still
apply. A successful archive does not prove installation on a particular phone.

Builds also run when app or build-workflow changes reach `main`. Build artifacts
expire after 14 days; run the workflow again when needed. Repository access is
public, although GitHub may require login to download Actions artifacts.

## Build from a cloud chat

```bash
gh workflow run build-ipa.yml --repo noahmumbert-hub/noahmumbert-hub-pivot-ios-build --ref feat/hhn-ui-refresh
gh run list --repo noahmumbert-hub/noahmumbert-hub-pivot-ios-build --workflow build-ipa.yml
gh run download RUN_ID --repo noahmumbert-hub/noahmumbert-hub-pivot-ios-build --name ARTIFACT_NAME
```

Develop future native changes in this repository and push them to `main` to
produce a new IPA. Changes to the private web/backend repository do not
automatically update this public copy. Copy only intended iOS source changes;
do not copy private server files or history. Each cloud task is isolated; use
the existing checkout and do not create a Git worktree unless requested.

## Local Mac build

Install Xcode 26.3 and run:

```bash
export DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer
PIVOT_BUILD_NUMBER=100.3.2 bash scripts/build-ipa.sh
```

The workflow uses the standard `macos-15` runner. Standard GitHub-hosted
Actions builds of public repositories are free under GitHub's current policy;
this workflow does not use a paid larger runner.

## Source provenance

The initial iOS project was copied from PIVOT source commit
`882055c8a5e267f2f0df0baf2e17bb3c901f5666` (release `2026.09.26.2`, native version
`1.13.0`). Only the app, Xcode project, Live Activity extension, and native
test targets were copied; the public repository starts with fresh history.


## October 8 audit candidate

The candidate advances to **1.14.1** from the verified published **1.14.0 / build 22** source archive `PIVOT-iOS-2026.10.04.2.zip`. Archive SHA-256: `1dd32326df0c8540cbcd98e4df2bac73050002a2cb3cf07501c199e2c0eb5f14`. Current 1.14 features are retained.

Native changes expire saved lightning guidance, require valid ride observations before reporting no closures, preserve failed cache health across park switches, and reject delayed GPS results after manual choices. Bundle identifiers and preference keys are unchanged.

[Verified candidate build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38080886085): 142 Xcode unit tests and 5 simulator UI tests passed. Unsigned IPA **1.14.1 / 100.3.1**, SHA-256 `6032370d60a08c2ae4dcb960477182b6a2d4395d15dcf3d05835ba52f04efe0d`. Download the **PIVOT-SideStore-3-1** artifact and import it as an update to the existing PIVOT app using the same signing identity. Keep the existing app installed to retain its data. Physical iPhone / SideStore installation remains untested.

The candidate has not been merged or published as a GitHub release. The tested native update is available through the SideStore source below. Backend fixes are reviewed separately and are not applied by installing this IPA. For manual Mac builds, set an explicit build number above the one already installed; the workflow sets it automatically.

## SideStore update source

In SideStore, open **Sources → +** (usually under Browse) and add:

```text
https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json
```

PIVOT **1.15.1 / 100.22.2** is the latest listed update; earlier tested updates remain in version history. Install it as an update to the existing PIVOT app, using the same signing identity. Keep the app installed to preserve saved data. The source and IPA downloads are public and do not expire with Actions artifacts. Physical SideStore installation remains untested.

Future updates use this same source URL. Each native update still needs a new tested IPA; SideStore downloads and signs it when you choose to update. Publishing is manual, after successful Xcode tests and archive validation. Workflow permissions are unchanged.

After downloading a successful newer build's IPA and metadata, prepare the source update with:

```bash
python3 scripts/test-sidestore-source.py
python3 scripts/publish-sidestore.py --ipa /path/to/PIVOT-new-version.ipa --info /path/to/build-info.json --notes /path/to/release-notes.txt
```

Add `--publish` when publication is authorized. The helper checks checksum, device platform, app and extension identity/version, successful build/test provenance, and version continuity. It appends immutable downloads and updates only the `ipa-builds` branch, preserving the source checkout and existing version history. New entitlements require an explicit permissions review before the helper can publish.

## Halloween Horror Nights update

**1.14.2 / 100.8.1** improves the native HHN layout with a purple/amber event header, readable house cards, larger waits, search, Favorites/To do filters and favorite completion progress. Existing preferences and app/widget identity are preserved. Stale, missing and preview waits stay unknown.

[Verified build](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38087339360): 149 unit tests, 10 iPhone simulator UI tests and the Release device archive passed. The update is available from the existing SideStore source. Main remains the older source pending review; use `feat/hhn-ui-refresh` for the current tested native changes. [Validation and delivery report](docs/hhn-ui-update.md) includes failed/superseded runs, limitations, checksum and release notes.

## Compact HHN follow-up

**1.14.3 / 100.9.1** replaces the large event hero with a compact card and a slim favorites progress strip, bringing the houses closer to the top. [Xcode run 38088227371](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38088227371) passed 149 unit tests, 10 simulator UI tests and the Release archive. The tested update is published through the same SideStore source. [Validation and delivery report](docs/hhn-compact-update.md).

## HHN posted-wait fix

**1.14.4 / 100.11.1** restores valid unchanged house waits from fresh observations and separates HHN house health from regular-ride feed health. The app can recover house waits omitted by the backend using the same free ThemeParks.wiki source, with bounded requests. Invalid, future, missing, failed and expired observations remain unavailable. Compact layout and saved data are preserved.

[Verified Xcode run](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38092438641): 154 unit tests, 10 simulator UI tests and Release archive passed. Available through the same SideStore source. [Validation and delivery report](docs/hhn-wait-update.md) distinguishes source/recorded-response tests, baseline lint/typecheck failures, simulator checks and unrun physical installation. Prepared backend/web source changes are not deployed by installing this IPA.

### Hourly ride waits and park crowds

**1.15.0 / 100.21.1** adds a compact wait-based crowd meter, a park/date browser, and hourly ride wait estimates with the lowest estimated remaining wait in ride details. Predictions learn from real observations on this device and show Learning until at least three previous days are available. Estimates are preliminary and are not attendance or capacity measurements; no paid feeds or backend deployment were added.

[Verified Xcode run](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38330317542) passed 167 unit tests, 12 simulator UI tests, and the Release archive. The tested IPA is available through the existing SideStore source, preserving identities and saved choices. [Validation and delivery report](docs/wait-crowd-forecast.md) includes the exact model, learning limits, failed/superseded checks, corrected simulator chart, immutable IPA checksum, and unrun physical installation/calibration.

### Crowd and forecast controls on Plan

**1.15.1 / 100.22.2** puts the crowd meter, park/date browser, and a ride forecast selector beneath Your day on the Plan tab. Waits and ride information retain posted waits and observed history. Learned data and forecast calculations are preserved.

[Verified Xcode run, attempt 2](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38332103121) passed 167 unit tests, 13 simulator UI tests, and the Release archive. The update is available through the existing SideStore source. [Validation and delivery report](docs/plan-crowd-update.md) includes the actual tab-placement check, inspected screenshot, first-attempt simulator startup failures, checksum, and unrun physical installation.

# PIVOT iOS builds

Public iOS source and GitHub-hosted macOS builds for installing PIVOT through
SideStore. The web application, backend implementation, and private repository
history are not included here. The app uses the existing PIVOT backend.

## Build an IPA

1. Open **Actions → Build SideStore IPA → Run workflow**.
2. Select `main` and wait for the run to finish successfully.
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
gh workflow run build-ipa.yml --repo noahmumbert-hub/noahmumbert-hub-pivot-ios-build --ref main
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
PIVOT_BUILD_NUMBER=100.1.1 bash scripts/build-ipa.sh
```

The workflow uses the standard `macos-15` runner. Standard GitHub-hosted
Actions builds of public repositories are free under GitHub's current policy;
this workflow does not use a paid larger runner.

## Source provenance

The initial iOS project was copied from PIVOT source commit
`882055c8a5e267f2f0df0baf2e17bb3c901f5666` (release `2026.09.26.2`, native version
`1.13.0`). Only the app, Xcode project, Live Activity extension, and native
test targets were copied; the public repository starts with fresh history.

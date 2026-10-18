# Native simulator monitoring — prepared, not active

Noah authorized cloud-coordinated GitHub macOS simulator observations, conditional on no new paid usage. This package is deliberately inactive: the cron is commented out and the job condition starts with `false`. No simulator run or artifact upload was dispatched for this work.

## Cost and existing setup, checked October 18, 2026

- Repository `noahmumbert-hub/noahmumbert-hub-pivot-ios-build` is public. `macos-15` is a standard GitHub-hosted runner; no larger runner, self-hosted runner, Noah's Mac, cache, external service, credential or permission addition is used.
- Only the existing `Build SideStore IPA` workflow was registered. Its triggers are manual dispatch and path-filtered pushes to `main`; no existing native schedule was found. The separate website availability observer remains separate.
- Standard runner time in public repositories is free. GitHub's billing documentation also describes a pooled allowance for Actions artifact and Packages storage. Current unexpired artifacts in this repository totaled **454,298,577 bytes (about 433.3 MiB)**. This is neither total account usage nor accrued storage usage.
- Both `GET /users/noahmumbert-hub/settings/billing/usage` and `GET /users/noahmumbert-hub/settings/billing/shared-storage` returned **403 Resource not accessible by integration**. The user API did not expose the account plan. No billing or permission settings were changed.
- **Activation blocker:** no reliable evidence of free shared storage headroom or an effective zero-spend stop for the required retained screenshots/test artifacts. A small cap and short retention do not alone prove zero cost. No artifact deletion was performed.

Sources: [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [standard runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [schedule semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

## Proposed limits

| Item | Bound |
| --- | --- |
| Schedule, currently disabled | `37 14 * * *`: once daily at 14:37 UTC, 10:37 EDT / 09:37 EST |
| Runner | One standard `macos-15`, one iPhone simulator, no matrix |
| Job | 27-minute hard timeout; compile once; no test retries |
| Concurrency | One global monitor group, no overlapping execution |
| Fixtures | Existing 187 unit tests and 4 selected fixture UI tests |
| Live native UI | 2 existing smoke tests, maximum 4 minutes |
| Explicit API probes | EPCOT (5) and Universal Studios Florida (65); one GET each, no retry or redirect, 5-second connect / 15-second total curl timeout, 2 MiB body limit |
| Retention | One evidence ZIP per run, maximum 20 MiB, one day |
| Evidence | Source SHA, monitor SHA, toolchain/simulator, phase timestamps/exits, exported XCTest summaries, screenshots, log tails, separate API observations, inclusion/omission manifest |

The app's normal live UI smoke can also make its usual requests while running; the two-request cap applies to explicit API probes. No collection trigger, refresh POST, homepage ping loop, prediction-score update, release build, SideStore publication or deployment is included. UI polling ends when the bounded test phase ends. Logs and job summaries remain visible under the repository's normal Actions retention; full xcresult databases are not uploaded. Cap omissions, export failures, timeouts and missing completion records are unverified evidence, not a pass. A hard job timeout can prevent artifact upload.

## What the checks establish

1. **Deterministic regression:** unit coverage for loading ownership across park changes, overlapping refresh suppression, retained-data/feed failures, opening eligibility, retired rides, ride contracts, source clocks and original/revised forecasts. Fixture UI verifies hourly forecasts, saved forecast wording, HHN ride favorites/completion/relaunch, and saved/empty ride-feed presentation. These cases cannot establish live API health or representative model accuracy.
2. **Live native UI smoke:** real app launch, Magic Kingdom Plan/Waits navigation and forecast-control placement, then a separate launch and park search/selection of Cedar Point. Existing assertions verify navigation responsiveness; a screenshot-only patch retains the selected-park and saved-forecast screens. Passing these tests does **not** prove rides loaded, forecasts were available, or every park switched correctly. Loading/data behavior is covered deterministically above; actual visible live state is retained for review.
3. **Live API observation:** HTTP/content type/JSON/park identity/ride-list contract and reported feed state, fetched timestamp, provider status timestamps, ride and forecast counts. Five-minute fetch age is an observation threshold, not a model deadline; provider status time is kept separate. Original prediction windows are not revised or scored. An inactive park is reported explicitly. Empty data, transport errors and unhealthy/stale responses remain separate findings; no synthetic zero-down-ride count is emitted.

Fixtures and live UI have separate xcresult bundles, workflow steps and exit records; API findings are separate JSON. A fixture failure does not suppress the live observations if compilation succeeded. A compile failure makes later observations unverified.

## Source and activation procedure

The application checkout is pinned to released **1.15.6**, commit `04b1c98d588b471479631f6e9df2aab4e8a1d05d`. Application code is unchanged. The screenshot patch changes XCTest attachments only, applied to the ephemeral runner checkout. The existing release run [39141813803](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/39141813803) passed 187 unit and 13 UI tests; it is prior evidence, not a validation run of this new workflow.

Default `main` is older (`85770e40a4c2c00cb9c798053d9b984b6c011275` when checked). The workflow checks out monitoring definitions separately from the immutable application source, so **only this package's commit** needs to be cherry-picked onto default `main`; do not merge unrelated application history merely to install monitoring. Its changed paths do not match the existing IPA build push filters.

Before activation, obtain current billing evidence establishing no-cost retention (including pooled usage/allowance and any effective stop), without adding billing access or enabling paid usage. Then install the monitoring-only commit on default `main`, preserve the public-repository condition while replacing the leading `false`, and run one manual verification with the cron still commented. Review all phase results and retained screenshots; only after a successful, safely free validation should the daily cron be uncommented. No activation or verification run was performed here. Recheck public visibility and storage assumptions at that point. GitHub cron runs only from the default branch, may be delayed, and public-repository schedules can be disabled after 60 days without activity; this is periodic observation, not continuous monitoring.

Local validation passed: shell syntax, Python compilation, **9 regression tests** (HTTP/HTML/JSON/identity/clock handling, bounded requests and evidence size/log-tail preservation), screenshot patch applicability against pinned source, inactive/public/read-only configuration assertions, and **actionlint 1.7.7**. Xcode/simulator execution remains unverified for this workflow because this workspace is Linux and no artifact-producing cloud run was authorized without establishing no cost. No new run or screenshot artifact link exists yet.

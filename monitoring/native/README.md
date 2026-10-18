# Native simulator monitoring — logs only

Noah authorized cloud-coordinated GitHub macOS simulator observations with no new paid usage. Retained screenshots have been replaced by normal workflow logs and a textual job summary. Screenshots and xcresult files exist only transiently on the runner and are unavailable after the job. There is no artifact upload, cache, release publication or deployment in this workflow.

## Verified no-cost basis

The repository is public and `macos-15` is a standard GitHub-hosted runner. GitHub documents that standard public runners are free and that workflow logs and job summaries do not count toward artifact storage. [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [standard runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

The job checks public visibility before runner allocation and again after checkout. It has only `contents: read` permissions. No new credentials, billing access, permissions, larger runner, Noah's Mac, artifact storage, cache storage or paid service is used. Earlier billing reads returned 403; those denied reads were not bypassed and are unnecessary for this logs-only design. Existing unrelated artifacts and billing settings were not changed.

## Limits and retained evidence

- Active schedule: once daily at **14:37 UTC** (`37 14 * * *`), 10:37 EDT / 09:37 EST. Installed on default `main` after reviewing the first manual run.
- One standard macOS runner, one iPhone simulator, no matrix, one compilation, no automatic test retries. Global concurrency prevents overlapping monitor runs.
- Hard job limit: **27 minutes**. Compile 12 minutes; fixtures 7; live UI 6; explicit API probes 2; result export/report 2. A hard timeout may prevent the final summary; step logs remain the available evidence.
- Fixture phase: existing **187 unit tests and 4 fixture UI tests**. Separate live UI phase: **2 navigation smoke tests**.
- Explicit API probes: EPCOT (5) and Universal Studios Florida (65), one GET each, no retries or redirects, 5-second connect / 15-second total timeout and 2 MiB response cap. The app's live UI also makes its ordinary requests while tests run; the two-request cap applies only to explicit probes.
- Normal Actions logs retain compiler/test output, pass/fail details and fixture performance measurements. The job summary retains source/monitor SHAs, toolchain, simulator, phase timing/exits, exported XCTest summaries, measurements and separate live API observations. Text sections are bounded to 32 KiB. Retention follows the repository's normal workflow-log policy; no account setting is changed.
- Screenshots are taken by XCTest and exported locally during the run, but **are not retained or available for later visual review**. No binary image data is embedded in logs or summaries. Full xcresult bundles are not retained.

## Interpretation

**Fixture regressions:** loading ownership across park changes, overlapping refresh suppression, retained-data/feed failures, opening eligibility, retired rides, ride contracts, source clocks and original/revised forecasts. Fixture UI checks hourly forecasts, saved forecast wording, HHN ride favorites/completion/relaunch, and saved/empty ride-feed presentation. Fixture results cannot establish live API health or representative prediction accuracy.

**Live navigation smoke:** real app launch, Magic Kingdom Plan/Waits navigation and forecast-control placement, then a separate launch and Cedar Point search/selection. These assertions verify navigation responsiveness, not that live rides loaded or forecasts were available. A screenshot-only test patch changes attachments in the ephemeral source checkout; application code is unchanged.

**Live API observations:** HTTP/content type/JSON/park identity/ride-list contract, feed state, fetch and provider timestamps, ride and forecast counts. The five-minute fetch-age threshold is an observation threshold, not a model deadline. Provider time stays separate; prediction windows are not revised or scored. Inactive parks are explicit; empty/stale/unhealthy data and transport failures remain separate findings, not synthetic zero-down-ride counts. A live API failure can correctly make the workflow red while fixture tests pass.

Each phase has its own step and result record. Fixture failures do not suppress the live observations if compilation succeeded. Missing records or export failures are unverified, never a pass. The existing website availability observer remains separate.

## Source and installation

Application source is pinned to released **1.15.6**, `04b1c98d588b471479631f6e9df2aab4e8a1d05d`. Update this pin deliberately when a newer release should be monitored. Prior release run [39141813803](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/39141813803) passed 187 unit and 13 UI tests; it is not the monitor's validation run.

The workflow checks out monitoring definitions separately from application source. Install only `.github/workflows/native-monitor.yml` and `monitoring/native/` on default `main`; no unrelated application history is merged. These paths do not trigger the existing IPA build workflow. The first manual run has been reviewed and the daily cron enabled. Scheduled workflows run from the default branch, may be delayed, and can be disabled after 60 days without repository activity. This is periodic observation, not continuous monitoring. [GitHub schedule semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

Local checks: shell syntax, **10 Python regression tests**, screenshot-patch applicability against pinned source, workflow lint using actionlint 1.7.7, and assertions that no artifact/cache upload action exists. Runtime verification is recorded in the actual Actions run, including any live-service findings.

## First observed run — October 18, 2026

[Run 39168003000](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/39168003000), monitor source `0cdc4d403f5d838dc366667c8b9f54b5ffaf7f35`, completed with **failure** because the live UI phase exhausted its original four-minute timeout. Compilation succeeded; **187 unit and four fixture UI tests passed (191 total)**. The live XCTest runner logged that it was starting tests only after nearly four minutes, so there were no completed live navigation assertions. This is an unverified live UI result, not a proven application defect. The live UI budget is now six minutes within the unchanged 27-minute job cap; the successful verification run below now validates that budget adjustment for this observed run. No automatic retries are enabled.

Both separate live API probes returned HTTP 200 JSON. EPCOT was `snapshot_observed` (11 rides, feed healthy); Universal Studios Florida was `inactive_park_observed` (13 rides, feed healthy, `parkActive=false`). EPCOT's one non-null estimate is only a count: this monitor did not retain the ride identity or original window and cannot claim a prospective reopening sample. The sole accuracy observer owns prospective forecast capture.

The text reporting step succeeded, retained the 191-test XCTest summary and fixed-fixture performance measurements, and explicitly recorded the missing live UI completion. GitHub's artifact listing for this run returned **zero artifacts**. Screenshots are unavailable after the run. No billing settings or permissions were changed, and no IPA build or deployment was triggered.

## Six-minute verification — October 18, 2026

[Run 39169213781](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/39169213781) tested workflow commit `2a6994e429da660174d39d3af1edf56d9e7d0fc0` and unchanged released app commit `04b1c98d588b471479631f6e9df2aab4e8a1d05d`. It completed **successfully**, with 187 unit tests, four fixture UI tests and both live navigation tests passing (**193 total, zero failures**).

The live step ran 21:52:41–21:57:17 UTC (**276 seconds**, below its 360-second cap). The first test began at 21:56:20.201 UTC, about **219 seconds after step start**. Actual test execution took **51.311 seconds**: Cedar Point search/selection 35.447 seconds; Plan/Waits crowd/forecast-control navigation 15.864 seconds. In the earlier failed run the XCTest runner logged startup near the four-minute cutoff and no test-case start was recorded. These logs identify pre-test infrastructure startup as the immediate timing bottleneck, not a reproduced application assertion failure. They do not identify why the simulator/XCTest startup was slow.

Separate EPCOT and Universal API probes again returned HTTP 200 JSON, reporting `snapshot_observed` and `inactive_park_observed` respectively. Normal logs and the job summary retain the test counts, timing and fixed-fixture measurements. The artifact API returned **zero artifacts**. Screenshots remain unavailable after the job. No app code, timeout beyond six minutes, deployment, permissions or billing settings were changed for this verification. This validates the covered smoke checks on this run, not all native functionality or physical-device behavior.

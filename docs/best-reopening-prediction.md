# Best reopening prediction

The Down ride list, ride information sheet, and featured closure card show the
forecast's central reopening estimate beside its supported reopening window.
Numeric values are labeled `Best prediction · <park-local time> (estimate)`.
An elapsed point within a still-current window is labeled `Earlier best
prediction`; it is never moved forward to the current time.

The time comes directly from `ReopeningEstimate.historicalMedianAt`. It is not
the middle of the window, a lowest-wait suggestion, an official operating time,
or a newly calculated forecast. No forecast calculation or server data changes.

The released backend uses v3 calibration metadata. The on-screen estimate can
therefore accompany an otherwise supported historical range without requiring
v4 calibrated point advice. `ReopeningGuidance.bestGuess` retains its existing
stricter contract for Live Activities. The new `estimatedBestPrediction` is
only screen presentation; a regression test verifies that a v3 screen estimate
cannot promote an unsupported Live Activity best guess.

Existing range validation still applies: current feed and park, current down
status, valid ordered forecast dates, a confirmed closure start, comparable
recent history, acceptable scored coverage when available, and any server
range restrictions. Explicit `showBestGuess: false` still withholds the point.
Weather guidance continues to require verified clearance and supported restart
evidence. Missing, stale, failed, invalid, expired, or unsupported guidance says
`Best prediction unavailable` and never invents a time.

## Integration

This work starts at `feature/ride-illustrations` commit
`090d0e3f23177256a20765e1c831c5d3e0fad577`, which includes the released
1.17.1 source (`741d33d5a922f18eb01c4582a5de3a11d26de049`). Reopening-only
label and fixture work was reused from checkpoint
`680caa1e471e81018641b0de104fb426ffb67f4f`. Its observed-wait and lowest-wait
changes are outside this patch.

The isolated integration branch is `codex/best-reopening-20261031-a18d`.
The shared source checkouts and feature branches were not edited. No release,
SideStore feed change, merge, or Site deployment is part of this work.

## Verification

- Local source checks: `git diff --check`, `bash -n scripts/test-native.sh`.
- SideStore publisher regressions: all 7 Python tests passed.
- Existing artwork validator: 53 packaged illustrations validated; existing
  incomplete artwork coverage is unchanged.
- Focused native scope: `PIVOT_TEST_SCOPE=reopening bash scripts/test-native.sh`.
  Includes forecast median/time-zone checks, passed points, v3/ActivityKit
  separation, unavailable and weather safeguards, row/detail states, and
  accessibility-size closure card presentation.
- Initial native CI tested source commit `15875cf75b2ba70faed8fe810ba3ef48dffc5d9d`.
  - [Initial focused reopening checks on iPhone SE](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41232274376) failed.
  - [Initial full regressions on iPhone SE, 16 Pro, and 16 Pro Max](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41232277475) exposed the same assertion failures; the device archive was skipped.
  Superseded runs `41232043925` and `41232047882`
  were cancelled after the v3 compatibility issue was identified; they are
  not validation receipts for this implementation.

Implementation commits, in order: `4e423416043a490359300739966406ca3e05a4f2`
and `15875cf75b2ba70faed8fe810ba3ef48dffc5d9d`. Native test corrections are
`e3b77a9990cf365790bbb4d235ca8516a54beb5c` and
`078ac919abc904b512ee8a335655e2d382cbe222`. Apply these when integrating
onto the illustration base, or inspect the combined patch if integrating
alongside other checkpoint changes. Documentation-only commits do not change
the tested source; the final native code SHA is `078ac91`.

## Corrections after native evidence review

The actual xcresult databases and attachments from artifacts `13056293450`
(focused SE) and `13055829602` (full iPhone 16 Pro) were downloaded and
inspected. The focused bundle records 8 successful and 6 failed test cases;
the Pro bundle records 231 successful and 5 failed cases. These are failed
validation receipts, not a passing release result.

Four unit tests contained eight failing assertions because iOS 26 formats the
space before AM/PM as U+202F. Commit `e3b77a9` normalizes only U+202F/U+00A0
to ASCII space in test assertions. Expected hour/minute values, AM/PM, and the
New York versus Los Angeles time-zone comparison remain independently checked.
The app formatter and local-time behavior are unchanged.

The SE screen recording shows the filter onscreen while the test tries to
reveal the segmented-control container. The test now targets the actual Down
button. Failure reporting no longer queries the identifier of an element
that cannot be found. The nine-state UI scenario also reached XCTest's
180-second per-test limit on both SE and Pro; it is now three bounded tests
covering the same nine states. No timeout was increased and no scenario was
removed.

The original SE screenshots show supported, v3, uncalibrated, range-only,
stale, missing, and ended states. Pixel inspection confirms that the v3
row displays its actual median with the estimate label beside the window.
The [focused SE rerun](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41238545797)
tested commit `e3b77a9990cf365790bbb4d235ca8516a54beb5c`: all 12 unit tests
and all three normal-size UI tests passed. Their nine modes include supported,
v3, uncalibrated, range-only, stale, missing, ended, failed, and passed-point
states. The three UI groups finished in 72, 87, and 82 seconds, with no timeout.
The remaining SE large-text test failed while revealing Down. Its recording
shows full-screen swipes alternating between opposite sides of the filter.

Commit `078ac919abc904b512ee8a335655e2d382cbe222` uses short, position-based
drags toward the actual content center, bounded above the native tab bar.
The [remaining SE large-text check](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41239620034)
passed: one UI test, zero failures, 95.6 seconds. Its xcresult database was
inspected, and both row and Radar screenshots were reviewed at pixel level.
The row keeps the full window and the two-line best prediction/estimate label
readable on the compact screen. The app's time formatter and reopening
implementation have not changed during these test corrections.

The fresh [full three-device regression run](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41240772511)
tests `078ac919abc904b512ee8a335655e2d382cbe222`. Pro Max completed all 205
unit tests successfully and passed 32 of 33 UI tests, including every reopening
test. Its sole failure is the unchanged map attribution journey: PIVOT opens
Safari at `gspe21-ssl.ls.apple.com`, but the expected page contents do not load
within the existing 20-second assertion. The actual failure recording and
Safari hierarchy were inspected; the hierarchy reports `IsPageLoaded=false`.
SE and Pro subsequently passed: each xcresult database records 205 successful
unit tests, 33 successful UI tests, and zero failures. The unsigned iPhoneOS
archive also passed validation. Its build-info records source `078ac91`,
version/build `1.17.1 / 100.103.1`, and SHA-256
`968b35813838f113782fed05408c0746fb74ef6352202c2d808b3bcb4cd22ab6`;
the downloaded IPA checksum was independently verified.

A request to retry only the failed Pro Max job was initially rejected because
the workflow was still running. Once it completed, GitHub accepted that retry
as attempt 2; job `124663674522` finished with the same single map attribution
test failing on the unchanged source. All 205 unit tests and the other 32 UI
tests, including all reopening tests, passed again. This attempt failed at
the preceding Safari foreground wait (`PIVOTUITests.swift:479`). Its actual
screen recording ends on a black Safari launch screen with the back-to-PIVOT
status-bar link. This differs from attempt 1, which reached Safari and then
failed waiting for the remote attribution page's contents.

The chart thread's independent run `41243279156`, source `869fc53`, failed the
same unchanged test on SE at its remote-content assertion. Evidence artifact
`13058648574` and actual xcresult `13058588781` were downloaded and inspected.
Its Safari hierarchy reports `IsPageLoaded=false`; the screenshot shows the
Apple attribution URL loading over Safari's Start Page. Pro Max retry evidence
`13059299433` and actual xcresult `13058984929` were also preserved. Before
the Legal tap, both recordings show the real native link visible, inside the
map and above the selected-ride card. The evidence supports a Safari cold
launch/page-loading dependency rather than a reopening or attribution-layout
regression; it does not prove that the remote credits successfully loaded.

The full matrix therefore remains **failed**, with successful complete SE and
Pro runs and a blocked Pro Max Legal browser journey. No app code, Legal
assertion, or required scenario was removed or weakened. No additional blind
retry was requested. Coordinate one common harness correction with the chart
owner: prepare and verify Safari readiness before the actual native Legal
tap, retain the real OpenStreetMap and Apple credit assertions, and diagnose
the external page load separately with a bounded wait and URL/load-state
attachments. That proposed correction has not been implemented here, avoiding
conflicting shared-test changes. Nothing has been published or merged.

A generic live API probe was initially denied with HTTP 403 (Cloudflare code
1010). Matching the existing native client's `Accept: application/json` and
`User-Agent: PIVOT-iOS/1.3` headers resolved that access issue without any app,
API, or authentication change. Live snapshots for Universal Studios Florida
and Islands of Adventure were fetched at 20:53:25 and 20:53:57 UTC on October
31, both with `feedHealthy: true`. Their forecasts include the existing
`historicalMedianAt` field; the Universal Studios response uses v3 calibration.
The snapshots also exercise legitimate unavailable cases: a first-seen closure
and zero same-ride samples. Those current observations must not be promoted to
supported point predictions just because a model median exists.

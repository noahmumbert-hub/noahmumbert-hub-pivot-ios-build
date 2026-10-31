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
- Native CI tests source commit `15875cf75b2ba70faed8fe810ba3ef48dffc5d9d`.
  At 19:16 UTC on October 31, GitHub had not assigned macOS runners to any
  current job; results and new screenshot review are **pending**, not passed.
  - [Focused reopening checks on iPhone SE](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41232274376).
  - [Full regressions on iPhone SE, 16 Pro, and 16 Pro Max, plus device archive](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41232277475).
  Both runs remain active. Superseded runs `41232043925` and `41232047882`
  were cancelled after the v3 compatibility issue was identified; they are
  not validation receipts for this implementation.

Implementation commits, in order: `4e423416043a490359300739966406ca3e05a4f2`
and `15875cf75b2ba70faed8fe810ba3ef48dffc5d9d`. Apply both when integrating
onto the illustration base, or inspect their combined patch if integrating
alongside other checkpoint changes. This document is a later documentation-only
commit; native test results must be assessed against the code SHA above.

A direct live API probe from the cloud environment was denied with HTTP 403
(Cloudflare code 1010). Production response verification remains unavailable
through that route; the implementation uses the existing decoded forecast
field, and automated behavior tests use explicit native fixtures.

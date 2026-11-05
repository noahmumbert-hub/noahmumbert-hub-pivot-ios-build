# Run 281 Map diagnostics

Run [281 / 42028374625](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/42028374625)
tested source `3666be4751beca9e9d76b575a6170cac323eeca5`. Pro and SE each passed
224 unit and 94 UI tests. Pro Max passed 224 unit tests and 92 of 94 UI tests.
The two failed assertions remain release gates. The successful unsigned archive
is not qualified for publication by this run.

## What the retained logs establish

- `testLiveMapRefreshReportsRealProviderStatus` completed its manual request and
  observed `Refresh failed; selected ride: Wait unavailable` at 13:30:35 UTC.
  Completion was about 21 seconds after the tap. The API request's existing
  timeout is 20 seconds. That timing is consistent with a timeout but does not
  establish its error code or cause. Pro and SE observed Live in their runs at
  different times. No HTTP status or typed request error was retained for the
  failed Pro Max request.
- `testMapCategoryChangesAndInterruptedSearchRemainUsable` selected Food, opened
  the native category sheet again, and expanded it with the existing drag. Its
  five-second wait for the Rides button to exist and be hittable timed out before
  the Rides tap. Later search-interruption steps were not reached. The logs do
  not establish whether geometry, a covering view, a stale accessibility query,
  or another interaction state caused the failure.

Only source and accessible job logs were reviewed. The CLI download of Max
summary artifact `13423800733` (453,121,346 bytes) returned `Forbidden`; it was
not retried or fetched through another route. Screenshot and recording bytes
were not reviewed. The larger xcresult artifact was not requested. All earlier
denied-access restrictions remain in force.

## Diagnostic changes, without a claimed behavior fix

The original category predicate still queries existence and hittability, with
the same five-second waiter. Its existing queries now retain their elapsed time
and result. Only after a failed waiter, a screen capture and one native root
snapshot record row matches, relevant container/control frames and enabled
states. The original waiter result is asserted after collecting that evidence;
there is no recovery tap, retry, alternate target or later passing substitute.
Compact text is printed to the job log as `MAP_CATEGORY_ROW_FAILURE`, so the
basic evidence does not depend on an artifact download.

The live test adds `--map-refresh-diagnostics`, which enables a Debug-only,
noninteractive accessibility probe and request records in `DashboardStore`.
The record contains request identity, park, generation, elapsed milliseconds,
cancellation/synthetic-transport flags and a typed error category. HTTP failures
retain only the status code; transport failures retain only the error domain
and code. Raw messages, response bodies, headers and URLs are omitted. The test
prints this value as `MAP_REFRESH_REQUEST_DIAGNOSTIC` after the request and on a
failed readiness wait. The request URL, transport, 20-second timeout, request
count and error handling are unchanged. All instrumentation is excluded from
Release compilation.

Both 30-second readiness waits, the manual refresh tap, both Live assertions,
the full-screen check and the original screenshot remain. The automatic-polling
test and every other UI test method are unchanged. All 94 UI method names,
existing assertions, gestures, screenshot calls and 180/240-second case limits
are retained. Artwork, provenance, the 119 prior illustrations and the stage's
326 added illustrations are unchanged.

## Next native diagnostic handoff

Stop for the requested GPT-6 Luna extra-high testing turn before dispatch.
The existing workflow's `map-recovery` scope now repeats these four methods
three times, for 12 UI executions on the selected simulator:

1. `testMapSearchAndCategoryWorkWithBundledLocations`
2. `testMapCategoryChangesAndInterruptedSearchRemainUsable`
3. `testLiveMapRefreshReportsRealProviderStatus`
4. `testMapNetworkAutoRefreshContinuesInFullScreenAndAfterForegroundReturn`

Start with iPhone 16 Pro Max using the existing macOS 15 runner and workflow.
The real live test must still report Live, and the separate HTTP test retains
the production automatic-polling loop. A new failure must be investigated from
its diagnostic records; it must not be waived or converted to a pass. Focused
passes do not establish the cause of run 281's failures or replace a fresh full
three-device run on the final source.

The default full scope and workflow configuration are unchanged: 954 tests
across Pro, SE and Pro Max, then required capture review, fresh archive audit,
eligible hosting with complete public-download hash verification and existing
feed checks. This implementation turn does not dispatch tests or publish.

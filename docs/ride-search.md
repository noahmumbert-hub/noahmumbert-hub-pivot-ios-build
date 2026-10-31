# Ride search with current waits

This follow-up is based on `090d0e3f23177256a20765e1c831c5d3e0fad577`
from `feature/ride-illustrations`. The current SideStore source lists native
1.17.1 / 100.63.1; the illustrations branch continues that released design.

Historical source defines the dimensions and favorite row hierarchy:

- `c958c4c:PIVOT/Views/RideListView.swift`: 46-point minimum search height,
  a 46 × 46 sort control, 13-point horizontal search padding and body text.
- `39b66d0:PIVOT/Views/RootView.swift`: semibold body ride names above caption
  land/status text, with three points of vertical spacing.

The existing implementation restores those dimensions while retaining the
new capsule and illustrated cards. Favorite search observes DashboardStore
and searches both names and lands. Saved favorite IDs remain available when
an entry disappears from the current feed. Results and their ride details
resolve waits by exact selected park and reviewed ride ID from the current
snapshot, without using historical waits as a fallback. Native toggles and
wrapping text retain selection state, accessible wait/status labels and
44-point minimum hit areas.

The follow-up separates expired snapshots, expired per-ride waits and explicit
stale ride states (`Wait stale`) from missing data, failed refreshes, invalid
values and contradictory provider states (`Wait unavailable`). Confirmed
closures remain `Temporarily closed`; scheduled non-operation remains
`Not operating now`. A freshly confirmed closure does not expire simply
because its source-version timestamp is old. Missing waits never become zero;
a provider-posted zero remains a walk-on. Stale rows use a neutral status dot
and withhold the continuing closure clock in visible and accessible summaries.

The focused native scope includes live snapshot changes, exact ride/park
identity, failed and stale feeds, contradictory provider status, invalid and
missing waits, 46-point controls, name/land searches, ride details, clear search,
favorite rows, real accessibility text size and expired/unavailable UI states:

```sh
PIVOT_TEST_SCOPE=reference-ui PIVOT_SIMULATOR_NAME='iPhone SE (3rd generation)' bash scripts/test-native.sh
```

The full `build-ipa.yml` workflow runs all unit/UI tests on iPhone 16 Pro,
iPhone 16 Pro Max and iPhone SE, and validates a Release device archive on the
Pro job. A focused pass does not replace that gate. Results must identify the
tested commit; earlier runs on the shared illustrations branch do not validate
this follow-up. Building a candidate does not publish it or update SideStore.

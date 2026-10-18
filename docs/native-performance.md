# Native loading and responsiveness

Candidate follows released 1.15.5 source 5228ed8f7c4a24e95828c98656b4c9e453d1868f, retaining Supercharged exclusion and 1.15.4 opening-hours protection.

Identified work and changes:
- Live JSON decoding created ISO8601 formatters for every date field. Create two parsers per decoder and reuse them for that response. Decoding already runs on the API actor, not MainActor; no false claim of moving it off the UI thread.
- Time labels allocated/configured DateFormatter on every view update. A bounded, thread-safe cache keys immutable configured formatters by zone and display format, with locale-change invalidation. Apple documents DateFormatter thread safety for supported iOS versions: https://developer.apple.com/documentation/foundation/dateformatter . Dates and freshness decisions are never cached.
- Selected-park crowd browsing could duplicate the dashboard's in-flight live request. It now uses the dashboard refresh path, which publishes both snapshots. Later refreshes still make network requests.
- A global isRefreshing guard blocked a new park behind an older park request. Refresh ownership is scoped to park, monitoring generation and unique request identity. Old results remain rejected and old cleanup cannot clear a newer loading indicator.

Reproducible comparison: testPerformanceComparisonUsesIdenticalSnapshotAndLabelOutputs decodes the same 60-ride payload with the frozen 1.15.5 decoder and the candidate, checks re-encoded equality, and records seven warm elapsed samples per implementation. It also compares 240 identical time-label outputs against frozen baseline formatting. PIVOT_PERF JSON is written to native-tests.log. Timing is a Debug iOS-simulator CPU microbenchmark, not a physical-device startup or network speedup. Review measurements before publication.

Controlled URLProtocol tests hold the old request open while switching parks, assert the new request starts before releasing the old one, and check stale-result/loading isolation. Another test asserts overlapping dashboard/crowd/manual refreshes use one request and a later refresh still uses the network. Timezone, DST, invalid date and locale invalidation tests preserve formatting behavior. Existing last-good-state, failure, polling cadence, alerts, retirement and opening-hours tests remain required.

Inspection: startup still loads saved local preferences/history and starts the selected park monitor; park picker schedules already use batches of six. No speculative rendering or planner rewrite is included. The 5-second foreground cadence, source timestamps, timeouts, HTTP cache policy, stale/error labels, and prediction rules are unchanged. Production API latency and physical launch/scroll performance are not measured by these tests. No backend or website changes/deployment are included.

# Fast & Furious – Supercharged retirement

TouringPlans' Universal Studios Florida attraction page, retrieved October 18, 2026, identifies August 16, 2026 as the final operating day and labels its remaining information historical:
https://touringplans.com/universal-studios-florida/attractions/fast-and-furious-supercharged

PEOPLE independently reported the permanent closure on August 16:
https://people.com/fast-and-furious-supercharged-closes-forever-today-at-universal-studios-florida-12029578
(The PEOPLE search result was accessible; its full page was not.)

The current native app excludes park 65 / ride 6038 before snapshots reach listings, Radar, active counts, plans, local alert processing or app-driven Live Activities. Matching also recognizes its ThemeParks.wiki UUID and narrowly normalized Supercharged names, including a single-rider alias, without excluding Hollywood Drift or another park. Provider status and timestamp cannot override retirement. Aggregate counts are recomputed from remaining rides. Raw payloads, stored favorites, learned history and explicitly saved historical offline packs are not deleted. Old packs remain labeled saved, not current live listings.

The backend candidate adds the same dated retirement to the existing lifecycle registry. The historical catalog entry remains for identity and pre-retirement history. Existing retirement handling excludes active responses and forecasts, censors unfinished forecasts without deleting original windows, and clears ephemeral closure state. No database migration or destructive historical deletion is added.

This release continues native 1.15.4 source d3220976738fb71631b7394ec52b52224f9910d3 and preserves its EPCOT opening-hours guard. The backend candidate continues local 2164d77887bf0022467d89409d3647259201746c. No backend or website is deployed; server-generated pushes and old app versions remain outside the native correction. No physical iPhone install is claimed.

Regression coverage exercises every status, stale response timestamps, identity aliases, park scope, the replacement-name negative case, active metrics, raw snapshot preservation, API integration, and absence of synthetic reopening alerts. The real backend ingestion/SQLite test verifies repeat upstream states cannot revive the ride, neighboring rides remain, and historical observations/original forecast windows survive.

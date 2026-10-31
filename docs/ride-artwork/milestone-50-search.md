# Fifty reviewed images and restored ride search

Eleven further independent ride images were generated with built-in ImageGen,
using individually inspected real photographs and the preserved UI reference.
The outputs were inspected before acceptance. Coverage now reaches 50 images in
Noah's requested more realistic style across 31 parks. The bundle contains 51
images overall, including the older Frozen draft blocked for revision, totaling
11,101,710 image bytes. Of 1,124 catalog IDs, 1,074 remain unfinished, including
the five moderated requests. Those requests were not retried or circumvented.
Epic Universe still needs an accepted authentic reference and artwork.

The eleven additions are Black Snake Summit, Hurricane Mountain, Flight Deck,
Rapterra, Iron Menace, Silver Bullet (Darien Lake), Prairie Schooner, Tornado
(Phoenix), Cheetah Hunt, Bahnzai Pipeline and Krakatau Aqua Coaster. Provenance
preserves exact reference URLs, publisher credits, retained rights, checksums,
review notes and generation prompts. Generated imagery remains disclosed as AI
art. Source photos and the private UI reference remain outside the public repo.
Identity, dimensions, budgets, checksums and coverage validation pass. Complete
coverage intentionally remains a failing gate while entries are unfinished.

Noah also requested the older ride search size and connection to live waits.
History establishes the dimensions rather than a guessed replacement:
`c958c4c:PIVOT/Views/RideListView.swift` uses a 46-point search field and 46×46
sort control. `39b66d0:PIVOT/Views/RootView.swift` has compact favorite rows with
a semibold name, caption land/status text and three-point vertical spacing.
The current native favorite picker had lost that wait/status subtitle.

Both search paths now retain the new design while restoring those dimensions
and compact favorite subtitles. The favorite sheet observes DashboardStore so
refreshes update an open search. Name/land filtering and saved selections remain.
Waits resolve by exact park and ride ID against the current healthy snapshot;
failed, expired, missing, conflicting or unavailable observations cannot appear
as a current number. Zero is shown only when supplied; closures and unposted
waits have explicit text. Results and details share that presentation. Dynamic
Type can wrap names/subtitles and native toggles retain accessible labels and
44-point minimum hit areas. New tests cover refresh changes, failures, data
freshness, closure states, historical dimensions, land search and large text.

Native validation of this combined revision is pending. Earlier focused runs
41224557856 and 41224561086 on 5eaf95b passed three artwork unit/five UI and four
map UI tests respectively. The actual map screenshot shows production search
selecting Space Mountain with the native tab bar, full-screen and zoom controls
present. The former Pro Max failure did not reproduce; no production map fix or
change to the failing test was made. Full run 41224611310 on that older revision
remains failed: its Pro job passed 198 unit tests but failed six of 27 UI tests,
five during simulator background assertion acquisition and one Safari Legal
attribution assertion. Pro Max and SE each passed 198 unit and 27 UI tests; the failed Pro job skipped the archive, so that run produced no IPA.
These older results do not validate the new search code or eleven resources.
No PR or publication was made.

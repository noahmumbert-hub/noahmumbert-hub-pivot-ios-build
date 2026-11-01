# PIVOT 1.18.1 — additional Florida illustrations

This candidate adds 17 accepted Florida ride illustrations to the public 1.18.0 source revision `3b495b1e828757144f1352e5ce9353d740eaf7ff`. The artwork owner's exact checkpoint is `9b25febc23e67104b1ff3bc5f0dc3ea85017018d` on `feature/ride-illustrations`. Its [handoff addendum](ride-artwork/florida-addendum-47-2026-11-01.json) pins the accepted records and both JPEG checksums for each addition. The full [release selection](ride-artwork/florida-release-selection-2026-11-01.json) includes 46 accepted Florida rides and excludes the earlier Frozen draft and all blocked or unaccepted work.

| Park | Additional ride IDs | Total accepted / catalog rides |
| --- | --- | ---: |
| EPCOT | `5-153`, `5-160`, `5-16467` | 8 / 11 |
| Magic Kingdom | `6-131`, `6-132`, `6-133`, `6-141`, `6-161`, `6-1190` | 15 / 21 |
| SeaWorld Orlando | `21-41297957342255`, `21-132368262506504`, `21-196344009848927`, `21-201433938641141`, `21-213939893339792`, `21-226635493153383`, `21-253934793508041`, `21-262673904341261` | 10 / 18 |
| Hollywood Studios | — | 2 / 9 |
| Animal Kingdom | — | 2 / 6 |
| Busch Gardens Tampa Bay | — | 1 / 25 |
| Islands of Adventure | — | 1 / 18 |
| Universal Studios Florida | — | 1 / 13 |
| Volcano Bay | — | 1 / 13 |
| Epic Universe | — | 5 / 11 |

Coverage is **46 of 145 Florida catalog rides, with 99 remaining gaps**. The 29 previously published illustration records and their 58 JPEGs are unchanged. All other public resources remain intact. Only the 17 accepted additions and their relevant attribution, coverage and handoff metadata are selected from the owner's larger artwork branch. The owner continues the remaining work independently.

The 34 added JPEGs are copied byte for byte from the checkpoint, without generation, resampling or retouching. The complete selected set contains 92 JPEGs (9,113,362 bytes) plus its manifest. Images retain their AI-generated illustration labels, alt text and reference attribution. The Soarin' entrance reference is representative; the handoff does not verify its current paint or capture date.

The released native ride search, labels for every observed-wait point, lowest-wait predictions, best reopening estimates and readability fixes are preserved. Production Swift and workflow/test-selection logic are unchanged. The app and Live Activity marketing version advance to 1.18.1, with an explicit increasing default build and a CI archive build of `100.<run>.<attempt>`. The settings UI assertion follows the new version. Existing native artwork tests decode every selected thumbnail and detail image and check bounded dimensions and attribution.

Release requires the exact committed source to pass all 217 unit and 56 UI tests on each of iPhone SE (3rd generation), iPhone 16 Pro and iPhone 16 Pro Max. Actual test database and log evidence must agree, with no missing, skipped, interrupted or repeated cases. Visual/accessibility review includes normal and largest text, ride search, reopening estimates, chart labels and clocks, modal disclosure, artwork and real Safari attribution destinations.

The Release iPhoneOS archive must identify the same source/run, app and widget version/build, device architecture and unsigned state, and contain exactly the selected 46 records and 93 illustration resource files. Before publication, verify the existing SideStore feed, increasing semantic version/build, IPA checksum, unchanged previous assets and version history, icon and permissions. Publication updates only the existing `ipa-builds` delivery branch after these gates pass. Main and the artwork branch are not merged or overwritten.

The final run, build, checksum and publication outcome are recorded in the release evidence and artifact metadata. Simulator tests and an unsigned archive do not establish physical SideStore installation, manual VoiceOver behavior or a formal contrast audit.

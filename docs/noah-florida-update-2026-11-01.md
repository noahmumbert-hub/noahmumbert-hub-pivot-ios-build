# PIVOT 1.18.0 — Florida artwork and native wait updates

This update combines Noah’s four native changes: compact ride search connected to live wait/status presentation, a wait label on every observed point, a lowest-wait estimate when fresh evidence supports it, and the best reopening prediction alongside the supported window. Stale, unavailable and insufficient evidence continue to withhold recommendations. Existing application identity, saved preferences and public reference assets are retained.

The Radar selection, reopening descriptions, hourly clocks and largest-size history views reserve their full text height. Regression coverage includes real enlarged modal fonts, full clock glyphs, every largest-size observed label in rows and details, source-health states, nested disclosure behavior and actual Safari attribution destinations.

The artwork owner’s [handoff](ride-artwork/florida-integration-2026-11-01.md) is pinned to handoff commit `c87e4c3d6ca91da76da94f0cfd69e13ca0cfddc8` and immutable asset revision `ba910085ca9a8d2484fbbbc64fa073ac85c1a645`. [The release selection](ride-artwork/florida-release-selection-2026-11-01.json) includes only the 29 Florida records accepted for style revision 2. The earlier Frozen Ever After draft is excluded. This is **29 of 145 Florida catalog rides**, with **116 remaining gaps**, not complete Florida coverage. Other park artwork continues independently.

| Park | Accepted illustrations / catalog rides |
| --- | ---: |
| EPCOT | 5 / 11 |
| Magic Kingdom | 9 / 21 |
| Hollywood Studios | 2 / 9 |
| Animal Kingdom | 2 / 6 |
| SeaWorld Orlando | 2 / 18 |
| Busch Gardens Tampa Bay | 1 / 25 |
| Islands of Adventure | 1 / 18 |
| Universal Studios Florida | 1 / 13 |
| Volcano Bay | 1 / 13 |
| Epic Universe | 5 / 11 |

The three added Epic Universe images are Fyre Drill (`334-14691`), Curse of the Werewolf (`334-14692`) and Hiccup’s Wing Gliders (`334-14695`). Their thumbnail/detail bytes match the accepted owner checkpoint. All images remain labeled AI-generated illustrations with their reference attribution; no new artwork was generated in this integration.

App and Live Activity marketing versions are aligned at 1.18.0. Their default project build is 100.64.0, above the existing public 100.63.1; the CI archive assigns its own increasing `100.<run>.<attempt>` build. The artifact’s build-info metadata and actual app/widget plists must agree. Keep the installed app and signing identity when updating to retain saved data.

Publication requires the exact final Git revision to pass the unrestricted Xcode suite on iPhone SE (3rd generation), iPhone 16 Pro and iPhone 16 Pro Max, followed by actual test-database, screenshot/accessibility and unsigned iPhoneOS archive review. The publisher must verify the artifact checksum, source/run identity, semantic-version/build continuity, existing source history, entitlements and the existing `ipa-builds/source.json` destination. It may update only that delivery branch; no main or artwork merge is needed. A historical artwork run or earlier integration result does not satisfy the final revision’s gates.

The delivered IPA is unsigned for SideStore to sign. Simulator validation and an unsigned archive do not establish physical-device installation or a manual VoiceOver audit. Publication status, exact run/build, checksums and source SHA are recorded in the release artifact metadata and SideStore source.

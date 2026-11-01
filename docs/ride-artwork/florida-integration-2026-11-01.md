# Florida artwork integration handoff — 2026-11-01

Immutable asset revision: `ba910085ca9a8d2484fbbbc64fa073ac85c1a645` on `feature/ride-illustrations`. The [machine-readable handoff](florida-integration-2026-11-01.json) lists every committed Florida ride ID, actual image filenames and SHA-256 checksums. The source manifest and provenance remain in their existing repository locations.

There are 30 bundled Florida images: 29 in the requested realistic style plus the retained older Frozen Ever After draft. This is partial coverage of the 145 Florida catalog entries; 115 have no bundled image, and 116 remain unfinished for the requested style. Existing moderation blocks are unchanged and must not be retried.

| Park | Bundled / catalog | Requested style |
| --- | ---: | ---: |
| EPCOT | 6 / 11 | 5 |
| Magic Kingdom | 9 / 21 | 9 |
| Hollywood Studios | 2 / 9 | 2 |
| Animal Kingdom | 2 / 6 | 2 |
| SeaWorld Orlando | 2 / 18 | 2 |
| Busch Gardens Tampa Bay | 1 / 25 | 1 |
| Islands of Adventure | 1 / 18 | 1 |
| Universal Studios Florida | 1 / 13 | 1 |
| Volcano Bay | 1 / 13 | 1 |
| Epic Universe | 5 / 11 | 5 |

All 30 Florida manifest records and all 60 JPEG variants were independently compared with native-tested revision `a86e4d4624bce4ce37c846ebc216bfe8849e7640` and are unchanged. [Focused native run 41241538401](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41241538401) passed 6 unit and 8 UI tests on iPhone SE and decoded both JPEG variants for all 138 images at that revision.

Twenty-seven of these 30 records and their JPEG bytes also match `090d0e3f23177256a20765e1c831c5d3e0fad577`, whose [full run 41229843189](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41229843189) passed 201 unit and 29 UI tests per device across three devices plus IPA validation. The three later images are Epic Universe's Fyre Drill (`334-14691`), Curse of the Werewolf (`334-14692`) and Hiccup's Wing Gliders (`334-14695`); their bytes match the focused native run, not that older full-run asset set.

Local validation passed for the entire 333-image asset set at the immutable revision, including references, dimensions, provenance, SHA-256 checks and per-file budgets. These historical results do not establish validation of a newly merged release. The eventual release revision still needs its required full device regression and IPA/archive checks, artifact identity and destination verification.

This artwork thread continues remaining parks independently. It has not changed the release branch, published a feed/release, changed signing, or retried blocked generation. The current Florida images can be selected by the exact IDs in the JSON handoff while retaining existing assets and generated-artwork labeling.

# PIVOT 1.18.2 — stable Florida artwork selection

The artwork owner has confirmed `d30931a62de9d4ce618efc4488a59962a794ce4f` and its [120-record handoff](ride-artwork/florida-addendum-120-2026-11-01.json) as the stable selection for this release. The handoff contains 119 accepted style-2 Florida records and the excluded earlier Frozen draft. This candidate adds **73 accepted illustrations** to public 1.18.1 source `9fb701c688b7ca039cd254edf57911d688ca4da7`, preserving every one of its 46 illustration records, their 92 JPEGs and all other public resources.

The [current release selection](ride-artwork/florida-release-selection-2026-11-01.json) pins those 119 records only. The six later assets recorded at `b2d06dced52801e8af3964f7c868e00b9343166a` are outside this release. All blocked or held keys and the unaccepted Frozen draft remain excluded. The owner's development branch remains independent.

| Park | Accepted illustrations / catalog rides |
| --- | ---: |
| EPCOT | 8 / 11 |
| Magic Kingdom Park | 17 / 21 |
| Disney’s Hollywood Studios | 6 / 9 |
| Disney’s Animal Kingdom | 5 / 6 |
| SeaWorld Orlando | 11 / 18 |
| Busch Gardens Tampa Bay | 25 / 25 |
| Islands of Adventure | 17 / 18 |
| Universal Studios Florida | 8 / 13 |
| Volcano Bay | 13 / 13 |
| Epic Universe | 9 / 11 |

Coverage is **119 of 145 Florida catalog rides, with 26 remaining gaps in this selected checkpoint**. The selected set contains 238 JPEGs plus the index (239 illustration resource files), totaling 24,493,483 JPEG bytes. The additions contribute 146 JPEGs and 15,380,121 bytes, copied byte for byte from the confirmed owner commit. No image was generated, resampled or retouched for this integration.

Artwork keeps its AI-generated labels, alt text and original reference attribution. Historical photographs do not establish current paint, hardware or operating condition. Kumba retains its map-only catalog-review state; accepted historical artwork does not mark it currently operating. Queue, station and static-sign scenes remain limited to the documented references. Reference-photo rights stay distinct from any generated-artwork license.

Pixel review records two minor qualifications in the accepted bytes: Zoe's outer left vehicle edge is cropped while the key face features remain visible; Transformers' packaged sign reads NORTH E3 while the owner reference-review text says NORTH E13. The latter remains an unresolved description-versus-generated-text detail. Neither is used as documentary or operational evidence. The selected record and JPEG bytes remain the owner's confirmed versions.

Production Swift, existing unit-test logic, native test selection, workflow and publisher scripts are unchanged. Ride search and current wait/status display, every observed-dot label, lowest-wait estimates, best reopening points/windows, disclosure behavior, DST/source-health guards and readability repairs are preserved. App and widget marketing versions advance to 1.18.2 and default project builds to 100.139.0; the actual archive uses its increasing `100.<run>.<attempt>` build. The two installed-version UI assertions follow the marketing version.

Release requires the exact committed revision to pass the complete 217 unit and 56 UI cases on each of iPhone SE (3rd generation), iPhone 16 Pro and iPhone 16 Pro Max. Actual SQLite results and raw logs must show all 819 starts and passing completions with no missing, skipped, repeated, interrupted or restarted cases. The native artwork test decodes every selected thumbnail and detail image. Prior release tests and historical artwork-only runs do not clear this candidate.

Current-run visual/accessibility review must cover all 24 largest-text observation value/time targets, eight complete headers and eight full hourly clocks per device, actual enlarged modal text, Radar/reopening support copy and states, search/favorites, artwork/rights and the real Safari attribution destination. Native simulators and automated accessibility assertions do not establish a manual VoiceOver, physical-device or formal contrast audit.

The unsigned Release iPhoneOS archive must match the exact source/run and app/widget version/build, retain device arm64 and minimum iOS17 metadata, exclude signatures/test bundles/DEBUG launch fixtures, and contain exactly the selected 119 records and 239 resource files with all prior artwork bytes preserved. Before publishing, verify the existing feed, increasing semantic version/build, archive checksum and exact local delivery commits, all 17 old versions and 55 asset blobs, icon and permissions. Normal publication updates only the existing `ipa-builds` branch, without merging main or the artwork branch. Successful public canonical/immutable feed and IPA readback establishes delivery. The final run, build, checksum and publication result are recorded in the release evidence and artifact metadata.

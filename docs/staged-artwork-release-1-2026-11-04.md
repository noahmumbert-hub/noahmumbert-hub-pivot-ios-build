# Staged PIVOT artwork release: first stage

This branch prepares **1.18.4** with the current native code, Map fixes and smaller Waits park card from full validated source `77191e42fb6dde600e6bc9a3ab948c7ce09ed4c2`. It bundles **445 illustrations: all 119 previously shipped records plus 326 unchanged additions**. The other **637 accepted illustrations are deferred**. No image has been resized, reencoded or regenerated.

The exact bundled and deferred park/ride keys are recorded in [the stage selection](ride-artwork/staged-release-selection-2026-11-04.json). Full accepted provenance remains byte-for-byte intact in `docs/ride-artwork/provenance.json`, covering all 1,082 accepted records. Coverage distinguishes accepted artwork from this stage's bundled selection. The older Frozen draft and all 42 blocked/held/unresolved catalog entries remain excluded.

## Selected artwork

The first stage includes every accepted new artwork for Magic Mountain, Discovery Kingdom, Over Texas, Over Georgia, Great Adventure, Great America, Fiesta Texas and Hurricane Harbor Los Angeles; all six remaining SeaWorld Orlando/Universal Studios Florida additions; and 16 representative or live-only identities across the remaining parks. This retains the existing 32-park UI coverage and both live-only identity assertions without removing any UI tests or changing assertions.

| Park | Previously shipped | Added in this stage | Bundled total |
|---|---:|---:|---:|
| EPCOT | 8 | 0 | 8 |
| Magic Kingdom Park | 17 | 0 | 17 |
| Disney’s Hollywood Studios | 6 | 0 | 6 |
| Disney’s Animal Kingdom | 5 | 0 | 5 |
| SeaWorld Orlando | 11 | 4 | 15 |
| Busch Gardens Tampa Bay | 25 | 0 | 25 |
| Six Flags Magic Mountain | 0 | 35 | 35 |
| Six Flags Discovery Kingdom | 0 | 34 | 34 |
| Six Flags Over Texas | 0 | 40 | 40 |
| Six Flags Over Georgia | 0 | 39 | 39 |
| Six Flags Great Adventure | 0 | 45 | 45 |
| Six Flags Great America | 0 | 45 | 45 |
| Six Flags Fiesta Texas | 0 | 54 | 54 |
| Hurricane Harbor Los Angeles | 0 | 12 | 12 |
| Six Flags New England | 0 | 1 | 1 |
| Hurricane Harbor New Jersey | 0 | 1 | 1 |
| Cedar Point | 0 | 1 | 1 |
| California’s Great America | 0 | 1 | 1 |
| Canada’s Wonderland | 0 | 3 | 3 |
| Carowinds | 0 | 1 | 1 |
| Kings Island | 0 | 1 | 1 |
| Knott’s Berry Farm | 0 | 1 | 1 |
| Kings Dominion | 0 | 1 | 1 |
| Islands of Adventure | 17 | 0 | 17 |
| Universal Studios Florida | 8 | 2 | 10 |
| Volcano Bay | 13 | 0 | 13 |
| Dorney Park & Wildwater Kingdom | 0 | 1 | 1 |
| Six Flags Darien Lake | 0 | 1 | 1 |
| Frontier City | 0 | 1 | 1 |
| Hurricane Harbor Phoenix | 0 | 1 | 1 |
| Epic Universe | 9 | 0 | 9 |
| Schlitterbahn New Braunfels | 0 | 1 | 1 |

## Size and cumulative limitation

The selected 890 JPEG files contain **89,681,726 bytes**, unchanged. Using their actual compressed contributions in the validated full IPA plus all current non-JPEG bytes and ZIP overhead gives a preliminary archive estimate of **98,708,294 bytes**, about 6.15 MB below GitHub's **104,857,600-byte (100 MiB)** ordinary-file limit. This is a measurement-based estimate, not an archived or release-qualified IPA. Filtering metadata and removing deferred ZIP entries may reduce it further; only the fresh archive determines eligibility.

**These are complete replacement apps, not additive artwork packs.** SideStore downloads one complete IPA for a version, and PIVOT loads artwork from `Bundle.main`. Later versions must include previous bundled images again to retain them. All 1,082 unchanged image pairs occupy 218,478,116 compressed bytes, before app code or other resources. Two or three releases cannot cumulatively retain them under 100 MiB without different hosting or new persistent asset storage/download architecture. No future removal or replacement of this stage's artwork is implicitly approved.

## Validation and publication hold

The source validator checks the exact stage keys, the complete accepted provenance set, all 119 previously released keys, every selected JPEG hash/size/dimension, and the explicit 637 deferred accepted records. The unit artwork count changes from 1,082 to the exact stage count 445. Every other unit assertion and all 94 UI test methods remain unchanged. Fresh three-device gates still require 224 unit plus 94 UI tests on each device (954 total), the complete 939 required and 99 OCR captures, original visual/accessibility review, and a fresh unsigned device archive/hash/size audit. Old full-candidate passes do not qualify this stage.

Publication is held until the parent/user resolves the material cumulative tradeoff and all fresh gates pass. Git/raw hosting is eligible only for an exact archive below the file limit and after authenticated upload and independent complete public download/hash verification. Preserve the existing feed identity, all 19 prior versions and existing downloads. The full candidate branch, its validated IPA and empty draft release 433609030 remain intact. No GitHub Release upload retry, new credentials, permission expansion, website deployment or new artwork is authorized here.

Use increasing three-component marketing versions, such as 1.18.4 then 1.18.5, with new increasing app/widget build numbers. `1.18.3.1` is rejected by the existing version parser; literal `18.3.1` jumps the major version from 1 to 18. Physical SideStore installation and spoken VoiceOver remain unverified.

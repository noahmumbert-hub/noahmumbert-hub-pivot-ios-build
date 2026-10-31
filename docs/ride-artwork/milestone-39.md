# Thirty-nine reviewed realistic images

Sixteen further ride IDs have individually researched official photo references,
pixel-reviewed built-in ImageGen outputs and bundled thumbnail/detail variants.
They cover Magic Mountain, Canada's Wonderland, Carowinds, Kings Island,
Discovery Kingdom, Over Texas, Over Georgia, Great Adventure, Great America,
Fiesta Texas, New England and Knott's Berry Farm. Coverage is now 39 requested-
style images across 20 parks, out of 1,124 catalog IDs. There are 40 bundled
images overall because the earlier Frozen draft is preserved and remains blocked
for revision. Image resource bytes total 8,649,388; 1,085 entries are unfinished.

All sixteen new real references were inspected alongside their official attraction
pages. Exact source URLs, publisher credits, retained photo rights, reference
checksums and review notes are preserved in provenance. Source photographs and
the user's UI reference remain outside this public repository. Generated images
remain labeled as AI artwork. The app now separates reference-photo rights from
an optional illustration adaptation license, preserving existing CC attribution
without inventing a CC grant for official publisher-owned photographs.

A new native UI test exercises the green No. 19 Kings Island railroad image,
generated-image disclosure, accurate retained-rights credit, absent invented
adaptation license and current wait. Its exact-ride fixture is DEBUG-only.
All assets pass identity, uniqueness, dimensions, byte-budget and checksum checks.
The explicit complete-coverage gate correctly fails while 1,085 entries remain.

One candidate for Kings Island Dodgem was rejected because the publisher's image
alt text identifies Cedar Point. No generated image was created from that
candidate; another exact-park reference is needed. See reference-rejections.json.
The five existing moderated requests were not retried or worked around, and all
sixteen new independent requests returned images without new moderation blocks.

Native validation remains a separate gate. The prior d5462c7 focused artwork
run passed three unit and four UI tests. Full run 41221950134 on 37c0399 passed
SE (198 unit, 26 UI), but Pro Max passed 198 unit and 25/26 UI, failing keyboard
focus after the map category menu interaction. Actual video and logs were
inspected; no map product defect or root cause is established. The production
map and existing failing test have not been changed. The focused map diagnostic
now additionally includes that production-map search test for reproduction.
New native credit changes and final resources require their own complete
three-device regression and artifact validation. No release or PR was made.

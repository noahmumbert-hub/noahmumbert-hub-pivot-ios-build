# Ride illustrations — work in progress

**Latest direction:** Noah requested slightly more realistic imagery after the
first examples. `direction.json` records this second style revision. The current
bundled illustrations are being revised for the new treatment. Each revised
record has `styleRevision: 2`; older records remain explicitly due for revision.
`direction.json` and `coverage.json` give the current accepted count for the
requested direction. Work continues on GPT-6.1 Sol, max reasoning.

The artwork request covers every ride, not just the assets currently bundled.
`coverage.json` records 1,124 unique park/ride IDs across 32 parks: 1,123 live
entries plus Kumba, which occurs only in the bundled map and needs a catalog
review. All remaining IDs stay explicitly pending until their reference pixels,
generated artwork and app integration have been reviewed. This is not a complete
artwork release.

At checkpoint 1,082, all independent rides with verified photo identities have
accepted requested-style artwork: 1,082 of 1,124 catalog IDs. The remaining 42
are fully accounted for in `blocked-rides.json` (33 generation blocks),
`held-rides.json` (two related holds without generation attempts), and
`reference-gaps.json` (seven unresolved exact photographic identities). Do not
retry or reframe blocked requests. The older Frozen draft remains bundled and
does not count toward the requested-style total. The full bundle contains 1,083
records; missing coverage keeps the existing truthful fallback.

The inventory reconciles the map catalog from source revision
`741d33d5a922f18eb01c4582a5de3a11d26de049` with recorded public live-feed responses
from October 31, 2026. It preserves stable numeric park/ride IDs, source-page
candidates, available real-photo references and response checksums. A source-page
candidate alone does not count as a verified photo. Different parks never share
an image merely because their ride names match.

Each accepted illustration was created with the built-in ImageGen tool using
an inspected real ride photograph and the user's UI reference. The original
reference is preserved in the working environment and is not copied into this
public repository. `provenance.json` records exact prompts, original generation
checksums, reference URLs/credits/licenses and pixel-review notes. Images are
marked as AI art in ride cards and AI-generated illustrations in ride details;
original photographers are credited as references rather than as the creators
of the generated images.

Reference-photo rights remain distinct from any generated-artwork license.
Publisher-owned references link to the publisher and its retained-rights terms;
they do not receive an invented Creative Commons grant. These source photos
remain outside the app bundle and public repository. Where a verified reference
specifies CC adaptation terms, the artwork continues to carry that attribution.

The app bundles 256×320 thumbnails and 768×960 detail copies. Larger generated
originals remain preserved outside the app bundle. ImageMagick performs only
mechanical downsampling/JPEG encoding during packaging, not artwork generation
or creative editing. Images decode off the main thread and share a 20 MiB,
80-entry evictable memory cache. Missing coverage retains the existing exact-ride
photo or neutral fallback. Artwork never changes operational data or park heroes.

Run `python3 scripts/validate-ride-illustrations.py` to validate every shipped
asset and report the actual coverage. Add `--require-complete` to reject any
unfinished catalog entries. Native tests additionally decode bundle resources,
check park isolation and cache behavior, and exercise artwork credits alongside
the current wait and planning controls. The complete simulator regression still
applies to each delivery candidate.

Noah separately authorized the Florida pictures for publication with the other
updates. The parent release owner handles that integration and its exact-revision
native, archive and publication gates. Its frozen artwork selection is commit
`d30931a62de9d4ce618efc4488a59962a794ce4f`, documented in
`florida-addendum-120-2026-11-01.json` (120 bundled records, 119 in the requested
style). Later artwork checkpoints preserve that selection unchanged and remain
independent of the release branch. This artwork executor does not publish or
modify the feed; the current published version remains separate from this branch.

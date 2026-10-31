# Twenty-three reviewed images

Tower of Terror, Slinky Dog Dash and Minion Blast have been generated with the
built-in image tool, inspected against real photo references and integrated with
full provenance. This brings requested-style coverage to 23 IDs across eight
parks. Twenty-four assets are bundled overall, including the old Frozen draft
whose requested-style revision remains blocked. Image resources total 4,999,118
bytes. The catalog has 1,124 IDs; 1,101 remain unfinished for the requested style.

All 28 original photo-reference entries now have either a reviewed requested-style
asset or an explicit generation blocker. New first attempts for Remy, Alien
Swirling Saucers and Runaway Railway returned HTTP 400 `moderation_blocked` at
output stage, category `other`, without an image. They were not retried or worked
around. Together with Toy Story Mania and Frozen, five rides remain blocked;
exact request IDs and status are in `blocked-rides.json`. The tool provided no
more specific reason, and none is inferred here.

Asset checks pass. The further changes from 37c0399 are artwork resources,
provenance and documentation; native behavior code and tests are unchanged.
The full 37c0399 regression and a focused check for this resource revision must
be tracked separately. See `validation-reconciliation.md` for the baseline SE
failure and subsequent passing focused rerun. No publication or PR occurred.

The larger reference-candidate catalog still requires individual identity,
source/pixel review and generated-output validation. This milestone is not
completion of artwork for every ride.

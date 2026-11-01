# Compact Waits layout

Noah requested a smaller gap between the park card and Current rides and a smaller Recent observed waits control. The source base is the published 1.18.2 revision `3d24f6e414a7a6877782ae06be6faa31e47233b1`.

The Waits header now reserves warning spacing only when the retained-snapshot notice actually appears. Its native section gap is 8 points. Controls and ride cells use less vertical padding; search, sort and filters remain joined to the ride results. The history disclosure removes its extra vertical card padding and uses a 6-point gap above the existing minimum 44-point toggle. Caption fonts and Dynamic Type wrapping remain intact. Expanded charts, forecast navigation, park hours, early entry, live/stale decisions, artwork and detail credits retain their behavior.

Four new UI regressions cover the ordinary EPCOT layout, the twelve-sample Islands of Adventure control, accessibility large text and the largest accessibility text. They measure the actual park-to-controls gap, history touch height, gap above history and row bottom padding; check full schedule and caption text; and open and close the real history chart. They join the existing `layout-review` diagnostic scope. Existing full regression methods, other diagnostic scopes and 180/240-second per-case limits remain unchanged.

Native validation and publication receipts are maintained outside the source checkout. Focused diagnostics do not publish or produce an IPA. Any map-refresh fix is integrated separately only after an immutable reviewed handoff, followed by fresh validation of the final combined release source.

# SE validation reconciliation

Full run 41218291541 tested `be28d80148bbf5a0b506845cffdf1cab416ae179`
and remains recorded as failed overall. Pro and Pro Max each passed 198 unit
and 26 UI tests; the device build/archive passed. SE passed 198 unit tests and
25 of 26 UI tests. The sole failure was the Safari OpenStreetMap attribution
assertion in `testNativeBrowseFocusesRideAndRootWaitDetailsStayCurrent`, line
292. Safari became foreground after MapKit Legal was tapped, but the log then
reported remote accessibility `kAXErrorServerNotFound` while looking for the
attribution link. The SE artwork test passed.

Focused SE map run 41220462215 on
`e2e29b57704f00362c28de40f584628700863aef` passed all three map UI tests,
including the same Legal journey. The actual Safari screenshot shows Apple's
attribution page and its OpenStreetMap copyright link. Map code and the failed
test have no diff between the baseline and this rerun; no workaround or map
product fix was introduced.

The failure was not reproduced by the focused rerun. A transient Safari/test
environment cause is plausible, but not proven. The original failure alone
does not establish a PIVOT defect, and the focused pass does not retroactively
turn the failed full run green.

Artwork run 41220238857 on e2e29b5 also passed three artwork unit tests and four
UI tests, with actual realistic-image, disclosure and current-wait screenshots
inspected. These results apply to that source revision.

Full run 41221950134 tests exactly
`37c039990060d9550aad3d3b2e59d02ddcc44a23`, including the portrait-fit change
and twenty reviewed realistic images. SE passed 198 unit and 26 UI tests,
including the original Legal attribution journey. Pro Max passed 198 unit and
25 of 26 UI tests; its sole failure was keyboard focus in the production map
search test after returning from the places sheet and selecting Rides. The
recording shows the category menu still present, and XCTest's subsequent search
tap computed hit point {-1, -1} before typing failed. The cause of the failed
menu interaction is unresolved; this does not establish an artwork regression
or a map product defect. Production map code and the failing test are unchanged.
The Pro build/archive job was still finishing at the last check. This full run
must not be described as a pass.

Focused artwork run 41222941027 on exact source
`d5462c7c5d261fda48ecbe6b5d4f120c723f09e6` passed three unit and four UI tests.
Actual screenshots were inspected: the portrait-fit view preserves the original
Starblaster tip and base, and generated-image disclosure, reference attribution,
current waits and planning remain exercised. These results precede the new
optional adaptation-license handling and sixteen further resources. The final
native change needs its own full three-device and archive gate; do not carry a
prior SHA's pass forward as validation of a newer artifact.
Any release requires current authorization and validation of its actual final
artifact/revision; this artwork request has not authorized publication.

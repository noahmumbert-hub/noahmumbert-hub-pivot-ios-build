# PIVOT 1.14.3 — compact HHN layout

The large Halloween Horror Nights hero is replaced by a compact event card: smaller headline and moon icon, reduced padding, and date/hours plus feed status and ticket notice. Redundant venue eyebrow, divider and preview instruction are removed. The favorites panel is now a slim summary with its existing progress bar, keeping houses closer to the top.

Text still scales with Dynamic Type and date/status rows fall back to vertical layouts when space is tight. Existing search, filters, house controls, favorites, completed houses, event-date storage keys, app/widget identity and prior fixes remain.

## Validation

- Six publisher tests passed locally; Bash syntax and git whitespace checks passed.
- The existing normal-text UI test now checks that the title-to-feed-status span stays below 150 points, protecting room for the house list. The full existing native suite also covers preview expansion, checklist persistence, stale feeds and accessibility text.
- Final [Xcode run 38088227371](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/38088227371), source `bce1ad4907c1a2a8135f797ef54cbab3412a9999`: **149 unit tests and 10 simulator UI tests passed**, zero failures, with Xcode 26.3 / iPhone 16 Pro / iOS 18.5. The Release device archive and IPA package validation passed.
- Final screenshots reviewed for normal text, favorite progress and accessibility text. The normal event card is roughly half its previous height; text still wraps at accessibility sizes. Screenshots use DEBUG simulator sample data, not actual park observations.
- ZIP integrity, checksum, unsigned device platform, matching app/widget versions, iOS 17 minimum and unchanged identities verified; DEBUG launch arguments and fictional house names are absent from the Release binary.
- All 33 native source files match the private repository mirror.
- Physical iPhone/SideStore signing and installation: unrun.
- No web/backend changes; existing Swift 5 actor-isolation warnings are inherited. No configured SwiftLint check.

## Changed files

- `PIVOT/Views/NativeParkExtras.swift`: compact event card and progress strip.
- `PIVOTUITests/PIVOTUITests.swift`: header size assertion and current version expectation.
- `PIVOT.xcodeproj/project.pbxproj`: marketing version 1.14.3 / project build 25; CI supplies an increasing build number.
- README and this report: tested update provenance.

## Delivery

**1.14.3 / build 100.9.1** is published to the [existing SideStore source](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json). Source, IPA and icon were read back over HTTPS (HTTP 200); downloaded IPA size, SHA-256 and app/widget metadata match. Previous updates remain in feed history. No main merge, GitHub release, backend deployment, permissions change or paid service.

IPA: `PIVOT-1.14.3-100.9.1.ipa`, 2,839,356 bytes.

SHA-256: `9f060d998e29bd08298b9d3fdd701c44bfdb7ac4f3449a6fb536166d0097853e`.

Source publication: `64d14f2f0ddcb7ec5581dc44a79274f51c8f3125`. Immutable asset: `b6c2e970e8120ab2834294d431ed1e276f1acaec`.

[Direct IPA](https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/b6c2e970e8120ab2834294d431ed1e276f1acaec/PIVOT-1.14.3-100.9.1.ipa). Refresh the existing source in SideStore, then update PIVOT while keeping the installed app and the same signing identity to retain data.

Halloween Horror Nights uses a smaller event card and a slim favorites progress strip so houses appear sooner. The moon icon and purple/amber theme remain, with readable event date, hours, ticket notice and Live/Preview/Saved labels. Existing favorites, completion, sorting and previous fixes are preserved. Update the existing PIVOT app using the same SideStore signing identity. Physical SideStore installation remains untested.

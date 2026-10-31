# PIVOT SideStore updates

Add this existing source in SideStore → Sources → +:

https://raw.githubusercontent.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/ipa-builds/source.json

Current update: **1.17.0 / build 100.55.1**, iOS 17.0+.

Refreshed iOS navigation, lists and controls, with a cleaner Plan page.

The park map fills the screen and supports native pinch, pan and zoom controls, with rides, food and show filters. Ride cards show current posted waits, including walk-ons, and clear closed or unavailable states when current data is missing.

Improved large-text layouts, visible Apple map attribution, and preservation of map selection and zoom when entering or leaving full screen.

IPA SHA-256: `ac5902c1e4e4685f938eda5cd8e1406cd39748fd6cc7428800c828810faeb334`.
[Verified native regression and archive](https://github.com/noahmumbert-hub/noahmumbert-hub-pivot-ios-build/actions/runs/41168198135).
194 unit tests and 23 UI tests passed on each of iPhone SE (3rd generation), iPhone 16 Pro and iPhone 16 Pro Max on the same source commit.

The unsigned iPhoneOS IPA preserves `com.noahmumbert.PIVOT` and its Live Activity extension.
SideStore signs the update using your existing identity. Physical installation and device performance remain untested; keep the existing app installed to retain its saved data.
This is a native app update; it does not deploy the website or backend.

This branch retains earlier downloads. IPA and icon URLs are pinned to immutable Git commits, while the source URL stays constant.

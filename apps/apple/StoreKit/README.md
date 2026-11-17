# Local subscription testing

The two local configurations define the same monthly and annual products in
one subscription group at the same level.

| Configuration | Monthly | Annual | Annual monthly equivalent |
| --- | ---: | ---: | ---: |
| `BackupDuck.storekit` (US) | USD 1.99 | USD 11.99 | USD 1.00 |
| `BackupDuck-China.storekit` | CNY 2.00 | CNY 12.00 | CNY 1.00 |

Use `app.backupduck.pro.monthly` and `app.backupduck.pro.annual` with one month
and one year of access. Register both in the same subscription group and
level in App Store Connect and choose each storefront's supported price points.
The app displays the localized StoreKit billing totals and calculates the
annual comparison from those prices.

Neither fixture includes an introductory offer. The seven-day welcome period
is an application grant persisted separately in device-only Keychain storage;
it does not create an Apple transaction or automatically charge afterward.

Use the separately identified `app.backupduck.storekittest` development host
with `BACKUPDUCK_SUBSCRIPTION_TESTING`. Its Run scheme must select the local
StoreKit configuration. Copying the file into a bundle does not activate the
local store, and creating `SKTestSession` alone does not replace that scheme
setting for an application purchase. A standalone launch without the active
local environment cannot establish a successful simulated purchase.

The adapter's local mode checks a verified Xcode app transaction before loading
products and before purchasing; only verified Xcode purchase transactions grant
paid test access. Production mode separately requires matching App Store or submission sandbox
distribution and purchase evidence. TestFlight and direct-download hosts retain ordinary backup.

`SubscriptionStoreKitTests` uses `SKTestSession` from XCTest to control the local
store. Run it serially: all sessions share one test environment. The suite covers
purchase, cancellation, failure, pending approval, renewal-off access, expiration,
refund, restoration, unverified transactions and the separately persisted welcome
grant. Test history reset affects the simulated store only. Forced test-session
mutations may need an explicit test restore before StoreKit returns updated signed
facts. That validates reconciliation after restore, not automatic transaction-update
delivery. The application never performs account sync from its ordinary refresh.
Cancellation injection can be unavailable on a test runtime; a skipped injection
requires a separate check of cancellation in Apple's actual confirmation sheet.

See Apple's [SKTestSession documentation](https://developer.apple.com/documentation/storekittest/sktestsession)
and [current-entitlements documentation](https://developer.apple.com/documentation/storekit/transaction/currententitlements).

StoreKit testing is local simulation. It does not establish App Store Connect
product availability, billing agreements, App Review approval, sandbox-account
behavior or production payment operation. Do not change a production bundle
identity or install over its data to run these tests.

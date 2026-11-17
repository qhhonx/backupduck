import XCTest
@testable import BackupDuckCatalog

final class SubscriptionAccessPolicyTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testNonStoreDistributionIgnoresExistingExpiredState() {
    let access = DuckSubscriptionAccessPolicy.resolve(enabled: false,
      welcomeStart: now.addingTimeInterval(-10 * 24 * 60 * 60),
      entitlement: .init(expiration: now.addingTimeInterval(-1), revoked: true), now: now)
    XCTAssertEqual(access, .unrestricted)
  }

  func testWelcomeEndsAtExactSevenDayBoundaryWithoutApplePurchase() {
    let start = now.addingTimeInterval(-DuckSubscriptionAccessPolicy.welcomeDuration)
    XCTAssertEqual(DuckSubscriptionAccessPolicy.resolve(enabled: true, welcomeStart: start,
      entitlement: nil, now: now.addingTimeInterval(-1)), .welcome(until: now))
    XCTAssertEqual(DuckSubscriptionAccessPolicy.resolve(enabled: true, welcomeStart: start,
      entitlement: nil, now: now), .expired(since: now))
  }

  func testRenewalIntentCannotExtendExpiredOrRevokedEntitlement() {
    for entitlement in [
      DuckSubscriptionEntitlement(expiration: now.addingTimeInterval(-1), revoked: false, willAutoRenew: true),
      DuckSubscriptionEntitlement(expiration: now.addingTimeInterval(100), revoked: true, willAutoRenew: true)
    ] {
      let access = DuckSubscriptionAccessPolicy.resolve(enabled: true, welcomeStart: now,
        entitlement: entitlement, now: now)
      XCTAssertFalse(access.permitsBackup)
    }
  }

  func testLateRefundOfOlderPeriodCannotReplaceNewerRenewal() {
    let renewal = DuckSubscriptionEntitlement(expiration: now.addingTimeInterval(100), revoked: false,
      signedDate: now, purchaseDate: now, transactionID: 2)
    let oldRefund = DuckSubscriptionEntitlement(expiration: now, revoked: true,
      signedDate: now.addingTimeInterval(10), purchaseDate: now.addingTimeInterval(-100), transactionID: 1)
    XCTAssertFalse(oldRefund.supersedes(renewal))
    var currentRefund = renewal
    currentRefund.signedDate = now.addingTimeInterval(10)
    XCTAssertTrue(currentRefund.supersedes(renewal))
    XCTAssertFalse(renewal.supersedes(currentRefund))
  }

  func testMissingOrFutureWelcomeCannotGrantUnlimitedAccess() {
    for start in [nil, now.addingTimeInterval(1)] {
      XCTAssertFalse(DuckSubscriptionAccessPolicy.resolve(enabled: true, welcomeStart: start,
        entitlement: nil, now: now).permitsBackup)
    }
  }

  func testTurningRenewalOffRetainsCurrentPaidPeriod() {
    let end = now.addingTimeInterval(100)
    let access = DuckSubscriptionAccessPolicy.resolve(enabled: true, welcomeStart: nil,
      entitlement: .init(expiration: end, revoked: false, willAutoRenew: false), now: now)
    XCTAssertEqual(access, .paid(until: end))
  }
}

import StoreKit
import StoreKitTest
import XCTest
@testable import BackupDuckStoreKitTest

/// This suite mutates Apple's single local test environment and must run serially.
@MainActor final class SubscriptionStoreKitTests: XCTestCase {
  private var session: SKTestSession!
  private var store: DuckSubscriptionStore!

  override func setUp() async throws {
    session = try SKTestSession(configurationFileNamed: "BackupDuck")
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    store = DuckSubscriptionStore(mode: .localTesting)
    await store.clearLocalWelcome()
    await store.start()
    XCTAssertTrue(store.commerceEnabled, "Tests require the separately identified local StoreKit host.")
    XCTAssertNotNil(store.offerPresentation.monthlyPrice)
  }

  override func tearDown() async throws {
    store = nil
    session.clearTransactions()
    session.resetToDefaultState()
    session = nil
  }

  func testPurchaseUsesVerifiedAppleTransactionAndRestoresAfterRelaunch() async throws {
    await store.purchase()
    XCTAssertEqual(store.purchaseOutcome, .purchased)
    assertPaid(store.access)
    XCTAssertNil(store.statusPresentation.monthlyPrice, "A new offer price is not an existing subscriber's renewal price.")
    XCTAssertNotNil(store.statusPresentation.date, "A verified renewing subscribed period has a known renewal date.")
    XCTAssertEqual(session.allTransactions().count, 1)
    let replacement = DuckSubscriptionStore(mode: .localTesting)
    await replacement.start()
    assertPaid(replacement.access)
    await replacement.restore()
    assertPaid(replacement.access)
  }

  func testAnnualPlanUsesAnnualTransactionAndRestoresPaidAccess() async throws {
    XCTAssertEqual(store.offerPresentation.annualPrice, "$11.99")
    XCTAssertEqual(store.offerPresentation.annualMonthlyEquivalent, "$1.00")
    XCTAssertTrue(store.offerPresentation.annualSavings?.contains("49%") == true)
    await store.purchase(.annual)
    XCTAssertEqual(store.purchaseOutcome, .purchased)
    assertPaid(store.access)
    XCTAssertEqual(session.allTransactions().map(\.productIdentifier), [DuckSubscriptionPlan.annual.productID])

    let replacement = DuckSubscriptionStore(mode: .localTesting)
    await replacement.start()
    await replacement.restore()
    assertPaid(replacement.access)
    try session.expireSubscription(productIdentifier: DuckSubscriptionPlan.annual.productID)
    await replacement.restore()
    try await waitFor { !replacement.access.permitsBackup }
  }

  func testCancelledPurchaseDoesNotGrantPaidAccess() async throws {
    await store.setLocalWelcomeStart(Date().addingTimeInterval(-8 * 24 * 60 * 60))
    try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
    // Check the public API first: some local runtimes turn this injection into an
    // unknown service error. That cannot establish cancellation behavior in the app.
    let products = try await Product.products(for: [DuckSubscriptionStore.monthlyProductID])
    let product = try XCTUnwrap(products.first)
    do {
      if case .userCancelled = try await product.purchase() {} else { XCTFail("Expected cancellation injection") }
    } catch StoreKitError.userCancelled {
    } catch let error as SKError where error.code == .paymentCancelled {
    } catch {
      throw XCTSkip("The local StoreKit runtime cannot deliver its public cancellation injection: \(error). Verify cancellation in Apple's confirmation sheet separately.")
    }
    await store.purchase()
    XCTAssertEqual(store.purchaseOutcome, .cancelled)
    XCTAssertFalse(store.access.permitsBackup)
  }

  func testFailedPurchaseDoesNotGrantPaidAccess() async throws {
    await store.setLocalWelcomeStart(Date().addingTimeInterval(-8 * 24 * 60 * 60))
    try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
    await store.purchase()
    XCTAssertEqual(store.purchaseOutcome, .failed)
    XCTAssertFalse(store.access.permitsBackup)
  }

  func testExternalVerifiedPurchaseArrivesThroughTransactionUpdates() async throws {
    await store.setLocalWelcomeStart(Date().addingTimeInterval(-8 * 24 * 60 * 60))
    XCTAssertFalse(store.access.permitsBackup)
    try await session.buyProduct(identifier: DuckSubscriptionStore.monthlyProductID)
    try await waitFor { self.store.access.permitsBackup }
    assertPaid(store.access)
  }

  func testAskToBuyIsPendingUntilVerifiedApprovalAndExplicitRestore() async throws {
    await store.setLocalWelcomeStart(Date().addingTimeInterval(-8 * 24 * 60 * 60))
    session.askToBuyEnabled = true
    await store.purchase()
    XCTAssertEqual(store.purchaseOutcome, .pending)
    XCTAssertTrue(store.offerPresentation.pending)
    XCTAssertFalse(store.access.permitsBackup)
    let pending = try XCTUnwrap(session.allTransactions().first { $0.pendingAskToBuyConfirmation })
    try session.approveAskToBuyTransaction(identifier: pending.identifier)
    await store.restore()
    try await waitFor { self.store.access.permitsBackup }
    assertPaid(store.access)
  }

  func testForcedExpiryRemovesPaidAccessWithoutCreatingNewWelcome() async throws {
    await store.purchase()
    assertPaid(store.access)
    try session.expireSubscription(productIdentifier: DuckSubscriptionStore.monthlyProductID)
    // Xcode's local store may retain cached StoreKit 2 data after test-session mutations.
    // Explicit restore advances that environment; it does not prove automatic updates.
    await store.restore()
    try await waitFor { !self.store.access.permitsBackup }
  }

  func testRefundRemovesPaidAccessWithoutCreatingNewWelcome() async throws {
    await store.purchase()
    assertPaid(store.access)
    let transaction = try XCTUnwrap(session.allTransactions().last)
    try session.refundTransaction(identifier: transaction.identifier)
    await store.restore()
    try await waitFor { !self.store.access.permitsBackup }
  }

  func testRenewalOffKeepsPaidAccessUntilExpiration() async throws {
    await store.purchase()
    let transaction = try XCTUnwrap(session.allTransactions().last)
    try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
    await store.restore()
    XCTAssertEqual(store.statusPresentation.state, .renewalOff)
    XCTAssertNotNil(store.statusPresentation.date)
    XCTAssertNil(store.statusPresentation.monthlyPrice)
    assertPaid(store.access)
  }

  func testEmptyAndFailedRestoreAreDistinctFromSubscriptionSuccess() async throws {
    await store.restore()
    if case .nothingFound = store.offerPresentation.restoration {} else { XCTFail("Expected empty restore") }
    try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync)
    await store.restore()
    if case .failed = store.offerPresentation.restoration {} else { XCTFail("Expected failed restore") }
    XCTAssertNotEqual(store.purchaseOutcome, .purchased)
  }

  func testUnverifiedTransactionsNeverGrantPaidAccess() async throws {
    await store.setLocalWelcomeStart(Date().addingTimeInterval(-8 * 24 * 60 * 60))
    try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
    await store.purchase()
    XCTAssertEqual(store.purchaseOutcome, .failed)
    XCTAssertFalse(store.access.permitsBackup)
  }

  func testProductionModeDoesNotEnableCommerceFromXcodePurchase() async throws {
    await store.purchase()
    assertPaid(store.access)
    let production = DuckSubscriptionStore(mode: .production)
    await production.start()
    XCTAssertFalse(production.commerceEnabled)
    XCTAssertEqual(production.access, .unrestricted)
    XCTAssertNil(production.offerPresentation.monthlyPrice)
  }

  func testWelcomeGrantPersistsAndUsesSevenAppGrantedDays() async throws {
    let start = Date().addingTimeInterval(-24 * 60 * 60)
    await store.setLocalWelcomeStart(start)
    let replacement = DuckSubscriptionStore(mode: .localTesting)
    await replacement.start()
    guard case .welcome(let end) = replacement.access else { return XCTFail("Expected persisted welcome") }
    XCTAssertEqual(end.timeIntervalSince(start), DuckSubscriptionAccessPolicy.welcomeDuration, accuracy: 0.01)
    XCTAssertTrue(session.allTransactions().isEmpty, "Welcome access is not an Apple introductory purchase.")
  }

  func testWelcomeExpiresByWallClockWithoutStoreMutationOrAccountSync() async throws {
    await store.setLocalWelcomeStart(Date().addingTimeInterval(-DuckSubscriptionAccessPolicy.welcomeDuration + 0.5))
    XCTAssertTrue(store.access.permitsBackup)
    try await waitFor { !self.store.access.permitsBackup }
    await store.refresh()
    XCTAssertFalse(store.access.permitsBackup)
    XCTAssertTrue(session.allTransactions().isEmpty)
  }

  func testPaidPeriodExpiresByWallClockWithRenewalOff() async throws {
    session.timeRate = .oneRenewalEveryTwoSeconds
    await store.purchase()
    let transaction = try XCTUnwrap(session.allTransactions().last)
    try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
    await store.restore()
    assertPaid(store.access)
    try await waitFor { !self.store.access.permitsBackup }
    await store.refresh()
    XCTAssertFalse(store.access.permitsBackup)
  }

  private func assertPaid(_ access: DuckSubscriptionAccess, file: StaticString = #filePath, line: UInt = #line) {
    guard case .paid(let until) = access else { return XCTFail("Expected verified paid access", file: file, line: line) }
    XCTAssertGreaterThan(until, Date(), file: file, line: line)
  }

  private func waitFor(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(10)
    while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
    XCTAssertTrue(condition(), "Timed out waiting for a StoreKit transaction update.")
  }
}

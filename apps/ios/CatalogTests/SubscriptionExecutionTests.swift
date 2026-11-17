import XCTest
@testable import BackupDuckCatalog

@MainActor final class SubscriptionExecutionTests: XCTestCase {
  func testExpiryAndRenewalPreserveUserPauseAndAutomaticBackup() async {
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    model.paused = true
    model.autoBackup = true

    await model.setSubscriptionAccess(allowed: false)
    XCTAssertTrue(model.subscriptionExecutionBlocked)
    XCTAssertTrue(model.executionBlocked)
    XCTAssertTrue(model.paused)
    XCTAssertTrue(model.autoBackup)

    await model.setSubscriptionAccess(allowed: true, validUntil: Date().addingTimeInterval(3600))
    XCTAssertFalse(model.subscriptionExecutionBlocked)
    XCTAssertTrue(model.executionBlocked, "Renewal must not resume an explicitly paused sender")
    XCTAssertTrue(model.paused)
    XCTAssertTrue(model.autoBackup)
    await model.setSubscriptionAccess(allowed: true)
  }

  func testExpiredDeadlineBlocksAnOtherwiseRunningSender() async {
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    model.paused = false
    model.autoBackup = false
    await model.setSubscriptionAccess(allowed: true, validUntil: Date(timeIntervalSince1970: 1))
    XCTAssertTrue(model.executionBlocked)
    XCTAssertFalse(model.paused)
    XCTAssertFalse(model.autoBackup)

    await model.setSubscriptionAccess(allowed: true)
    XCTAssertFalse(model.executionBlocked, "An unrestricted channel must clear an earlier access deadline")
    XCTAssertNil(model.subscriptionAccessValidUntil)
    XCTAssertFalse(model.paused)
    XCTAssertFalse(model.autoBackup)
  }
}

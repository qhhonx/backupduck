import XCTest
@testable import BackupDuck

/// Notifications only when the user is needed (design/flows.md § Every day):
/// each condition is announced once and withdrawn or rearmed when it clears.
@MainActor final class BackupNotifierTests: XCTestCase {
  private func history(_ state: String, pending: Int, checked: Int = 10) -> HistoricalImportStatus {
    HistoricalImportStatus(run: 1, state: state, checked: checked, pending: pending)
  }

  func testUnreachableIsScheduledOnceAndWithdrawnWhenBack() {
    var memory = BackupNotifier.Memory()
    XCTAssertEqual(BackupNotifier.changes(status: .problem(.receiverUnreachable), earlier: nil, memory: &memory),
      [.post(id: "unreachable", after: 86_400)])
    XCTAssertEqual(BackupNotifier.changes(status: .problem(.receiverUnreachable), earlier: nil, memory: &memory), [])
    XCTAssertEqual(BackupNotifier.changes(status: .caughtUp(lastSaved: nil, saving: 0), earlier: nil, memory: &memory),
      [.withdraw(id: "unreachable")])
  }

  func testFullAndConversionAnnounceOnlyNewProblems() {
    var memory = BackupNotifier.Memory()
    XCTAssertEqual(BackupNotifier.changes(status: .problem(.receiverFull), earlier: nil, memory: &memory), [.post(id: "full", after: nil)])
    XCTAssertEqual(BackupNotifier.changes(status: .problem(.receiverFull), earlier: nil, memory: &memory), [])
    XCTAssertEqual(BackupNotifier.changes(status: .problem(.conversionNeeded(2)), earlier: nil, memory: &memory), [.post(id: "convert", after: nil)])
    XCTAssertEqual(BackupNotifier.changes(status: .problem(.conversionNeeded(2)), earlier: nil, memory: &memory), [])
    XCTAssertEqual(BackupNotifier.changes(status: .problem(.conversionNeeded(3)), earlier: nil, memory: &memory), [.post(id: "convert", after: nil)])
  }

  func testEarlierPhotosAnnouncedOnlyWhenTheyFinishWhileWatched() {
    var memory = BackupNotifier.Memory()
    let calm = BackupHubStatus.caughtUp(lastSaved: nil, saving: 0)
    // Already done when first seen: nothing to announce.
    XCTAssertEqual(BackupNotifier.changes(status: calm, earlier: history("scanned", pending: 0), memory: &memory), [])
    memory = BackupNotifier.Memory()
    XCTAssertEqual(BackupNotifier.changes(status: calm, earlier: history("running", pending: 5), memory: &memory), [])
    XCTAssertEqual(BackupNotifier.changes(status: calm, earlier: history("scanned", pending: 0), memory: &memory), [.post(id: "earlier", after: nil)])
    XCTAssertEqual(BackupNotifier.changes(status: calm, earlier: history("scanned", pending: 0), memory: &memory), [])
  }
}

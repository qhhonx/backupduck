import XCTest
@testable import BackupDuck

final class BackupHubStatusTests: XCTestCase {
  private func inputs(_ change: (inout BackupHubStatus.Inputs) -> Void = { _ in }) -> BackupHubStatus.Inputs {
    var summary = SenderSummary(); summary.total = 10; summary.received = 10; summary.published = 10
    var value = BackupHubStatus.Inputs(paired: true, ready: true, paused: false, connection: .ready, receiverUnavailable: false,
      summary: summary, phoneSpaceShort: false, photoAccess: .full, jobs: [])
    change(&value)
    return value
  }

  func testOneStatePerSituationInPriorityOrder() {
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.paired = false }), .notPaired)
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.ready = false }), .opening)
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.connection = .authentication }), .problem(.receiverRejected))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.waiting_reason = "network" }), .problem(.receiverUnreachable))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.waiting_reason = "capacity" }), .problem(.receiverFull))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.phoneSpaceShort = true }), .problem(.phoneFull))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.photoAccess = .denied }), .problem(.photoAccessDenied))
  }

  func testPausingOutranksStaleConnectionReadings() {
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.paused = true; $0.connection = .network }), .paused)
  }

  func testCaughtUpNeverClaimsPhotosStillBeingSaved() {
    XCTAssertEqual(BackupHubStatus.derive(inputs()), .caughtUp(lastSaved: nil, saving: 0))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.published = 7; $0.summary.publication_failed = 1 }),
      .caughtUp(lastSaved: nil, saving: 2))
  }

  func testBackingUpCountsQueuedRunningAndWaiting() {
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.queued = 3; $0.summary.running = 1; $0.summary.waiting = 2 }),
      .backingUp(remaining: 6, bytes: 0))
  }

  func testEmptyWhenNothingWasSaved() {
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary = SenderSummary() }), .empty)
  }
}

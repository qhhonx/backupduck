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
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.published = 7 }),
      .caughtUp(lastSaved: nil, saving: 3))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.published = 0 }),
      .caughtUp(lastSaved: nil, saving: 10))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.publication_failed = 1 }), .problem(.photosNeedYou(1)))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.preparation_waiting = 2 }), .backingUp(remaining: 2, bytes: 0))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.preparation_failed = 2 }), .problem(.photosNeedYou(2)))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.conversion_required = 201 }), .problem(.conversionNeeded(201)))
  }

  func testBackingUpCountsQueuedRunningAndWaiting() {
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.queued = 3; $0.summary.running = 1; $0.summary.waiting = 2 }),
      .backingUp(remaining: 6, bytes: 0))
  }

  func testEmptyWhenNothingWasSaved() {
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary = SenderSummary() }), .empty)
  }
}


@MainActor final class SelectedBackupTests: XCTestCase {
  func testRepeatConsentUsesPublicationAndMatchingRevision() {
    let ids = ["new", "received", "saving", "failed", "saved", "changed", "missing", "unknown"]
    let sources = ids.map { PhotoBackupOrder.Source(id: $0, revision: $0 == "missing" ? nil : "v2", capturedAt: nil) }
    let observations: [String: LibrarySourceObservation] = [
      "received": .init(revision: "v2", preparing: false, tile_state: "unknown"),
      "saving": .init(revision: "v2", preparing: false, tile_state: "saving"),
      "failed": .init(revision: "v2", preparing: false, tile_state: "needs_you"),
      "saved": .init(revision: "v2", preparing: false, tile_state: "saved"),
      "changed": .init(revision: "v1", preparing: false, tile_state: "saved"),
      "missing": .init(revision: nil, preparing: false, tile_state: "saved"),
    ]
    XCTAssertEqual(BackupModel.selectedBackupRepeatSources(sources, observations: observations), ["saved"])
  }
  func testMissingReceiverPreservesSelectionWithoutRegistering() async {
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let library = PhotoLibraryModel()
    library.selection = ["selected"]
    let action = SelectionBackupAction()
    await action.request(library: library, model: model)
    XCTAssertEqual(library.selection, ["selected"])
    XCTAssertNotNil(action.error)
    XCTAssertFalse(action.added)
    XCTAssertFalse(action.busy)
    XCTAssertFalse(action.confirmingRepeat)
  }
  func testRegistrationFeedbackFailureAndRetry() async {
    let action = SelectionBackupAction()
    var selection: Set<String> = ["selected"]
    await action.perform({ false }, failure: { "Pixel is unavailable" })
    XCTAssertEqual(selection, ["selected"])
    XCTAssertEqual(action.error, "Pixel is unavailable")
    XCTAssertFalse(action.added)
    await action.perform({
      XCTAssertTrue(action.busy)
      selection.removeAll()
      return true
    }, failure: { nil })
    XCTAssertTrue(selection.isEmpty)
    XCTAssertTrue(action.added)
    XCTAssertNil(action.error)
    XCTAssertFalse(action.busy)
    action.selectionChanged()
    XCTAssertFalse(action.added)
  }
}

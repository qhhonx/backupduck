import XCTest
@testable import BackupDuck

final class BackupHubStatusTests: XCTestCase {
  private func inputs(_ change: (inout BackupHubStatus.Inputs) -> Void = { _ in }) -> BackupHubStatus.Inputs {
    var summary = SenderSummary(); summary.total = 10; summary.received = 10; summary.published = 10
    var value = BackupHubStatus.Inputs(paired: true, ready: true, paused: false, connection: .ready, receiverUnavailable: false,
      summary: summary, phoneSpaceShort: false, photoAccess: .full, photoLibraryInScope: true, jobs: [])
    change(&value)
    return value
  }

  func testOneStatePerSituationInPriorityOrder() {
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.paired = false }), .notPaired)
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.ready = false }), .opening)
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.connection = .authentication }), .problem(.receiverRejected))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.waiting_reason = "network" }), .caughtUp(lastSaved: nil, saving: 0))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.waiting_reason = "network"; $0.receiverUnavailable = true }), .problem(.receiverUnreachable))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.summary.waiting_reason = "capacity" }), .problem(.receiverFull))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.phoneSpaceShort = true }), .problem(.phoneFull))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.photoAccess = .denied }), .problem(.photoAccessDenied))
  }

  func testLocalNetworkBlockKeepsUnreachablePriorityAndSpecificCause() {
    XCTAssertEqual(BackupHubStatus.derive(inputs {
      $0.connection = .localNetworkDenied; $0.receiverUnavailable = true
      $0.summary.waiting_reason = "network"; $0.photoAccess = .denied
      $0.phoneSpaceShort = true
    }), .problem(.localNetworkBlocked))
    XCTAssertEqual(BackupHubStatus.derive(inputs {
      $0.connection = .localNetworkDenied; $0.summary.waiting_reason = "authentication"
    }), .problem(.receiverRejected))
    XCTAssertEqual(BackupHubStatus.derive(inputs {
      $0.connection = .localNetworkDenied; $0.paused = true
    }), .paused)
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.connection = .network }), .problem(.receiverUnreachable))
    XCTAssertEqual(BackupHubStatus.problem(.localNetworkBlocked).sentence(receiver: "Pixel"),
      NSLocalizedString("hub_problem_local_network", comment: ""))
  }

  @MainActor func testHubReadsCachedPhotoAccessUntilExplicitRefresh() {
    let original = BackupEnvironment.photoAccess
    defer { BackupEnvironment.photoAccess = original }
    var reads = 0, access = PhotoAccess.full
    BackupEnvironment.photoAccess = { reads += 1; return access }
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    XCTAssertEqual(reads, 1)
    access = .denied
    for _ in 0..<100 {
      model.autoBackup = true; model.ready = true
      _ = model.hubStatus; _ = model.photoLibraryInScope; _ = model.showsEarlierPhotosNotStarted
    }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(model.photoAccess, .full)
    model.refreshPhotoAccess()
    XCTAssertEqual(model.photoAccess, .denied)
    XCTAssertEqual(reads, 2)
  }

  @MainActor func testPhotoRequestRefreshesCacheAfterBothResults() async {
    let originalAccess = BackupEnvironment.photoAccess
    let originalRequest = BackupEnvironment.requestPhotoAccess
    defer {
      BackupEnvironment.photoAccess = originalAccess
      BackupEnvironment.requestPhotoAccess = originalRequest
    }
    var access = PhotoAccess.undetermined
    BackupEnvironment.photoAccess = { access }
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    BackupEnvironment.requestPhotoAccess = { access = .denied; return false }
    let denied = await model.authorizePhotos()
    XCTAssertFalse(denied)
    XCTAssertEqual(model.photoAccess, .denied)
    BackupEnvironment.requestPhotoAccess = { access = .limited; return true }
    let allowed = await model.authorizePhotos()
    XCTAssertTrue(allowed)
    XCTAssertEqual(model.photoAccess, .limited)
  }

  @MainActor func testNetworkDenialCheckerRefinesOnlyNetworkFailuresAndCaches() async {
    let pairing = Pairing(version: 2, receiverID: "synthetic", endpoint: "https://127.0.0.1:1", certificate: "fixture", token: "fixture")
    var probes = 0, checks = 0
    var response = ReceiverConnection.network
    var denied = true
    let gate = ReceiverAvailability(monitorNetwork: false,
      diagnose: { _ in probes += 1; return response },
      localNetworkDenied: { target in
        XCTAssertEqual(target.endpoint, pairing.endpoint)
        checks += 1; return denied
      })
    gate.networkChanged(allowed: true)
    let blocked = await gate.diagnose(pairing)
    XCTAssertEqual(blocked, .localNetworkDenied)
    denied = false
    let cached = await gate.diagnose(pairing)
    XCTAssertEqual(cached, .localNetworkDenied)
    XCTAssertEqual(probes, 1); XCTAssertEqual(checks, 1)
    let unreachable = await gate.diagnose(pairing, force: true)
    XCTAssertEqual(unreachable, .network)
    for result in [ReceiverConnection.ready, .authentication, .unavailable] {
      response = result
      let actual = await gate.diagnose(pairing, force: true)
      XCTAssertEqual(actual, result)
    }
    XCTAssertEqual(checks, 2)
    XCTAssertEqual(probes, 5)
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

  func testPhotoAccessOnlyBlocksLibraryWork() {
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.photoAccess = .denied; $0.photoLibraryInScope = false }),
      .caughtUp(lastSaved: nil, saving: 0))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.photoAccess = .denied; $0.photoLibraryInScope = false; $0.summary.queued = 4 }),
      .backingUp(remaining: 4, bytes: 0))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.photoAccess = .denied; $0.photoLibraryInScope = true }),
      .problem(.photoAccessDenied))
    XCTAssertEqual(BackupHubStatus.derive(inputs { $0.photoAccess = .limited }), .caughtUp(lastSaved: nil, saving: 0))
  }
  @MainActor func testPhotoLibraryScopeFollowsActualWork() {
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    XCTAssertFalse(model.photoLibraryInScope)
    model.autoBackup = true
    XCTAssertTrue(model.photoLibraryInScope)
    model.autoBackup = false
    model.historicalImport = HistoricalImportStatus(run: 1, state: "idle", checked: 0, pending: 0)
    XCTAssertFalse(model.photoLibraryInScope)
    model.historicalImport = HistoricalImportStatus(run: 1, state: "paused", checked: 2, pending: 2)
    XCTAssertTrue(model.photoLibraryInScope)
    model.historicalImport = HistoricalImportStatus(run: 1, state: "scanned", checked: 2, pending: 0, published: 2)
    XCTAssertFalse(model.photoLibraryInScope)
    model.pendingImports = 1
    XCTAssertTrue(model.photoLibraryInScope)
    model.pendingImports = 0
    let folder = BackupJob(id: 1, asset: .init(metadata: ["source_type": "folder"], kind: "photo", source_id: "folder:1", revision: "1", resources: []), state: "queued", confirmedBytes: 0, errorCode: nil)
    model.jobs = [folder]
    XCTAssertFalse(model.photoLibraryInScope)
    let library = BackupJob(id: 2, asset: .init(kind: "photo", source_id: "library:1", revision: "1", resources: []), state: "queued", confirmedBytes: 0, errorCode: nil)
    model.jobs = [library]
    XCTAssertTrue(model.photoLibraryInScope)
  }

  func testNewOnlyCaughtUpTitle() {
    XCTAssertEqual(BackupHubStatus.caughtUpTitle(saving: 0, earlierPhotosStarted: false), "hub_caught_up_new")
    XCTAssertEqual(BackupHubStatus.caughtUpTitle(saving: 0, earlierPhotosStarted: true), "hub_caught_up")
    XCTAssertEqual(BackupHubStatus.caughtUpTitle(saving: 1, earlierPhotosStarted: false), "hub_caught_up_saving")
    XCTAssertEqual(BackupHubStatus.caughtUpTitle(saving: 0, earlierPhotosStarted: false, autoBackup: false), "hub_caught_up_chosen")
  }
  func testBatchProgressPeakPartialClampAndReset() {
    var batch = HubBatchProgress()
    batch.observe(.backingUp(remaining: 100, bytes: 0))
    XCTAssertEqual(batch.fraction(remaining: 100, partial: 0), 0)
    batch.observe(.backingUp(remaining: 80, bytes: 0))
    XCTAssertEqual(batch.fraction(remaining: 80, partial: 0.5), 0.205, accuracy: 0.00001)
    batch.observe(.backingUp(remaining: 200, bytes: 0))
    XCTAssertEqual(batch.batchPeak, 200)
    XCTAssertEqual(batch.fraction(remaining: 200, partial: 1.5), 0.0075, accuracy: 0.00001)
    XCTAssertEqual(batch.fraction(remaining: 1, partial: 10), 1)
    XCTAssertEqual(batch.fraction(remaining: 300, partial: 0), 0)
    batch.observe(.paused)
    XCTAssertEqual(batch.batchPeak, 0)
    XCTAssertEqual(batch.fraction(remaining: 0, partial: 0), 0)
    batch.observe(.backingUp(remaining: 2, bytes: 0))
    XCTAssertEqual(batch.batchPeak, 2)
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

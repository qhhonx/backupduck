import XCTest
import SwiftUI
import Network
@testable import BackupDuck

@MainActor final class NetworkProgressTests: XCTestCase {
  func testGalleryResultUpdatesWhileOriginalPreparationIsBusy() async throws {
    #if !targetEnvironment(simulator)
      throw XCTSkip("State stream fixture is simulator-only")
    #endif
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("state-events-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let data = try await Bridge.call(["op": "start_receiver", "root": root.appendingPathComponent("receiver").path,
      "listen": "127.0.0.1:18496", "capacity": 32 * 1024 * 1024])
    let target = try JSONDecoder().decode(Pairing.self, from: data)
    let shared = BackupModel.shared
    await shared.open()
    let previousPause = shared.paused
    shared.stopProcessingEvents()
    // The hosted test runner may background its application after synthetic
    // window captures. Keep this result-stream fixture independent of scene
    // activation and of the shared model's discovery/lifecycle workers.
    let model = BackupModel(root: root)
    model.pairing = target; model.importing = true; model.paused = true
    addTeardownBlock { @MainActor in
      model.stopProcessingEvents()
      _ = try? await Bridge.call(["op": "stop_receiver"])
      _ = try? await Bridge.call(["op": "pause_sender", "paused": previousPause])
      shared.queueRevision = -1
      await shared.refresh(includeStorage: false)
      shared.startProcessingEvents()
    }
    _ = try await Bridge.call(["op": "pause_sender", "paused": false])
    let file = root.appendingPathComponent("generated.jpg")
    try Data(repeating: 42, count: 4096).write(to: file)
    let queued = try await Bridge.call(["op": "enqueue", "receiver_id": target.receiverID, "source_id": "generated-state-events-" + UUID().uuidString,
      "revision": "1", "kind": "photo", "resources": [["path": file.path, "role": "photo", "filename": "generated.jpg", "media_type": "image/jpeg"]]])
    let jobID = try XCTUnwrap((try JSONSerialization.jsonObject(with: queued) as? [String: Any])?["id"] as? Int64)
    let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(target))
    _ = try await Bridge.call(["op": "run_sender", "pairing": payload])
    await model.refresh(includeStorage: false)
    XCTAssertEqual(model.jobs.first(where: {$0.id == jobID})?.state, "received")
    let publicationData = try await Bridge.call(["op": "publications"])
    let publications = try XCTUnwrap(try JSONSerialization.jsonObject(with: publicationData) as? [[String: Any]])
    let publication = try XCTUnwrap(publications.first)
    let id = try XCTUnwrap(publication["id"] as? String)
    let asset = try XCTUnwrap(publication["asset"] as? [String: Any])
    let resources = try XCTUnwrap(asset["resources"] as? [[String: Any]])
    let hash = try XCTUnwrap(resources.first?["sha256"] as? String)
    model.startProcessingEvents(pollingAllowed: { true })
    try await Task.sleep(for: .milliseconds(150))
    _ = try await Bridge.call(["op": "gallery_publication", "id": id,
      "copy": ["locator": "content://generated/fixture/1", "sha256": hash, "size": 4096]])
    // Hosted simulators can schedule foreground/network callbacks more slowly
    // than a local device. Bound the asynchronous outcome, not machine speed.
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while ContinuousClock.now < deadline {
      if model.jobs.first(where: {$0.id == jobID})?.processing == "complete" { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(model.jobs.first(where: {$0.id == jobID})?.processing, "complete")
    XCTAssertTrue(model.importing, "The result monitor must not wait for original preparation")
    XCTAssertEqual(model.summary.published, 1)
  }

  func testLogExportSnapshotFailureKeepsCurrentWindowRetryable() async {
    var writes = 0
    let model = ActivityLogExportModel(snapshot: { throw NSError(domain: "SyntheticSnapshotFailure", code: 1) },
      write: { _ in writes += 1; return URL(fileURLWithPath: "/synthetic-unused.json") })
    await model.prepare()
    XCTAssertTrue(model.failed)
    XCTAssertFalse(model.preparing)
    XCTAssertNil(model.url, "A failed snapshot must not expose a shareable stale file")
    XCTAssertEqual(writes, 0)
  }

  func testLogExportWriterFailureRetriesUsingFreshSnapshot() async {
    var snapshots = 0, writes: [Data] = []
    let expected = URL(fileURLWithPath: "/synthetic-fresh-report.json")
    let model = ActivityLogExportModel(snapshot: {
      snapshots += 1; return Data([UInt8(snapshots)])
    }, write: { data in
      writes.append(data)
      if writes.count == 1 { throw NSError(domain: "SyntheticDiskFailure", code: 28) }
      return expected
    })
    await model.prepare()
    XCTAssertTrue(model.failed); XCTAssertNil(model.url)
    await model.prepare()
    XCTAssertFalse(model.failed); XCTAssertFalse(model.preparing)
    XCTAssertEqual(model.url, expected)
    XCTAssertEqual(writes, [Data([1]), Data([2])], "Retry must prepare a fresh snapshot rather than reuse failed export bytes")
  }

  func testLogExportRejectsDuplicatePreparationWhileBusy() async {
    var snapshots = 0
    var completion: CheckedContinuation<Data, Error>?
    let started = expectation(description: "snapshot started")
    let model = ActivityLogExportModel(snapshot: {
      snapshots += 1; started.fulfill()
      return try await withCheckedThrowingContinuation { completion = $0 }
    }, write: { _ in URL(fileURLWithPath: "/synthetic-single-report.json") })
    let first = Task { await model.prepare() }
    await fulfillment(of: [started], timeout: 2)
    XCTAssertTrue(model.preparing)
    await model.prepare()
    XCTAssertEqual(snapshots, 1)
    XCTAssertNil(model.url)
    completion?.resume(returning: Data("synthetic".utf8))
    await first.value
    XCTAssertFalse(model.preparing); XCTAssertFalse(model.failed)
    XCTAssertNotNil(model.url)
  }

  func testCancelledLogExportDoesNotBecomeReady() async {
    var completion: CheckedContinuation<Data, Error>?
    var writes = 0
    let started = expectation(description: "cancellable snapshot started")
    let model = ActivityLogExportModel(snapshot: {
      started.fulfill()
      return try await withCheckedThrowingContinuation { completion = $0 }
    }, write: { _ in writes += 1; return URL(fileURLWithPath: "/synthetic-cancelled.json") })
    let task = Task { await model.prepare() }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    completion?.resume(returning: Data("synthetic".utf8))
    await task.value
    XCTAssertFalse(model.preparing); XCTAssertFalse(model.failed)
    XCTAssertNil(model.url); XCTAssertEqual(writes, 0)
  }

  func testBusyAndInvalidPairingNeverReportSavedTrustAsNewSuccess() async {
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    model.pairing = pairing
    model.pairingInProgress = true
    let busy = await model.pair("invalid-qr")
    XCTAssertFalse(busy)
    XCTAssertEqual(model.pairing?.receiverID, "test")
    model.pairingInProgress = false
    let invalid = await model.pair("invalid-qr")
    XCTAssertFalse(invalid)
    XCTAssertFalse(model.pairingInProgress)
    XCTAssertNotNil(model.pairingError)
    XCTAssertEqual(model.pairing?.receiverID, "test")
  }

  private var pairing: Pairing {
    Pairing(version: 2, receiverID: "test", endpoint: "https://127.0.0.1:8443",
      certificate: "test", token: "test")
  }

  func testFailedPairingKeepsSavedTrustAndConnectionRecoverySeparate() {
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    model.pairing = pairing
    model.pairingError = "A different pairing attempt failed"
    model.receiverConnection = .ready
    let view = ReceiverStatusIndicator(model: model)
    XCTAssertEqual(view.status.key, "receiver_indicator_attention")
    XCTAssertEqual(model.pairing?.receiverID, "test", "Failed pairing must retain saved trust")
    model.pairingError = nil
    XCTAssertEqual(view.status.key, "receiver_indicator_connected")
    model.receiverConnection = .authentication
    XCTAssertEqual(view.status.key, "receiver_indicator_attention")
    model.receiverConnection = .network; model.receiverUnavailable = true
    XCTAssertEqual(view.status.key, "receiver_indicator_waiting")
    model.receiverConnection = .ready; model.receiverUnavailable = false
    XCTAssertEqual(view.status.key, "receiver_indicator_connected")
    model.receiverConnection = .unknown
    XCTAssertEqual(view.status.key, "receiver_indicator_paired", "Saved trust alone does not prove connectivity")
  }

  func testDiagnosticsKeepAuthenticationSeparateAndForceBypassesFailureCache() async {
    XCTAssertEqual(ReceiverConnection.failure(Bridge.Failure(code: "authentication")), .authentication)
    XCTAssertEqual(ReceiverConnection.failure(Bridge.Failure(code: "network")), .network)
    XCTAssertEqual(ReceiverConnection.failure(Bridge.Failure(code: "storage")), .unavailable)
    var probes = 0
    var response = ReceiverConnection.authentication
    let gate = ReceiverAvailability(monitorNetwork: false, diagnose: { _ in probes += 1; return response })
    gate.networkChanged(allowed: true)
    let first = await gate.diagnose(pairing)
    XCTAssertEqual(first, .authentication)
    response = .ready
    let cached = await gate.diagnose(pairing)
    XCTAssertEqual(cached, .authentication)
    let forced = await gate.diagnose(pairing, force: true)
    XCTAssertEqual(forced, .ready)
    XCTAssertEqual(probes, 2)
  }

  func testCellularAndUnreachableWifiBlockPreparationUntilReceiverReturns() async {
    var probes = 0
    var reachable = false
    let gate = ReceiverAvailability(monitorNetwork: false, probe: { _ in
      probes += 1; return reachable
    })
    gate.networkChanged(allowed: false)
    let cellular = await gate.check(pairing)
    XCTAssertFalse(cellular)
    XCTAssertEqual(probes, 0)
    gate.networkChanged(allowed: true)
    let foreignWifi = await gate.check(pairing)
    XCTAssertFalse(foreignWifi)
    XCTAssertEqual(probes, 1)
    reachable = true
    gate.networkChanged(allowed: true)
    let returned = await gate.check(pairing)
    XCTAssertTrue(returned)
    XCTAssertEqual(probes, 2)
  }

  func testNetworkChangeRejectsAnOldSuccessfulProbe() async {
    var completion: CheckedContinuation<Bool, Never>?
    let gate = ReceiverAvailability(monitorNetwork: false, probe: { _ in
      await withCheckedContinuation { completion = $0 }
    })
    gate.networkChanged(allowed: true)
    let check = Task { await gate.check(pairing) }
    while completion == nil { await Task.yield() }
    gate.networkChanged(allowed: false)
    completion?.resume(returning: true)
    let value = await check.value
    XCTAssertFalse(value)
  }

  func testMixedWifiAndCellularCanProbeButCellularAloneCannot() async {
    var probes = 0
    var reachable = true
    let gate = ReceiverAvailability(monitorNetwork: false, probe: { _ in
      probes += 1; return reachable
    })
    gate.networkChanged(satisfied: true, interfaces: [.wifi, .cellular])
    let mixed = await gate.check(pairing)
    XCTAssertTrue(mixed)
    XCTAssertEqual(probes, 1)

    gate.networkChanged(satisfied: true, interfaces: [.cellular])
    let cellular = await gate.check(pairing)
    XCTAssertFalse(cellular)
    XCTAssertEqual(probes, 1)

    gate.networkChanged(satisfied: false, interfaces: [.wifi, .cellular])
    let unavailable = await gate.check(pairing)
    XCTAssertFalse(unavailable)
    XCTAssertEqual(probes, 1)

    reachable = false
    gate.networkChanged(satisfied: true, interfaces: [.wifi, .cellular])
    let foreignNetwork = await gate.check(pairing)
    XCTAssertFalse(foreignNetwork)
    XCTAssertEqual(probes, 2)

    reachable = true
    gate.networkChanged(satisfied: true, interfaces: [.wiredEthernet, .cellular])
    let ethernet = await gate.check(pairing)
    XCTAssertTrue(ethernet)
    XCTAssertEqual(probes, 3)
  }

  func testConcurrentProgressDoesNotOverwriteAnotherJobOrResetOnPolling() {
    var tracker = TaskProgressTracker()
    let a = NativeAttempt(jobID: 1, generation: 1)
    let b = NativeAttempt(jobID: 2, generation: 1)
    tracker.update(taskID: 10, attempt: a, sent: 250, expected: 1000, phase: "bundle", baseline: 0)
    tracker.update(taskID: 20, attempt: b, sent: 700, expected: 1000, phase: "bundle", baseline: 0)
    XCTAssertEqual(tracker.jobs[1]?.displayedBytes(confirmed: 0, total: 800), 200)
    tracker.waiting(taskID: 10)
    tracker.update(taskID: 10, attempt: a, sent: 250, expected: 1000, phase: "bundle", baseline: 0)
    XCTAssertEqual(tracker.jobs[1]?.waitingForNetwork, true)
    tracker.remove(taskID: 20)
    XCTAssertNotNil(tracker.jobs[1])
    tracker.update(taskID: 10, attempt: a, sent: 500, expected: 1000, phase: "bundle", baseline: 0)
    XCTAssertEqual(tracker.jobs[1]?.waitingForNetwork, false)
    XCTAssertEqual(tracker.jobs[1]?.displayedBytes(confirmed: 0, total: 800), 400)
    XCTAssertEqual(tracker.jobs[1]?.displayedBytes(confirmed: 600, total: 800), 600)
  }

  func testProgressBarOnlyAppearsDuringMediaTransfer() {
    var progress = TransferProgress(sent: 0, expected: 1000, baseline: 0, phase: "bundle")
    XCTAssertNil(progress.activeFraction(confirmed: 0, total: 800))
    progress.sent = 500
    XCTAssertEqual(progress.activeFraction(confirmed: 0, total: 800), 0.5)
    progress.sent = 1000
    XCTAssertNil(progress.activeFraction(confirmed: 0, total: 800))
    progress.phase = "commit"
    progress.sent = 1
    progress.expected = 2
    XCTAssertNil(progress.activeFraction(confirmed: 800, total: 800))
    progress.phase = "upload"
    progress.sent = 100
    progress.expected = 400
    progress.baseline = 400
    XCTAssertEqual(progress.activeFraction(confirmed: 400, total: 800), 0.625)
    progress.waitingForNetwork = true
    XCTAssertNil(progress.activeFraction(confirmed: 400, total: 800))
    progress.waitingForNetwork = false
    XCTAssertNil(progress.activeFraction(confirmed: 800, total: 800))
    XCTAssertNil(progress.activeFraction(confirmed: 0, total: 0))
  }
}


extension NetworkProgressTests {
  func testStatusIndicatorHeightRemainsStableForLongErrorsAndNetworkWarnings() async {
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let host = UIHostingController(rootView: BackupStatusIndicator(model: model))
    host.loadViewIfNeeded()
    let size = CGSize(width: 340, height: 1000)
    let initial = host.sizeThatFits(in: size).height
    XCTAssertEqual(initial, 44, accuracy: 1)
    model.message = String(repeating: "A long error message requiring details. ", count: 30)
    await Task.yield()
    host.view.layoutIfNeeded()
    XCTAssertEqual(host.sizeThatFits(in: size).height, initial, accuracy: 1)
    model.message = nil
    model.waitingForNetwork = true
    model.pendingImports = 12_000
    await Task.yield()
    host.view.layoutIfNeeded()
    XCTAssertEqual(host.sizeThatFits(in: size).height, initial, accuracy: 1)
  }
}


extension NetworkProgressTests {
  func testActivityLogUpdatesWithoutReplacingUnchangedOrReadingRows() async {
    func entry(_ id: Int64) -> ActivityEntry {
      ActivityEntry(id: id, timestamp: id, code: "app_foreground", job_id: nil, bytes: nil, context: nil)
    }
    var response = ActivityLogUpdate(entries: [entry(2), entry(1)], oldest_id: 1, newest_id: 2, reset: false)
    var shouldFail = false
    var requested: [Int64] = []
    let model = ActivityLogModel { cursor in
      requested.append(cursor)
      if shouldFail { throw NSError(domain: "test", code: 1) }
      return response
    }
    var publications = 0
    let subscription = model.$entries.sink { _ in publications += 1 }
    defer { subscription.cancel() }
    await model.refresh { true }
    XCTAssertEqual(model.entries.map(\.id), [2, 1])
    let initialPublications = publications
    response = ActivityLogUpdate(entries: [], oldest_id: 1, newest_id: 2, reset: false)
    await model.refresh { true }
    XCTAssertEqual(publications, initialPublications)
    response = ActivityLogUpdate(entries: [entry(3)], oldest_id: 2, newest_id: 3, reset: false)
    await model.refresh { false }
    XCTAssertEqual(model.entries.map(\.id), [2, 1])
    XCTAssertEqual(model.pendingCount, 1)
    XCTAssertEqual(publications, initialPublications)
    shouldFail = true
    await model.refresh { true }
    XCTAssertTrue(model.failed)
    XCTAssertEqual(model.cursor, 3)
    XCTAssertEqual(model.entries.map(\.id), [2, 1])
    shouldFail = false
    await model.refresh { false }
    XCTAssertFalse(model.failed)
    model.showLatest()
    XCTAssertEqual(model.entries.map(\.id), [3, 2])
    XCTAssertEqual(model.pendingCount, 0)
    XCTAssertEqual(requested, [0, 2, 2, 3, 3])
    response = ActivityLogUpdate(entries: [], oldest_id: nil, newest_id: nil, reset: true)
    await model.refresh { true }
    XCTAssertTrue(model.entries.isEmpty)
    XCTAssertEqual(model.cursor, 0)
  }

  func testActivityLogChecksReadingPositionAfterFetchCompletes() async {
    var completion: CheckedContinuation<ActivityLogUpdate, Never>?
    var following = true
    let model = ActivityLogModel { _ in
      await withCheckedContinuation { completion = $0 }
    }
    let initial = Task { await model.refresh { true } }
    while completion == nil { await Task.yield() }
    completion?.resume(returning: ActivityLogUpdate(entries: [], oldest_id: nil, newest_id: nil, reset: false))
    await initial.value
    completion = nil
    let poll = Task { await model.refresh { following } }
    while completion == nil { await Task.yield() }
    following = false
    let entry = ActivityEntry(id: 1, timestamp: 1, code: "app_foreground", job_id: nil, bytes: nil, context: nil)
    completion?.resume(returning: ActivityLogUpdate(entries: [entry], oldest_id: 1, newest_id: 1, reset: false))
    let followed = await poll.value
    XCTAssertFalse(followed)
    XCTAssertTrue(model.entries.isEmpty)
    XCTAssertEqual(model.pendingCount, 1)
  }
}

// Visual evidence from real SwiftUI/UIKit windows, using in-memory synthetic
// model values only. These captures are not pixel-diff or fidelity pass tests.
extension NetworkProgressTests {
  func testSharedSheetChromeInNativeWindows() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("Synthetic sheet fixtures run only in the dedicated simulator")
    #endif
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene); window.frame = UIScreen.main.bounds; window.windowLevel = .normal + 1
    defer { window.isHidden = true; previous?.makeKeyAndVisible() }
    for mode in 0..<3 {
      let title: LocalizedStringKey = mode == 2
        ? "Original preparation details for a photo with a long descriptive title"
        : "original_preparation_detail"
      let sheet = DuckSheetLayout(title: title,busy: mode == 2,
        error: mode == 1 ? NSLocalizedString("apple_retry_failed",comment: "") : nil) {
        Text("Example-photo.HEIC").font(.headline)
        Text("state_preparing").foregroundStyle(DuckColors.textSecondary)
      } actions: {
        DuckSheetAction(title: "settings_done") {}.disabled(mode == 2)
        if mode == 1 { DuckSheetAction(title: "retry_task",primary: true) {} }
      }
      let root = FidelityModalFixture {
        sheet.environment(\.locale,Locale(identifier: mode == 2 ? "en_US" : "zh_CN"))
          .environment(\.dynamicTypeSize,mode == 2 ? .accessibility3 : .large)
      }.preferredColorScheme(mode == 1 ? .dark : .light)
      let host = UIHostingController(rootView: root)
      window.rootViewController = host; window.makeKeyAndVisible()
      try await Task.sleep(for: .milliseconds(900)); host.view.layoutIfNeeded()
      XCTAssertNotNil(host.presentedViewController,"Exercise a presented native sheet, not an off-screen view")
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds,afterScreenUpdates: true)
      }
      let attachment = XCTAttachment(image: image)
      attachment.name = "Shared sheet chrome — scenario \(mode)"; attachment.lifetime = .keepAlways; add(attachment)
      window.rootViewController = nil
    }
  }

  func testFidelityPairedAndTransferWindows() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("Only the dedicated simulator may host synthetic UI fixtures")
    #endif
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
      throw XCTSkip("A native window scene is required")
    }
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    window.windowLevel = .normal + 1
    defer { window.isHidden = true; previous?.makeKeyAndVisible() }
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent("fidelity-" + UUID().uuidString))
    model.ready = true; model.paused = false
    model.pairing = Pairing(version: 2, receiverID: "synthetic-pixel", endpoint: "https://192.0.2.10:8484", certificate: "synthetic", token: "synthetic")
    model.deviceSnapshot = DeviceSnapshot(device: DeviceProfile(id: "synthetic-iphone", name: "Example iPhone"), peers: [
      DeviceSnapshot.Peer(key: "synthetic-pixel", profile: DeviceProfile(id: "synthetic-pixel", name: "Example Pixel"), last_seen: 0)])
    model.summary = SenderSummary(total: 248, received: 242, published: 240, failed: 2, queued: 5, running: 1)
    func capture<V: View>(_ name: String, _ view: V) async throws {
      let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: "en_US")).preferredColorScheme(.light))
      window.rootViewController = host; window.makeKeyAndVisible()
      try await Task.sleep(for: .milliseconds(800))
      host.view.layoutIfNeeded()
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      let attachment = XCTAttachment(image: image)
      attachment.name = "fidelity-native-" + name; attachment.lifetime = .keepAlways; add(attachment)
      window.rootViewController = nil
    }
    try await capture("backup-paired-overview", VStack(spacing: 0) {
      IOSPrototypeHeader("nav_backup")
      ScrollView { DuckBackupProgress(model: model, showTransfers: {}, title: "apple_history_progress_title").iosPrototypePageBody() }
    }.background(DuckColors.canvas))
    model.paused = true
    try await capture("backup-paused-overview", VStack(spacing: 0) {
      IOSPrototypeHeader("nav_backup")
      ScrollView { DuckBackupProgress(model: model, showTransfers: {}, title: "apple_history_progress_title").iosPrototypePageBody() }
    }.background(DuckColors.canvas))
    model.paused = false
    try await capture("receiver-paired", IOSReceiverPage(model: model))
    try await capture("selected-backup", SelectedBackupToolbarFixture())
    try await capture("selected-backup-repeat", SelectedBackupToolbarFixture(repeatConfirmation: true))
    for (name, state, processing, captured) in [
      ("transfer-failed", "failed", "pending", true),
      ("transfer-received", "received", "pending", true),
      ("transfer-published", "received", "complete", true),
      ("transfer-publication-failed", "received", "failed", true),
      ("transfer-missing-date", "received", "pending", false)] {
      let asset = BackupJob.Asset(metadata: captured ? ["created_at_ms": "1790913600000", "source_name": "Example iPhone"] : ["source_name": "Example iPhone"], kind: "burst", source_id: "synthetic-photo", revision: "synthetic", resources: [.init(filename: "IMG_5400.HEIC", size: 12687770)])
      let job = BackupJob(id: 1, asset: asset, state: state, confirmedBytes: state == "received" ? 12687770 : 0,
        errorCode: state == "failed" ? "receiver_unavailable" : nil, processing: processing, processingError: processing == "failed" ? "unsupported_motion" : nil)
      try await capture(name, FidelityModalFixture {
        DuckTransferDetail(job: job, status: NSLocalizedString(state == "failed" ? "state_failed" : processing == "complete" ? "state_published" : processing == "failed" ? "state_publication_failed" : "state_received", comment: ""),
              symbol: processing == "failed" ? "exclamationmark.triangle" : processing == "complete" ? "checkmark" : "clock", tone: processing == "failed" || state == "failed" ? .failure : processing == "complete" ? .saved : .attention, retry: { false })
      })
    }
  }
}
private struct SelectedBackupToolbarFixture: View {
  var repeatConfirmation = false
  @StateObject private var action = SelectionBackupAction()
  @State private var count = 3
  var body: some View {
    NavigationStack {
      Text("Synthetic selection").navigationTitle("nav_library")
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            DuckSelectionBackupControl(action: action, count: count, request: {
              await action.perform({ count = 0; return true }, failure: { nil })
            }, confirm: {
              action.confirmingRepeat = false
              await action.perform({ count = 0; return true }, failure: { nil })
            })
          }
        }
        .task { if repeatConfirmation { action.confirmingRepeat = true } }
    }
  }
}
private struct FidelityModalFixture<Content: View>: View {
  @ViewBuilder var content: () -> Content
  @State private var presented = true
  var body: some View {
    VStack(spacing: 0) { IOSPrototypeHeader("nav_backup"); Spacer() }
      .background(DuckColors.canvas).sheet(isPresented: $presented, content: content)
  }
}

@MainActor final class TransferDetailFeedbackTests: XCTestCase {
  private func job(state: String = "received", processing: String? = "complete",
    timestamp: Int64? = 1700000000000, receiver: String? = "historical-pixel") -> BackupJob {
    BackupJob(id: 1, asset: .init(metadata: ["source_name": "Example iPhone", "created_at_ms": "1600000000000"],
      kind: "photo", source_id: "synthetic-source", revision: "1", resources: [.init(filename: "synthetic.jpg", size: 100)]),
      state: state, confirmedBytes: state == "received" ? 100 : 0, errorCode: nil,
      processing: processing, stateChangedAt: timestamp, receiverID: receiver)
  }
  func testJobReceiverIdentityDecodingAndLegacyFallback() throws {
    let json = Data(#"{"id":1,"receiver_id":"historical-pixel","asset":{"kind":"photo","source_id":"synthetic","revision":"1","resources":[{"filename":"synthetic.jpg","size":100}]},"state":"received","confirmed_bytes":100,"error_code":null,"processing":"complete"}"#.utf8)
    XCTAssertEqual(try JSONDecoder().decode(BackupJob.self, from: json).receiverID, "historical-pixel")
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
    legacy.removeValue(forKey: "receiver_id")
    XCTAssertNil(try JSONDecoder().decode(BackupJob.self, from: JSONSerialization.data(withJSONObject: legacy)).receiverID)
  }
  func testHistoricalReceiverDoesNotFollowCurrentPairing() {
    let model = BackupModel(root: URL(fileURLWithPath: "/synthetic-unused"))
    model.deviceSnapshot = DeviceSnapshot(device: .init(id: "sender", name: "Example iPhone"), peers: [
      .init(key: "historical-pixel", profile: .init(id: "old-profile", name: "Old Pixel"), last_seen: 0),
      .init(key: "new-pixel", profile: .init(id: "new-profile", name: "New Pixel"), last_seen: 0),
    ])
    model.pairing = Pairing(version: 2, receiverID: "new-pixel", endpoint: "https://192.0.2.10:8484", certificate: "", token: "")
    XCTAssertEqual(model.receiverDeviceName(for: job()), "Old Pixel")
    XCTAssertNil(model.receiverDeviceName(for: job(receiver: nil)))
    XCTAssertNil(model.receiverDeviceName(for: job(receiver: "missing-pixel")))
    model.pairing = nil
    XCTAssertEqual(model.receiverDeviceName(for: job()), "Old Pixel", "Unpairing must not replace the job's historical destination")
  }
  func testReceiptTimeIsNotCaptureOrGalleryTime() {
    let received = TransferDetailFacts(job: job())
    XCTAssertEqual(received.receiptConfirmedAt?.timeIntervalSince1970, 1700000000)
    XCTAssertNil(received.gallerySavedAt, "Job has no gallery publication timestamp")
    XCTAssertNil(TransferDetailFacts(job: job(state: "failed")).receiptConfirmedAt)
    XCTAssertNil(TransferDetailFacts(job: job(state: "running")).receiptConfirmedAt)
    XCTAssertNil(TransferDetailFacts(job: job(timestamp: nil)).receiptConfirmedAt)
    XCTAssertNil(TransferDetailFacts(job: job(timestamp: 0)).receiptConfirmedAt)
  }
  func testGalleryAndCloudRemainSeparateFacts() {
    let pending = TransferDetailFacts(job: job(processing: "pending"))
    XCTAssertTrue(pending.receiptConfirmed); XCTAssertFalse(pending.galleryConfirmed)
    XCTAssertEqual(pending.originalNode, .confirmed); XCTAssertEqual(pending.galleryNode, .pending)
    let failed = TransferDetailFacts(job: job(processing: "failed"))
    XCTAssertTrue(failed.receiptConfirmed); XCTAssertEqual(failed.galleryNode, .failed)
    let saved = TransferDetailFacts(job: job())
    XCTAssertTrue(saved.galleryConfirmed); XCTAssertFalse(saved.cloudConfirmed)
    XCTAssertFalse(TransferDetailFacts(job: job(state: "queued")).galleryConfirmed)
  }
}

@MainActor final class TransferListFeedbackTests: XCTestCase {
  func testFourUserCategoriesKeepSourceRecordsSeparate() {
    XCTAssertEqual(TransferUserCategories.keys, ["all", "active", "attention", "saved"])
    XCTAssertEqual(TransferUserCategories.initial("queued"), "active")
    XCTAssertEqual(TransferUserCategories.initial("failed"), "attention")
    XCTAssertEqual(TransferUserCategories.initial("preparing"), "active")
    XCTAssertEqual(TransferUserCategories.initial("scanned"), "all")
    XCTAssertFalse(TransferUserCategories.keys.contains("preparing"))
    XCTAssertFalse(TransferUserCategories.keys.contains("received"))
  }
  func testDirectSortChoicesAreFourAtomicResultsAndPersist() throws {
    XCTAssertEqual(TransferOrdering.directChoices.map(\.id), ["capture_latest", "capture_earliest", "added_latest", "added_earliest"])
    let values = TransferOrdering.directChoices.map(\.ordering)
    XCTAssertEqual(Set(values).count, 4)
    for value in values { XCTAssertEqual(try JSONDecoder().decode(TransferOrdering.self, from: JSONEncoder().encode(value)), value) }
    XCTAssertEqual(values[0].sort, "capture"); XCTAssertTrue(values[0].descending)
    XCTAssertEqual(values[1].sort, "capture"); XCTAssertFalse(values[1].descending)
    XCTAssertEqual(values[2].sort, "added"); XCTAssertTrue(values[2].descending)
    XCTAssertEqual(values[3].sort, "added"); XCTAssertFalse(values[3].descending)
    XCTAssertFalse(values.contains { $0.sort == "retry" || $0.sort == "activity" })
  }
  func testAttentionIncludesGalleryPublicationFailures() {
    var summary = SenderSummary(); summary.failed = 2; summary.publication_failed = 3; summary.published = 4
    XCTAssertEqual(summary.count(for: "attention"), 5)
    XCTAssertEqual(summary.count(for: "saved"), 4)
  }
  func testFourCategoriesCoverPendingGalleryWithoutDoubleCounting() {
    var summary = SenderSummary()
    summary.total = 16; summary.queued = 3; summary.running = 1; summary.waiting = 2; summary.paused = 1
    summary.failed = 2; summary.received = 7; summary.published = 3; summary.publication_failed = 2
    XCTAssertEqual(summary.count(for: "active"), 9, "Two received items with unconfirmed gallery status remain active")
    XCTAssertEqual(summary.count(for: "attention"), 4)
    XCTAssertEqual(summary.count(for: "saved"), 3)
    XCTAssertEqual(summary.count(for: "active") + summary.count(for: "attention") + summary.count(for: "saved"), summary.total)
    summary.received = 1; summary.published = 3
    XCTAssertGreaterThanOrEqual(summary.count(for: "active"), 0, "Malformed old counts must not create a negative pending count")
  }
}

@MainActor final class ActivityLogFeedbackTests: XCTestCase {
  func testDetailSnapshotAndVisibleRowsRemainStableUntilShowLatest() async {
    let first = ActivityEntry(id: 1, timestamp: 1, code: "backup_paused", job_id: 7, bytes: nil, context: nil)
    let second = ActivityEntry(id: 2, timestamp: 2, code: "sender_ready", job_id: nil, bytes: nil, context: nil)
    var response = ActivityLogUpdate(entries: [first], oldest_id: 1, newest_id: 1, reset: false)
    let journal = ActivityLogModel { _ in response }
    await journal.refresh { true }
    let detailSnapshot = journal.entries[0]
    response = ActivityLogUpdate(entries: [second], oldest_id: 1, newest_id: 2, reset: false)
    await journal.refresh { false }
    XCTAssertEqual(journal.entries.map(\.id), [1]); XCTAssertEqual(journal.pendingCount, 1)
    XCTAssertEqual(detailSnapshot.id, 1); XCTAssertEqual(detailSnapshot.job_id, 7)
    await journal.refresh { false } // Closing a detail does not implicitly ShowLatest.
    XCTAssertEqual(journal.entries.map(\.id), [1])
    journal.showLatest()
    XCTAssertEqual(journal.entries.map(\.id), [2, 1]); XCTAssertEqual(journal.pendingCount, 0)
    XCTAssertEqual(detailSnapshot.code, "backup_paused")
  }
}

@MainActor final class DiagnosticsProjectionTests: XCTestCase {
  func testUnknownEventUsesItsCode() throws {
    let data = Data(#"{"id":42,"timestamp":1792638000,"code":"future_event_v3","future_top":"retained"}"#.utf8)
    XCTAssertEqual(try JSONDecoder().decode(ActivityEntry.self, from: data).title, "future_event_v3")
  }
  func testRecentActivityIsLimitedToSixNewestEvents() async {
    let entries = (1...9).map { ActivityEntry(id: Int64($0), timestamp: Int64($0), code: "sender_ready", job_id: nil, bytes: nil, context: nil) }
    let model = ActivityLogModel { _ in .init(entries: entries, oldest_id: 1, newest_id: 9, reset: true) }
    await model.refresh { true }
    XCTAssertEqual(model.recentEntries.map(\.id), [9, 8, 7, 6, 5, 4])
  }
  func testNewestTimestampWinsWhileCursorUsesRecordIdentity() async {
    let entries = [ActivityEntry(id: 8, timestamp: 100, code: "sender_ready", job_id: nil, bytes: nil, context: nil),
      ActivityEntry(id: 7, timestamp: 200, code: "sender_ready", job_id: nil, bytes: nil, context: nil)]
    let model = ActivityLogModel { _ in .init(entries: entries, oldest_id: 7, newest_id: 8, reset: true) }
    await model.refresh { true }
    XCTAssertEqual(model.entries.map(\.id), [7, 8])
    XCTAssertEqual(model.cursor, 8)
  }
  func testDefaultExportWritesAnExactJSONFile() async throws {
    let bytes = Data(#"[{"id":42,"timestamp":100,"code":"request_failed","context":{"http_status":503,"future":{"amount":9223372036854775806}},"unknown_field":"preserved"}]"#.utf8)
    let model = ActivityLogExportModel(snapshot: { bytes })
    await model.prepare()
    let url = try XCTUnwrap(model.url)
    XCTAssertEqual(url.lastPathComponent, "BackupDuck-diagnostics.json")
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    try FileManager.default.removeItem(at: url.deletingLastPathComponent())
  }
  func testStorageRefreshMigratesOldRetentionWithoutMaintenance() async throws {
    let original = BackupEnvironment.core
    defer { BackupEnvironment.core = original }
    let core = LogSettingsCore(); BackupEnvironment.core = core
    let originalSettings = core.settings
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    model.ready = true
    await model.refreshStorage()
    XCTAssertEqual(core.operations, ["storage_status", "save_storage_settings"])
    XCTAssertEqual(core.settings.log_days, 14)
    XCTAssertEqual(core.settings.log_limit, originalSettings.log_limit)
    XCTAssertEqual(core.settings.cache_budget_bytes, originalSettings.cache_budget_bytes)
    XCTAssertEqual(core.settings.auto_reclaim, originalSettings.auto_reclaim)
    await model.refreshStorage()
    XCTAssertEqual(core.operations.filter { $0 == "save_storage_settings" }.count, 1)
  }
  func testFixedLogRetentionSavesWithoutStartingMaintenanceAndKeepsFailureRetryable() async throws {
    let original = BackupEnvironment.core
    defer { BackupEnvironment.core = original }
    let core = LogSettingsCore(); BackupEnvironment.core = core
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    model.ready = true
    var settings = core.settings; settings.log_days = 7
    await model.saveStorage(settings, performMaintenance: false)
    XCTAssertEqual(core.operations, ["save_storage_settings", "storage_status"])
    XCTAssertEqual(model.storage?.settings.log_days, 14)
    XCTAssertTrue(model.storage?.settings.auto_reclaim == true)
    core.fail = true; settings.log_days = 14
    await model.saveStorage(settings, performMaintenance: false)
    XCTAssertNotNil(model.storageSettingsError)
    XCTAssertEqual(model.storage?.settings.log_days, 14)
    XCTAssertFalse(model.savingStorage)
    core.fail = false
    await model.saveStorage(settings, performMaintenance: false)
    XCTAssertNil(model.storageSettingsError)
    XCTAssertEqual(model.storage?.settings.log_days, 14)
  }

}

private final class LogSettingsCore: CoreTransport, @unchecked Sendable {
  var operations: [String] = []
  var fail = false
  var settings = StorageSettings(cache_budget_bytes: 1 << 30, receiver_budget_bytes: 0,
    min_free_bytes: 1 << 30, auto_reclaim: true, log_days: 30, log_limit: 2000)
  func call(_ command: String) async throws -> Data {
    let object = try JSONSerialization.jsonObject(with: Data(command.utf8)) as! [String: Any]
    let op = object["op"] as! String; operations.append(op)
    if op == "save_storage_settings" {
      if fail { throw Bridge.Failure(code: "storage") }
      settings = try JSONDecoder().decode(StorageSettings.self,
        from: JSONSerialization.data(withJSONObject: object["settings"]!))
    }
    let value: Any = op == "storage_status" ? ["settings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)),
      "used_bytes": 0, "free_bytes": 10 << 30, "export_allowance": 1 << 30] : NSNull()
    return try JSONSerialization.data(withJSONObject: ["ok": true, "value": value])
  }
}

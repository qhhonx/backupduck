import XCTest
import UIKit
@testable import BackupDuck

final class LibraryPresentationTests: XCTestCase {
  func testRangeSelectionRestoresBacktrackedItemsAndPreservesOutsideSnapshot() {
    let drag = LibraryRangeSelection(baseline: ["outside", "b"], adding: true)
    XCTAssertEqual(drag.applying(["a", "b", "c"]), ["outside", "a", "b", "c"])
    XCTAssertEqual(drag.applying(["a"]), ["outside", "a", "b"])
    let remove = LibraryRangeSelection(baseline: ["outside", "a", "b", "c"], adding: false)
    XCTAssertEqual(remove.applying(["a", "b", "c"]), ["outside"])
    XCTAssertEqual(remove.applying(["a"]), ["outside", "b", "c"])
    XCTAssertEqual(remove.baseline, ["outside", "a", "b", "c"])
  }

  func testBurstFramesAcrossPagesStayOneRowAndPreserveIdentity() {
    var records = (0..<1000).map { LibraryPresentationIndex.Metadata(id: "photo-\($0)", burst: nil, representative: false) }
    records[0] = .init(id: "burst-a-first", burst: "a", representative: false)
    records[1] = .init(id: "burst-a-second", burst: "a", representative: false)
    records[500] = .init(id: "burst-a-picked", burst: "a", representative: true)
    var index = LibraryPresentationIndex()
    var reads = 0
    index.load(sourceCount: records.count, targetRows: 240) { reads += 1; return records[$0] }
    XCTAssertEqual(index.rows.count, 240)
    XCTAssertEqual(index.cursor, 241)
    XCTAssertEqual(reads, 241, "Initial presentation must not enumerate the entire library")
    XCTAssertEqual(index.rows[0].key, "burst:a")
    XCTAssertEqual(index.rows[0].rawIndex, 0)
    let changed = index.load(sourceCount: records.count, targetRows: 720) { records[$0] }
    XCTAssertTrue(changed)
    XCTAssertEqual(index.rows[0].rawIndex, 500)
    XCTAssertEqual(index.positions["burst:a"], 0)
    XCTAssertEqual(index.rows.filter { $0.key == "burst:a" }.count, 1)
  }

  func testCancelledMetadataWorkStopsReadingAnOversizedBurst() {
    var index = LibraryPresentationIndex()
    var reads = 0
    index.load(sourceCount: 1_000_000, targetRows: 240, shouldContinue: { reads < 100 }) { i in
      reads += 1
      return .init(id: "frame-\(i)", burst: "a", representative: false)
    }
    XCTAssertEqual(reads, 100)
    XCTAssertEqual(index.cursor, 100)
    XCTAssertEqual(index.rows.count, 1)
  }

  func testLargeBurstDoesNotCreateEmptyPaginationAndAnchorCanExpandWindow() {
    let records = (0..<1200).map { LibraryPresentationIndex.Metadata(id: "frame-\($0)", burst: $0 < 1100 ? "a" : nil, representative: $0 == 900) }
    var index = LibraryPresentationIndex()
    index.load(sourceCount: records.count, targetRows: 20) { records[$0] }
    XCTAssertEqual(index.rows.count, 20)
    XCTAssertEqual(index.cursor, 1119)
    XCTAssertEqual(index.rows[0].rawIndex, 900)
    index.load(sourceCount: records.count, targetRows: 20, minimumCursor: 1200) { records[$0] }
    XCTAssertEqual(index.rows.count, 101)
    XCTAssertEqual(index.cursor, 1200)
  }

  @MainActor func testNativeBurstBadgesAndAccessibilityReset() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    let controller = UIViewController()
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    for style in [UIUserInterfaceStyle.light, .dark] {
      let panel = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 160))
      window.overrideUserInterfaceStyle = style
      panel.overrideUserInterfaceStyle = style
      panel.backgroundColor = .systemBackground
      controller.view.addSubview(panel)
      var cells: [PhotoCell] = []
      for (index, state) in ["received", "partial", "failed"].enumerated() {
        let cell = PhotoCell(frame: CGRect(x: 8 + index * 128, y: 8, width: 120, height: 140))
        cell.contentView.backgroundColor = [.systemTeal, .systemIndigo, .systemBrown][index]
        panel.addSubview(cell)
        cell.setGroup(count: [8, 32, 1200][index], state: state)
        cell.isSelected = index == 1
        cell.layoutIfNeeded()
        XCTAssertTrue(cell.accessibilityValue?.contains(String(format: NSLocalizedString("library_burst_count", comment: ""), [8, 32, 1200][index])) == true)
        XCTAssertEqual(cell.accessibilityHint, NSLocalizedString("library_burst_selection", comment: ""))
        cells.append(cell)
      }
      panel.layoutIfNeeded()
      try await Task.sleep(nanoseconds: 100_000_000)
      let image = UIGraphicsImageRenderer(bounds: panel.bounds).image { _ in
        XCTAssertTrue(panel.drawHierarchy(in: panel.bounds, afterScreenUpdates: true))
      }
      let attachment = XCTAttachment(image: image)
      attachment.name = style == .dark ? "burst-cells-dark" : "burst-cells-light"
      attachment.lifetime = .keepAlways
      add(attachment)
      cells[0].setGroup(count: nil, state: nil)
      XCTAssertNil(cells[0].accessibilityHint)
      XCTAssertEqual(cells[0].accessibilityValue, NSLocalizedString("state_not_queued", comment: ""))
      panel.removeFromSuperview()
    }
  }

  func testWholeBurstStatusCannotBeInferredFromCoverReceipt() {
    let group = LibraryGroup(sources: (0..<3).map { LibrarySource(id: "\($0)", revision: "1") }, complete: true)
    XCTAssertNil(group.state([:]))
    XCTAssertEqual(group.state(["0": "received"]), "partial")
    XCTAssertEqual(group.state(["0": "received", "1": "running"]), "running")
    XCTAssertEqual(group.state(["0": "received", "1": "failed", "2": "running"]), "failed")
    XCTAssertEqual(group.state(["0": "received", "1": "received", "2": "received"]), "received")
    XCTAssertEqual(group.state(["0": "received", "1": "received_previous", "2": "received"]), "received_previous")
    XCTAssertEqual(group.state(["0": "received_previous"]), "partial")
    XCTAssertEqual(group.state(["0": "received", "1": "received", "2": "waiting"]), "waiting")
    XCTAssertNil(LibraryGroup(sources: group.sources, complete: false).state(["0": "received", "1": "received", "2": "received"]))
    XCTAssertNil(LibraryGroup(sources: [], complete: true).state([:]))
  }
}


@MainActor final class HistoricalSnapshotBindingTests: XCTestCase {
  func testUnboundCaptureCannotReplaceAnActiveScopeAndMissingSnapshotIsNotRecreated() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try HistoricalScanCursor.persistSnapshot(root: root, receiver: "receiver", ids: ["original"])
    let later = try HistoricalScanCursor.persistSnapshot(root: root, receiver: "receiver", ids: ["original", "later"])
    let active = try await HistoricalScanCursor.load(root: root, receiver: "receiver", run: 1, snapshotID: first)
    XCTAssertEqual(active.ids, ["original"])
    try active.advance(to: 1)
    let restored = try await HistoricalScanCursor.load(root: root, receiver: "receiver", run: 1, snapshotID: first)
    XCTAssertEqual(restored.offset, 1)
    let next = try await HistoricalScanCursor.load(root: root, receiver: "receiver", run: 2, snapshotID: later)
    XCTAssertEqual(next.ids, ["original", "later"])
    do { _ = try await HistoricalScanCursor.load(root: root, receiver: "receiver", run: 3, snapshotID: first); XCTFail("Rebound an existing snapshot") }
    catch { XCTAssertEqual((error as? Bridge.Failure)?.code, "history_snapshot_unavailable") }
    let before = try FileManager.default.contentsOfDirectory(atPath: root.path).count
    do { _ = try await HistoricalScanCursor.load(root: root, receiver: "receiver", run: 1, snapshotID: "missing"); XCTFail("Recreated missing scope") }
    catch { XCTAssertEqual((error as? Bridge.Failure)?.code, "history_snapshot_unavailable") }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, before)
  }
}

@MainActor final class DiscoveryLedgerHandoffTests: XCTestCase {
  func testActualBridgeHandoffDoesNotRecreateWorkCompletedBeforeNativeAcknowledgement() async throws {
    #if !targetEnvironment(simulator)
      throw XCTSkip("Generated registry fixture is simulator-only")
    #endif
    await BackupModel.shared.open()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let receiver = "discovery-" + UUID().uuidString
    var state = PhotoLibraryChanges.State(); state.receiverID = receiver
    state.pending = [.init(id: "completed-before-reply", createdAtMS: 900),
      .init(id: "still-pending", createdAtMS: 100)]
    try JSONEncoder().encode(state).write(to: root.appendingPathComponent("photo-library-changes.json"), options: .atomic)
    let ledger = try PhotoLibraryChanges(root: root)
    do {
      try await ledger.handoffPending { command in
        _ = try await Bridge.call(command)
        _ = try await Bridge.call(["op": "source_result", "receiver_id": receiver,
          "source": "completed-before-reply", "complete": true])
        throw Bridge.Failure(code: "network")
      }
      XCTFail("Expected lost acknowledgement")
    } catch { XCTAssertEqual((error as? Bridge.Failure)?.code, "network") }
    let restored = try PhotoLibraryChanges(root: root)
    try await restored.handoffPending()
    let data = try await Bridge.call(["op": "pending_sources", "receiver_id": receiver])
    let pending = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(pending["count"] as? Int, 1)
    XCTAssertEqual(pending["sources"] as? [String], ["still-pending"])
    XCTAssertTrue(restored.state.pending.isEmpty)
    _ = try await Bridge.call(["op": "source_result", "receiver_id": receiver,
      "source": "still-pending", "complete": true])
  }

  func testLegacyPendingDeadlinesHandOffOnceAndLostCoreReplyKeepsStableIdentity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var state = PhotoLibraryChanges.State()
    state.receiverID = "saved-receiver"
    state.enabled = true
    let deadline = Date().addingTimeInterval(300)
    state.pending = [.init(id: "new", nextAttempt: deadline, createdAtMS: 900),
      .init(id: "old", createdAtMS: 100)]
    try JSONEncoder().encode(state).write(to: root.appendingPathComponent("photo-library-changes.json"), options: .atomic)
    let ledger = try PhotoLibraryChanges(root: root)
    var accepted = Set<String>()
    var captured: [[String: Any]] = []
    do {
      try await ledger.handoffPending { command in
        XCTAssertEqual(command["receiver_id"] as? String, "saved-receiver")
        captured = try XCTUnwrap(command["sources"] as? [[String: Any]])
        for source in captured { accepted.insert(try XCTUnwrap(source["handoff_id"] as? String)) }
        throw Bridge.Failure(code: "network") // Core accepted; its reply was lost.
      }
      XCTFail("Expected lost reply")
    } catch { XCTAssertEqual((error as? Bridge.Failure)?.code, "network") }
    XCTAssertEqual(ledger.state.pending.count, 2)
    let restored = try PhotoLibraryChanges(root: root)
    let stable = Set(restored.state.pending.compactMap(\.handoffID))
    XCTAssertEqual(stable, accepted)
    XCTAssertEqual(captured.first?["retry_at"] as? Int64, Int64(deadline.timeIntervalSince1970))
    try await restored.handoffPending { command in
      let replay = try XCTUnwrap(command["sources"] as? [[String: Any]])
      XCTAssertEqual(Set(replay.compactMap { $0["handoff_id"] as? String }), stable)
      for source in replay { accepted.insert(try XCTUnwrap(source["handoff_id"] as? String)) }
      return Data("{}".utf8)
    }
    XCTAssertEqual(accepted.count, 2)
    XCTAssertTrue(restored.state.pending.isEmpty)
    let reopened = try PhotoLibraryChanges(root: root)
    XCTAssertTrue(reopened.state.pending.isEmpty)
    XCTAssertEqual(reopened.state.receiverID, "saved-receiver")
    XCTAssertTrue(reopened.state.enabled)
  }
}


@MainActor final class DiscoveryReceiverBoundaryTests: XCTestCase {
  func testSwitchClosesOldIntervalAndQueuesItsAdditionsToTheOldReceiver() async throws {
    await BackupModel.shared.open()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let old = "old-window-" + UUID().uuidString, new = "new-window-" + UUID().uuidString
    var initial = PhotoLibraryChanges.State(); initial.receiverID = old; initial.enabled = true
    initial.token = Data("start".utf8)
    try JSONEncoder().encode(initial).write(to: root.appendingPathComponent("photo-library-changes.json"), options: .atomic)
    let ledger = try PhotoLibraryChanges(root: root, captureToken: { Data("ending".utf8) }, readChanges: { saved, cutoff in
      XCTAssertEqual(saved, Data("start".utf8)); XCTAssertEqual(cutoff, Data("ending".utf8))
      return (cutoff, ["added-before-switch"], [])
    })
    try await ledger.matchReceiver(new)
    XCTAssertFalse(ledger.state.enabled); XCTAssertEqual(ledger.state.receiverID, new)
    let data = try await Bridge.call(["op": "pending_sources", "receiver_id": old])
    let pending = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(pending["count"] as? Int, 1)
    XCTAssertEqual(pending["sources"] as? [String], ["added-before-switch"])
    try await ledger.matchReceiver(old)
    XCTAssertFalse(ledger.state.enabled)
    XCTAssertNil(ledger.state.closingToken)
    XCTAssertEqual(ledger.state.token, Data("ending".utf8))
    _ = try await Bridge.call(["op": "source_result", "receiver_id": old, "source": "added-before-switch", "complete": true])
  }
  func testUnresolvableClosedBoundaryIsArchivedAndRestoredWithoutEnablingNewBackup() async throws {
    await BackupModel.shared.open()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let old = "unresolved-" + UUID().uuidString, new = "replacement-" + UUID().uuidString
    var initial = PhotoLibraryChanges.State(); initial.receiverID = old; initial.enabled = true
    initial.token = Data("saved-start".utf8)
    try JSONEncoder().encode(initial).write(to: root.appendingPathComponent("photo-library-changes.json"), options: .atomic)
    let ledger = try PhotoLibraryChanges(root: root, captureToken: { Data("saved-ending".utf8) }, readChanges: { _,_ in throw Bridge.Failure(code: "history_unavailable") })
    try await ledger.matchReceiver(new)
    XCTAssertFalse(ledger.state.enabled); XCTAssertEqual(ledger.state.receiverID, new)
    try await ledger.matchReceiver(old)
    XCTAssertFalse(ledger.state.enabled); XCTAssertTrue(ledger.state.historyUnavailable)
    XCTAssertEqual(ledger.state.token, Data("saved-start".utf8))
    XCTAssertEqual(ledger.state.closingToken, Data("saved-ending".utf8))
    XCTAssertTrue(ledger.state.pending.isEmpty)
  }
}

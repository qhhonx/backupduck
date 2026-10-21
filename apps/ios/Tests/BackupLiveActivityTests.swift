import XCTest
import ActivityKit
import UIKit
@testable import BackupDuck

final class BackupLiveActivityTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1000)
  private var attributes: BackupActivityAttributes {
    .init(receiver: "pixel:a&b", receiverName: "Test Pixel", session: "batch-a", baselinePublished: 100, initialRemaining: 10)
  }
  private func state(total: Int = 110, published: Int = 100, received: Int = 100,
    active: Int = 10, history: HistoricalImportStatus? = nil, paused: Bool = false,
    status: BackupHubStatus = .backingUp(remaining: 10, bytes: 0), failed: Bool = false) -> BackupActivityAttributes.ContentState {
    var summary = SenderSummary()
    summary.total = total; summary.published = published; summary.received = received; summary.active = active
    summary.queued = max(0, total - received)
    return BackupActivityProjection.state(summary: summary, history: history, paused: paused,
      status: status, attributes: attributes, now: now, actionFailed: failed)
  }
  func testBatchProgressExcludesEarlierSavedPhotosAndIncludesNewWork() {
    XCTAssertEqual(state().remaining, 10)
    XCTAssertEqual(state().progress, 0)
    XCTAssertEqual(state(total: 115, published: 105).total, 15)
    XCTAssertEqual(state(total: 115, published: 105).progress!, 1.0 / 3.0, accuracy: 0.001)
    let done = state(published: 110, received: 110, active: 0)
    XCTAssertEqual(done.phase, .saved); XCTAssertEqual(done.remaining, 0); XCTAssertEqual(done.progress, 1)
  }
  func testReceiptAndScanningDoNotClaimSavedCompletion() {
    let saving = state(received: 110)
    XCTAssertEqual(saving.phase, .saving); XCTAssertEqual(saving.progress, 0)
    let history = HistoricalImportStatus(run: 2, state: "scanning", checked: 20, pending: 10)
    XCTAssertEqual(state(history: history).phase, .finding)
    XCTAssertNil(state(history: history).progress)
    XCTAssertNil(state(published: 99).progress, "Regressed publication cannot manufacture completed progress")
    let removed = state(total: 100, published: 100, received: 100, active: 0)
    XCTAssertEqual(removed.phase, .attention, "Removed work is not confirmed publication")
    XCTAssertNil(removed.progress)
  }
  func testPausedWaitingAttentionAndActionFailureRemainDistinct() {
    XCTAssertEqual(state(paused: true, status: .problem(.receiverUnreachable)).phase, .paused)
    XCTAssertEqual(state(status: .problem(.receiverUnreachable)).phase, .waiting)
    XCTAssertEqual(state(status: .problem(.photosNeedYou(10))).phase, .attention)
    XCTAssertEqual(state(failed: true).phase, .attention)
    XCTAssertTrue(state(failed: true).actionFailed)
  }
  func testDismissalRestartAndPermissionDoNotRecreateOldWork() {
    XCTAssertTrue(BackupActivityProjection.shouldStart(active: 10, foreground: true, enabled: true, alreadyStarted: false))
    XCTAssertFalse(BackupActivityProjection.shouldStart(active: 10, foreground: false, enabled: true, alreadyStarted: false))
    XCTAssertFalse(BackupActivityProjection.shouldStart(active: 10, foreground: true, enabled: false, alreadyStarted: false))
    XCTAssertFalse(BackupActivityProjection.shouldStart(active: 10, foreground: true, enabled: true, paused: true, alreadyStarted: false))
    XCTAssertFalse(BackupActivityProjection.shouldStart(active: 10, foreground: true, enabled: true, alreadyStarted: true))
    XCTAssertFalse(BackupActivityProjection.shouldStart(active: 0, foreground: true, enabled: true, alreadyStarted: false))
  }
  func testActionBelongsToCurrentReceiverAndSession() {
    let activities = [("pixel-a", "batch-a")]
    XCTAssertTrue(BackupActivityProjection.permitsAction(receiver: "pixel-a", session: "batch-a", currentReceiver: "pixel-a", activities: activities))
    XCTAssertFalse(BackupActivityProjection.permitsAction(receiver: "pixel-a", session: "batch-a", currentReceiver: "pixel-b", activities: activities))
    XCTAssertFalse(BackupActivityProjection.permitsAction(receiver: "pixel-a", session: "old", currentReceiver: "pixel-a", activities: activities))
    XCTAssertFalse(BackupActivityProjection.permitsAction(receiver: "pixel-a", session: "batch-a", currentReceiver: "pixel-a", activities: []))
  }
  func testContentRoundTripAndReceiverLinkRetainTheirIdentity() throws {
    let original = state()
    XCTAssertEqual(try JSONDecoder().decode(BackupActivityAttributes.ContentState.self, from: JSONEncoder().encode(original)), original)
    let query = URLComponents(url: attributes.url, resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(query?.first?.value, attributes.receiver)
    var fresh = original; fresh.observedAt = now.addingTimeInterval(5)
    XCTAssertTrue(fresh.sameFacts(as: original))
    fresh.actionFailed = true
    XCTAssertFalse(fresh.sameFacts(as: original))
  }
}


extension BackupLiveActivityTests {
  /// The CI script creates a disposable simulator. This never runs against an
  /// installed physical client or reads the user's photos/credentials.
  @MainActor func testSystemActivityLifecycleOnIsolatedSimulator() async throws {
    #if targetEnvironment(simulator)
    guard ProcessInfo.processInfo.environment["BACKUPDUCK_ACTIVITY_SYSTEM_TESTS"] == "1" else {
      throw XCTSkip("Opt in only on a disposable simulator with synthetic data")
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw XCTSkip("System Live Activities are unavailable on this simulator")
    }
    guard UIApplication.shared.applicationState == .active else {
      throw XCTSkip("Activity creation requires the host foreground execution state")
    }
    let suite = "activity-tests-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = BackupLiveActivity(defaults: defaults)
    let model = BackupModel(root: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
    model.ready = true; model.queueRevision = 0; model.paused = false
    model.pairing = Pairing(version: 2, receiverID: "activity-synthetic", endpoint: "https://192.0.2.1", certificate: "synthetic", token: "synthetic")
    model.summary.total = 10; model.summary.active = 10; model.summary.queued = 10
    await controller.synchronize(model)
    let activities = Activity<BackupActivityAttributes>.activities.filter { $0.attributes.receiver == "activity-synthetic" }
    XCTAssertNil(controller.requestFailure)
    XCTAssertEqual(activities.count, 1)
    let activity = try XCTUnwrap(activities.first)
    model.paused = true
    await controller.synchronize(model)
    let paused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      activity.content.state.phase == .paused
    }, object: nil)
    await fulfillment(of: [paused], timeout: 5)
    XCTAssertEqual(activity.content.state.phase, .paused)
    XCTAssertEqual(Activity<BackupActivityAttributes>.activities.filter { $0.attributes.receiver == "activity-synthetic" }.count, 1)
    model.paused = false; model.summary.active = 0; model.summary.queued = 0
    model.summary.received = 10; model.summary.published = 10
    await controller.synchronize(model)
    XCTAssertNil(defaults.string(forKey: "liveActivity.receiver"))
    let ended = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      activity.activityState == .ended || activity.activityState == .dismissed
    }, object: nil)
    await fulfillment(of: [ended], timeout: 5)
    XCTAssertTrue(activity.activityState == .ended || activity.activityState == .dismissed)
    #else
    throw XCTSkip("Synthetic lifecycle acceptance runs only on a disposable simulator")
    #endif
  }
}

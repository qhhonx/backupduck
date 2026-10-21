import ActivityKit
import Combine
import UIKit

/// A presentation batch, not a queue: membership, retries and durable intent
/// stay in Rust. The baseline excludes photos saved before this surface began.
enum BackupActivityProjection {
  static func state(summary: SenderSummary, history: HistoricalImportStatus?, paused: Bool,
    status: BackupHubStatus, attributes: BackupActivityAttributes, now: Date,
    actionFailed: Bool = false) -> BackupActivityAttributes.ContentState {
    let remaining = max(0, summary.total - summary.published)
    let total = max(attributes.initialRemaining, summary.total - attributes.baselinePublished, remaining)
    let phase: BackupActivityAttributes.Phase
    if paused { phase = .paused }
    else if status.isProblem || actionFailed { phase = .attention }
    else if history?.state == "scanning" { phase = .finding }
    else if (summary.preparation_waiting ?? 0) > 0 { phase = .preparing }
    else if summary.queued + summary.running + summary.waiting + summary.paused > 0 { phase = .sending }
    else if summary.count(for: "active") > 0 { phase = .saving }
    else if remaining > 0 { phase = .attention }
    else if summary.published >= attributes.baselinePublished + attributes.initialRemaining { phase = .saved }
    else { phase = .attention }
    let resolvedPhase: BackupActivityAttributes.Phase = status == .problem(.receiverUnreachable) && !paused ? .waiting : phase
    return .init(remaining: remaining, total: total, phase: resolvedPhase,
      determinate: history?.state != "scanning" && summary.published >= attributes.baselinePublished
        && summary.total >= attributes.baselinePublished + attributes.initialRemaining,
      observedAt: now, actionFailed: actionFailed)
  }
  static func permitsAction(receiver: String, session: String, currentReceiver: String?,
    activities: [(String, String)]) -> Bool {
    receiver == currentReceiver && activities.contains { $0.0 == receiver && $0.1 == session }
  }
  static func shouldStart(active: Int, foreground: Bool, enabled: Bool, paused: Bool = false, alreadyStarted: Bool) -> Bool {
    active > 0 && foreground && enabled && !paused && !alreadyStarted
  }
}

@MainActor final class BackupLiveActivity {
  static let shared = BackupLiveActivity()
  private var watching: AnyCancellable?
  private var updating = false
  private var needsUpdate = false
  private var lastRequest = Date.distantPast
  private let defaults: UserDefaults
  private(set) var requestFailure: Error?
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  private let markerKey = "liveActivity.receiver"

  private var permitsSystemPresentation: Bool {
    // Unit-test hosts must not end or replace the explicit synthetic system
    // fixtures. The lifecycle tests supply their own isolated defaults suite.
    !(defaults === UserDefaults.standard &&
      (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil))
  }
  func start(_ model: BackupModel) {
    guard permitsSystemPresentation, BackupEnvironment.usesPhotoLibrary, watching == nil else { return }
    watching = model.objectWillChange
      .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
      .sink { [weak self, weak model] _ in
        Task { @MainActor in if let model { await self?.synchronize(model) } }
      }
    Task { await synchronize(model) }
  }

  func synchronize(_ model: BackupModel) async {
    guard permitsSystemPresentation, BackupEnvironment.usesPhotoLibrary else { return }
    needsUpdate = true
    guard !updating else { return }
    updating = true
    defer { updating = false }
    repeat {
      needsUpdate = false
      await updateCurrent(model)
    } while needsUpdate
  }

  private func updateCurrent(_ model: BackupModel) async {
    guard model.ready else { return }
    let receiver = model.pairing?.receiverID
    for activity in Activity<BackupActivityAttributes>.activities where activity.attributes.receiver != receiver {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    guard let receiver else { defaults.removeObject(forKey: markerKey); return }
    guard model.queueRevision >= 0 else { return }
    let existing = Activity<BackupActivityAttributes>.activities.filter {
      $0.attributes.receiver == receiver && ($0.activityState == .active || $0.activityState == .stale)
    }
    let now = Date()
    let active = model.summary.count(for: "active")
    for activity in existing {
      let next = BackupActivityProjection.state(summary: model.summary, history: model.historicalImport,
        paused: model.paused, status: model.hubStatus, attributes: activity.attributes, now: now,
        actionFailed: model.pauseError != nil)
      let content = ActivityContent(state: next, staleDate: now.addingTimeInterval(90))
      if active == 0 && model.historicalImport?.state != "scanning" {
        await activity.end(content, dismissalPolicy: next.remaining == 0 ? .immediate : .after(now.addingTimeInterval(60)))
      } else if !next.sameFacts(as: activity.content.state)
        || now.timeIntervalSince(activity.content.state.observedAt) >= 30 {
        await activity.update(content)
      }
      guard model.pairing?.receiverID == receiver else { needsUpdate = true; return }
    }
    if active == 0 && model.historicalImport?.state != "scanning" {
      defaults.removeObject(forKey: markerKey)
      return
    }
    if !existing.isEmpty { defaults.set(receiver, forKey: markerKey); return }
    // A persisted marker with no activity also represents user dismissal.
    // Do not recreate it until this work has drained.
    guard BackupActivityProjection.shouldStart(active: active,
      foreground: UIApplication.shared.applicationState == .active,
      enabled: ActivityAuthorizationInfo().areActivitiesEnabled, paused: model.paused,
      alreadyStarted: defaults.string(forKey: markerKey) == receiver),
      now.timeIntervalSince(lastRequest) >= 30 else { return }
    lastRequest = now
    requestFailure = nil
    let attributes = BackupActivityAttributes(receiver: receiver, receiverName: model.peerDevice?.name ?? "Pixel",
      session: UUID().uuidString, baselinePublished: model.summary.published,
      initialRemaining: max(0, model.summary.total - model.summary.published))
    let state = BackupActivityProjection.state(summary: model.summary, history: model.historicalImport,
      paused: model.paused, status: model.hubStatus, attributes: attributes, now: now)
    do {
      _ = try Activity.request(attributes: attributes,
        content: ActivityContent(state: state, staleDate: now.addingTimeInterval(90)), pushType: nil)
      defaults.set(receiver, forKey: markerKey)
    } catch {
      requestFailure = error
      // Optional OS presentation can be unavailable; backup and its task UI
      // continue. A later foreground observation may retry at a bounded rate.
    }
  }
}

import ActivityKit
import AppIntents
import Foundation

/// LiveActivityIntent executes in the app process, so the extension never
/// opens the sender database or creates another queue/credential store.
struct SetBackupPauseIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "activity_pause_intent"
  static var isDiscoverable = false
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  @Parameter(title: "activity_receiver_parameter") var receiver: String
  @Parameter(title: "activity_session_parameter") var session: String
  @Parameter(title: "activity_paused_parameter") var paused: Bool
  init() {}
  init(receiver: String, session: String, paused: Bool) {
    self.receiver = receiver; self.session = session; self.paused = paused
  }
  @MainActor func perform() async throws -> some IntentResult {
    #if BACKUPDUCK_WIDGET
    // The system routes this intent to the host. Never report a successful
    // pause if it unexpectedly reaches a process that cannot persist it.
    try Self.requireHost()
    #else
    let model = BackupModel.shared
    await model.open()
    guard BackupEnvironment.usesPhotoLibrary,
      BackupActivityProjection.permitsAction(receiver: receiver, session: session,
        currentReceiver: model.pairing?.receiverID,
        activities: Activity<BackupActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }.map { ($0.attributes.receiver, $0.attributes.session) }) else {
      return .result()
    }
    _ = await model.setPaused(paused, discoverAfterResume: false)
    await model.refresh()
    await BackupLiveActivity.shared.synchronize(model)
    #endif
    return .result()
  }
  #if BACKUPDUCK_WIDGET
  private static func requireHost() throws { throw BackupActivityActionError.unavailable }
  #endif
}
private enum BackupActivityActionError: LocalizedError {
  case unavailable
  var errorDescription: String? { NSLocalizedString("activity_action_failed", comment: "") }
}

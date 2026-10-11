import Foundation

// A durable intent is normal while executing. Only an idle, unfinished intent
// needs recovery. Persistence bookkeeping must not flash a warning in the UI.
enum FolderControlPresentation: Equatable {
  case idle, running, needsRecovery
  init(pending: FolderPendingControl?, executing: Bool) {
    self = pending == nil ? .idle : executing ? .running : .needsRecovery
  }
}

enum FolderSourcePresentation {
  static func status(source: FolderSource, phase: String?, action: String?,
    executing: Bool, paused: Bool, paired: Bool, now: Date = Date()) -> String {
    switch FolderControlPresentation(pending: source.pendingControl, executing: executing) {
    case .running: return "folder_starting"
    case .needsRecovery: return "mac_folder_operation_incomplete"
    case .idle: break
    }
    if let phase, ["folder_scanning", "folder_scan_failed", "folder_offline"].contains(phase) { return phase }
    if action == "folder_check_requested" { return "folder_check_requested" }
    if action == "folder_check_finished", let checked = source.lastCheck,
      now.timeIntervalSince(checked) < 15 { return "folder_check_finished" }
    if source.enabled || !(source.retryPaths ?? []).isEmpty {
      if paused { return source.automaticActive ? "folder_auto_enabled" : source.manualActive ? "folder_manual_queued" : "folder_retry_waiting" }
      if !paired { return "folder_pair_first" }
      if let phase, !["folder_up_to_date", "folder_paused", "folder_manual_idle"].contains(phase) { return phase }
      return source.automaticActive ? "folder_auto_active" : "folder_manual_active"
    }
    return "folder_manual_idle"
  }
}

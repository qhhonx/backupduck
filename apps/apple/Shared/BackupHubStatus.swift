import Foundation

/// What the backup hub says at the top (design/flows.md § Every day and § When
/// something goes wrong). One state, said once; a problem outranks progress.
enum BackupHubStatus: Equatable {
  enum Problem: Equatable {
    case receiverRejected
    case receiverUnreachable
    case receiverFull
    case phoneFull
    case photoAccessDenied
    case conversionNeeded(Int)
  }
  case notPaired
  case opening
  case problem(Problem)
  case paused
  case backingUp(remaining: Int, bytes: UInt64)
  /// Everything reached the Pixel; `saving` photos are still going into its Photos.
  case caughtUp(lastSaved: Date?, saving: Int)
  case empty

  struct Inputs {
    var paired: Bool
    var ready: Bool
    var paused: Bool
    var connection: ReceiverConnection
    var receiverUnavailable: Bool
    var summary: SenderSummary
    var phoneSpaceShort: Bool
    var photoAccess: PhotoAccess
    var jobs: [BackupJob]
  }

  static func derive(_ input: Inputs) -> BackupHubStatus {
    guard input.paired else { return .notPaired }
    guard input.ready else { return .opening }
    // Pausing is the user's choice: while paused nothing is checked, so a stale
    // connection reading must not read as a problem.
    if input.paused { return .paused }
    if input.connection == .authentication || input.summary.waiting_reason == "authentication" { return .problem(.receiverRejected) }
    if input.receiverUnavailable || input.connection == .network || input.connection == .unavailable
      || input.summary.waiting_reason == "network" { return .problem(.receiverUnreachable) }
    if ["capacity", "low_space"].contains(input.summary.waiting_reason ?? "") { return .problem(.receiverFull) }
    if input.phoneSpaceShort { return .problem(.phoneFull) }
    if input.photoAccess == .denied { return .problem(.photoAccessDenied) }
    let conversions = input.jobs.filter { $0.processingError == "conversion_required" }.count
    if conversions > 0 { return .problem(.conversionNeeded(conversions)) }
    let remaining = input.summary.queued + input.summary.running + input.summary.waiting
    if remaining > 0 {
      let bytes = input.jobs.filter { ["queued", "running", "waiting"].contains($0.state) }
        .reduce(UInt64(0)) { $0 + ($1.totalBytes > $1.confirmedBytes ? $1.totalBytes - $1.confirmedBytes : 0) }
      return .backingUp(remaining: remaining, bytes: bytes)
    }
    if input.summary.published > 0 {
      let last = input.jobs.compactMap { $0.state == "received" ? $0.stateChangedAt : nil }.max()
      let saving = max(0, input.summary.received - input.summary.published - input.summary.publication_failed)
      return .caughtUp(lastSaved: last.map { Date(timeIntervalSince1970: Double($0) / 1000) }, saving: saving)
    }
    return .empty
  }
}

extension BackupHubStatus {
  var isProblem: Bool { if case .problem = self { return true } else { return false } }
}

extension BackupModel {
  @MainActor var hubStatus: BackupHubStatus {
    BackupHubStatus.derive(.init(
      paired: pairing != nil, ready: ready, paused: paused, connection: receiverConnection,
      receiverUnavailable: receiverUnavailable, summary: summary,
      phoneSpaceShort: storage?.reason == "local_free_space",
      photoAccess: BackupEnvironment.photoAccess(), jobs: jobs))
  }
}

extension BackupHubStatus {
  /// The hub's one-line answer, for surfaces that show only a line (the Mac
  /// menu bar, notifications). Same words as the hub card (P3).
  func sentence(receiver: String, remainingBytes: UInt64 = 0) -> String {
    func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    switch self {
    case .notPaired: return text("hub_not_paired")
    case .opening: return text("hub_opening")
    case .empty: return text("hub_empty")
    case .paused: return text("hub_paused")
    case .caughtUp(_, let saving): return text(saving > 0 ? "hub_caught_up_saving" : "hub_caught_up")
    case .backingUp(let remaining, _):
      return String(format: text("hub_backing_up_count"), remaining.formatted())
    case .problem(let problem):
      switch problem {
      case .receiverRejected: return text("hub_problem_rejected")
      case .receiverUnreachable: return String(format: text("hub_problem_offline"), receiver)
      case .receiverFull: return text("hub_problem_receiver_full")
      #if os(macOS)
      case .phoneFull: return text("hub_problem_mac_full")
      #else
      case .phoneFull: return text("hub_problem_phone_full")
      #endif
      case .photoAccessDenied: return text("hub_problem_photos")
      case .conversionNeeded(let count): return String(format: text("hub_problem_convert"), count.formatted())
      }
    }
  }
}

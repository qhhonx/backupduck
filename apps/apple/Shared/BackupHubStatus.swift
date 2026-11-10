import Foundation
import SwiftUI

/// What the backup hub says at the top (design/flows.md § Every day and § When
/// something goes wrong). One state, said once; a problem outranks progress.
enum BackupHubStatus: Equatable {
  enum Problem: Equatable {
    case receiverRejected
    case receiverUnreachable
    case localNetworkBlocked
    case receiverFull
    case phoneFull
    case photoAccessDenied
    case conversionNeeded(Int)
    case photosNeedYou(Int)
  }
  case notPaired
  case opening
  case problem(Problem)
  case paused
  /// `bytes` is nil when any pending work is absent or its original size is unknown.
  case backingUp(remaining: Int, bytes: UInt64?)
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
    var photoLibraryInScope: Bool
    var jobs: [BackupJob]
  }

  static func derive(_ input: Inputs) -> BackupHubStatus {
    guard input.paired else { return .notPaired }
    guard input.ready else { return .opening }
    // Pausing is the user's choice: while paused nothing is checked, so a stale
    // connection reading must not read as a problem.
    if input.paused { return .paused }
    if input.connection == .authentication || input.summary.waiting_reason == "authentication" { return .problem(.receiverRejected) }
    if input.connection == .localNetworkDenied { return .problem(.localNetworkBlocked) }
    if input.receiverUnavailable || input.connection == .network || input.connection == .unavailable { return .problem(.receiverUnreachable) }
    if ["capacity", "low_space"].contains(input.summary.waiting_reason ?? "") { return .problem(.receiverFull) }
    if input.phoneSpaceShort { return .problem(.phoneFull) }
    if input.photoLibraryInScope && input.photoAccess == .denied { return .problem(.photoAccessDenied) }
    let conversions = input.summary.conversion_required
      ?? input.jobs.filter { $0.processingError == "conversion_required" }.count
    if conversions > 0 { return .problem(.conversionNeeded(conversions)) }
    let attention = input.summary.attention
      ?? (input.summary.failed + input.summary.publication_failed + (input.summary.preparation_failed ?? 0))
    if attention > 0 { return .problem(.photosNeedYou(attention)) }
    let remaining = input.summary.queued + input.summary.running + input.summary.waiting
      + input.summary.paused + (input.summary.preparation_waiting ?? 0)
    if remaining > 0 {
      return .backingUp(remaining: remaining, bytes: remainingBytes(input))
    }
    if input.summary.received > 0 || input.summary.published > 0 {
      let saving = max(0, input.summary.received - input.summary.published - input.summary.publication_failed)
      // Job change times are receipt/activity times, not gallery save times.
      return .caughtUp(lastSaved: nil, saving: saving)
    }
    return .empty
  }

  private static func remainingBytes(_ input: Inputs) -> UInt64? {
    // The task feed is paged, while the summary covers the whole receiver queue.
    // Never label a loaded prefix as the size of every pending photo.
    guard input.summary.preparation_waiting == 0 else { return nil }
    let states = ["queued", "running", "waiting", "paused"]
    let pending = input.jobs.filter { states.contains($0.state) }
    guard Set(pending.map(\.id)).count == pending.count,
      states.allSatisfy({ state in pending.filter { $0.state == state }.count == input.summary.count(for: state) })
    else { return nil }
    var bytes: UInt64 = 0
    for job in pending {
      guard !job.asset.resources.isEmpty else { return nil }
      var total: UInt64 = 0
      for resource in job.asset.resources {
        guard resource.size > 0 else { return nil }
        let (next, overflow) = total.addingReportingOverflow(resource.size)
        guard !overflow else { return nil }
        total = next
      }
      let (next, overflow) = bytes.addingReportingOverflow(total > job.confirmedBytes ? total - job.confirmedBytes : 0)
      guard !overflow else { return nil }
      bytes = next
    }
    return bytes
  }
}

extension BackupHubStatus {
  var isProblem: Bool { if case .problem = self { return true } else { return false } }
}

extension BackupModel {
  @MainActor var earlierPhotosStarted: Bool { historicalImport?.hasStarted == true }
  @MainActor var photoLibraryInScope: Bool {
    deferredPhotoAccess || autoBackup || (earlierPhotosStarted && historicalImport?.isSaved != true)
      || pendingImports > 0 || jobs.contains {
        ($0.receiverID == nil || $0.receiverID == pairing?.receiverID)
          && $0.asset.metadata?["source_type"] != "folder"
          && ["queued", "running", "waiting", "paused"].contains($0.state)
      }
  }
  @MainActor var showsEarlierPhotosNotStarted: Bool {
    let access = photoAccess
    return pairing != nil && ready && receiverConnection == .ready && !earlierPhotosStarted
      && (access == .full || access == .limited)
  }
  @MainActor var earlierPhotosCardStatus: HistoricalImportStatus {
    historicalImport ?? HistoricalImportStatus(run: 0, state: "idle", checked: 0, pending: 0)
  }
  @MainActor var hubStatus: BackupHubStatus {
    BackupHubStatus.derive(.init(
      paired: pairing != nil, ready: ready, paused: paused, connection: receiverConnection,
      receiverUnavailable: receiverUnavailable, summary: summary,
      phoneSpaceShort: storage?.reason == "local_free_space",
      photoAccess: photoAccess, photoLibraryInScope: photoLibraryInScope,
      jobs: jobs.filter { $0.receiverID == nil || $0.receiverID == pairing?.receiverID }))
  }
}

extension BackupHubStatus {
  /// Claims only what is in scope: all photos after an earlier-photo run,
  /// new photos while Auto Backup is on, otherwise what was chosen.
  static func caughtUpTitle(saving: Int, earlierPhotosStarted: Bool, autoBackup: Bool = true) -> String {
    saving > 0 ? "hub_caught_up_saving" : earlierPhotosStarted ? "hub_caught_up"
      : autoBackup ? "hub_caught_up_new" : "hub_caught_up_chosen"
  }
  /// The hub's one-line answer, for surfaces that show only a line (the Mac
  /// menu bar, notifications). Same words as the hub card (P3).
  func sentence(receiver: String, earlierPhotosStarted: Bool = true, autoBackup: Bool = true) -> String {
    func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    switch self {
    case .notPaired: return text("hub_not_paired")
    case .opening: return text("hub_opening")
    case .empty: return text("hub_empty")
    case .paused: return text("hub_paused")
    case .caughtUp(_, let saving): return text(Self.caughtUpTitle(saving: saving, earlierPhotosStarted: earlierPhotosStarted, autoBackup: autoBackup))
    case .backingUp(let remaining, let bytes):
      if let bytes, bytes > 0 {
        return String(format: text("hub_backing_up"), remaining.formatted(),
          ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file))
      }
      return String(format: text("hub_backing_up_count"), remaining.formatted())
    case .problem(let problem):
      switch problem {
      case .receiverRejected: return text("hub_problem_rejected")
      case .receiverUnreachable: return String(format: text("hub_problem_offline"), receiver)
      case .localNetworkBlocked: return text("hub_problem_local_network")
      case .receiverFull: return text("hub_problem_receiver_full")
      #if os(macOS)
      case .phoneFull: return text("hub_problem_mac_full")
      #else
      case .phoneFull: return text("hub_problem_phone_full")
      #endif
      case .photoAccessDenied: return text("hub_problem_photos")
      case .conversionNeeded(let count): return String(format: text("hub_problem_convert"), count.formatted())
      case .photosNeedYou(let count): return String(format: text("hub_problem_photos_need_you"), count.formatted())
      }
    }
  }
}

/// Identity chrome never projects backup results.
extension ReceiverConnection {
  var identityTone: Color {
    switch self {
    case .ready: DuckRole.saved
    case .unknown: DuckRole.secondaryText
    case .network, .localNetworkDenied, .authentication, .unavailable: DuckRole.attentionGlyph
    }
  }
  var identityLabel: String {
    switch self {
    case .ready: NSLocalizedString("device_connected_now", comment: "")
    case .unknown: NSLocalizedString("device_connection_unknown", comment: "")
    case .network, .localNetworkDenied, .authentication, .unavailable: NSLocalizedString("device_unreachable", comment: "")
    }
  }
}

extension BackupHubStatus {
  /// Only an attention card replaces the matching attention summary. An offline
  /// card must not hide other photos that still need the person.
  var showsAttentionDetails: Bool {
    switch self {
    case .problem(.conversionNeeded), .problem(.photosNeedYou): true
    default: false
    }
  }
}

/// Presentation-only progress includes originals that have not materialized yet.
struct HubBatchProgress {
  private(set) var batchPeak = 0
  mutating func observe(_ status: BackupHubStatus) {
    if case .backingUp(let remaining, _) = status { batchPeak = max(batchPeak, remaining) }
    else { batchPeak = 0 }
  }
  func fraction(remaining: Int, partial: Double) -> Double {
    guard batchPeak > 0 else { return 0 }
    return min(1, max(0, (Double(batchPeak - remaining) + partial) / Double(batchPeak)))
  }
}

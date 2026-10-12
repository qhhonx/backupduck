import Foundation
import Photos
import CryptoKit

/// PhotoKit-specific discovery state. The token and pending native identifiers
/// are atomically persisted together before any originals are exported to Rust.
@MainActor final class PhotoLibraryChanges: NSObject, PHPhotoLibraryChangeObserver {
  struct Pending: Codable {
    let id: String
    var nextAttempt: Date = .distantPast
    var createdAtMS: Int64? = nil
    var handoffID: String? = nil
  }
  struct State: Codable {
    var enabled = false
    var receiverID: String?
    var token: Data?
    var closingToken: Data? = nil
    var pending: [Pending] = []
    var historyUnavailable = false
  }
  private let file: URL
  private let captureToken: () throws -> Data
  private let readChanges: (Data, Data?) async throws -> (Data?, Set<String>, Set<String>)
  private(set) var state = State()
  private var scanning = false
  private var revision = 0
  init(root: URL,
    captureToken: @escaping () throws -> Data = {
      try NSKeyedArchiver.archivedData(withRootObject: PHPhotoLibrary.shared().currentChangeToken, requiringSecureCoding: true)
    },
    readChanges: @escaping (Data, Data?) async throws -> (Data?, Set<String>, Set<String>) = { saved, cutoff in
      try await Task.detached(priority: .utility) { try PhotoLibraryChanges.changes(since: saved, through: cutoff) }.value
    }) throws {
    self.captureToken = captureToken; self.readChanges = readChanges
    file = root.appendingPathComponent("photo-library-changes.json")
    super.init()
    if FileManager.default.fileExists(atPath: file.path) {
      state = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
    }
    PHPhotoLibrary.shared().register(self)
  }
  deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
  private func persist(_ next: State) throws {
    #if os(iOS)
      let options: Data.WritingOptions = [
        .atomic, .completeFileProtectionUntilFirstUserAuthentication,
      ]
    #else
      let options: Data.WritingOptions = [.atomic]
    #endif
    try JSONEncoder().encode(next).write(to: file, options: options)
    state = next
  }
  func setEnabled(_ enabled: Bool, receiverID: String?) async throws {
    var next = state
    if next.receiverID != receiverID {
      try await matchReceiver(receiverID)
      next = state
    }
    if next.enabled == enabled { return }
    if enabled {
      // Finish the interval that was enabled before resetting the baseline.
      if next.closingToken != nil { try await reconcileClosingWindow() }
      next = state
      // Start from now, including newly imported photos with old capture dates.
      next.token = try captureToken()
      next.historyUnavailable = false
    } else if next.token != nil {
      next.closingToken = try captureToken()
    }
    next.enabled = enabled
    try persist(next)
    revision += 1
  }
  private func archivedWindowFile(_ receiver: String) -> URL {
    let hash = SHA256.hash(data: Data(receiver.utf8)).map { String(format: "%02x", $0) }.joined()
    return file.deletingLastPathComponent().appendingPathComponent("closed-photo-window-\(hash).json")
  }
  func matchReceiver(_ receiverID: String?) async throws {
    guard state.receiverID != receiverID else { return }
    if let previous = state.receiverID {
      // Freeze the ending boundary before changing trust. Original reads and
      // network availability are irrelevant to this metadata-only operation.
      if state.enabled { try await setEnabled(false, receiverID: previous) }
      if state.closingToken != nil {
        do { try await reconcileClosingWindow() }
        catch {
          var unresolved = state; unresolved.historyUnavailable = true
          try persist(unresolved) // Retain original token/cutoff; never widen scope.
        }
      }
      try await handoffPending()
      try JSONEncoder().encode(state).write(to: archivedWindowFile(previous), options: .atomic)
    }
    var next = State(); next.receiverID = receiverID
    if let receiverID, FileManager.default.fileExists(atPath: archivedWindowFile(receiverID).path) {
      let preserved = try JSONDecoder().decode(State.self, from: Data(contentsOf: archivedWindowFile(receiverID)))
      guard preserved.receiverID == receiverID, !preserved.enabled else { throw Bridge.Failure(code: "conflict") }
      // Restore only the closed outstanding boundary; no automatic new window.
      next = preserved
    }
    try persist(next); revision += 1
  }

  nonisolated static func changes(since saved: Data, through ending: Data? = nil)
    throws -> (Data?, Set<String>, Set<String>)
  {
    guard let start = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: PHPersistentChangeToken.self, from: saved)
    else { throw Bridge.Failure(code: "history_unavailable") }
    let cutoff = try ending.flatMap {
      try NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: $0)
    }
    if ending != nil && cutoff == nil { throw Bridge.Failure(code: "history_unavailable") }
    if let cutoff, start == cutoff { return (ending, [], []) }
    var latest: PHPersistentChangeToken?
    var inserted = Set<String>()
    var deleted = Set<String>()
    for change in try PHPhotoLibrary.shared().fetchPersistentChanges(since: start) {
      let details = try change.changeDetails(for: .asset)
      inserted.formUnion(details.insertedLocalIdentifiers)
      inserted.subtract(details.deletedLocalIdentifiers)
      deleted.formUnion(details.deletedLocalIdentifiers)
      deleted.subtract(details.insertedLocalIdentifiers)
      latest = change.changeToken
      if let cutoff, latest == cutoff { break }
    }
    if let cutoff, latest != cutoff { throw Bridge.Failure(code: "history_unavailable") }
    return (try latest.map {
      try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
    }, inserted, deleted)
  }
  private func reconcileClosingWindow() async throws {
    guard let saved = state.token, let cutoff = state.closingToken else { return }
    let version = revision
    let changes = try await readChanges(saved, cutoff)
    guard version == revision, state.closingToken == cutoff else {
      throw Bridge.Failure(code: "conflict")
    }
    let included = await filteredDiscovery(changes.1)
    guard version == revision, state.closingToken == cutoff else { throw Bridge.Failure(code: "conflict") }
    var next = state
    next.pending.removeAll { changes.2.contains($0.id) }
    let known = Set(next.pending.map(\.id))
    next.pending.append(contentsOf: included.subtracting(known).map { Pending(id: $0) })
    next.token = cutoff
    next.closingToken = nil
    try persist(next)
  }
  private func filteredDiscovery(_ ids: Set<String>) async -> Set<String> {
    // Freeze policy for this discovery pass; already persisted handoffs retain
    // their original membership when the user changes settings.
    let scope = BackupScopeStore.shared.rule
    if ids.isEmpty || scope.types.isEmpty { return [] }
    if !scope.restrictAlbums && scope.types == Set(BackupMediaKind.allCases) { return ids }
    return await Task.detached(priority: .utility) { scope.selectedIDs(from: ids) }.value
  }
  nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
    Task { @MainActor in await BackupModel.shared.discoverPhotos() }
  }
  func discoverAndQueue(using model: BackupModel) async {
    guard (state.enabled || state.closingToken != nil || !state.pending.isEmpty),
      !scanning, !model.paused,
      model.pairing?.receiverID == state.receiverID
    else { return }
    let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard authorization == .authorized || authorization == .limited else {
      model.message = NSLocalizedString("photos_permission_needed", comment: "")
      return
    }
    scanning = true
    defer {
      scanning = false
      model.updateDiscoveryStatus()
    }
    let version = revision
    do {
      if state.closingToken != nil { try await reconcileClosingWindow() }
      guard version == revision else { return }
      if state.enabled, !state.historyUnavailable, let savedToken = state.token {
        do {
          // PhotoKit fetches can block; keep change-history work off the UI thread.
          let changes = try await readChanges(savedToken, nil)
          guard version == revision, !Task.isCancelled else { return }
          if let token = changes.0 {
            let included = await filteredDiscovery(changes.1)
            guard version == revision, state.token == savedToken, !Task.isCancelled else { return }
            var next = state
            next.pending.removeAll { changes.2.contains($0.id) }
            let known = Set(next.pending.map(\.id))
            next.pending.append(contentsOf: included.subtracting(known).map { Pending(id: $0) })
            next.token = token
            try persist(next)
          }
        } catch {
          guard version == revision else { return }
          var next = state
          next.historyUnavailable = true
          try persist(next)
          model.message = NSLocalizedString("error_history_unavailable", comment: "")
        }
      }
      // Core preparation owns ordering, eligibility and all original exports.
      // This ledger only hands off metadata persisted with the PhotoKit token.
      try await handoffPending()
      await model.refreshPendingImportCount()
    } catch { model.message = error.localizedDescription }
  }
  /// Stable receipts make lost replies safe even if core preparation finishes
  /// before the native token ledger can remove its acknowledged identifiers.
  func handoffPending(using send: ([String: Any]) async throws -> Data = Bridge.call) async throws {
    guard let receiver = state.receiverID, !state.pending.isEmpty else { return }
    var next = state
    var changed = false
    for index in next.pending.indices where next.pending[index].handoffID == nil {
      next.pending[index].handoffID = UUID().uuidString; changed = true
    }
    if changed { try persist(next) } // Stamp identities before any core call.
    let pending = state.pending
    for start in stride(from: 0, to: pending.count, by: 200) {
      let batch = Array(pending[start..<min(start + 200, pending.count)])
      let sources: [[String: Any]] = batch.map { item in
        var value: [String: Any] = ["handoff_id": item.handoffID!, "source": item.id,
          "retry_at": Int64(max(0, item.nextAttempt.timeIntervalSince1970))]
        if let date = item.createdAtMS { value["created_at_ms"] = max(0, date) }
        return value
      }
      _ = try await send(["op": "handoff_sources", "receiver_id": receiver, "sources": sources])
      guard state.receiverID == receiver else { return }
      let accepted = Set(batch.compactMap(\.handoffID))
      var remaining = state
      remaining.pending.removeAll { $0.handoffID.map(accepted.contains) ?? false }
      try persist(remaining)
    }
  }

}

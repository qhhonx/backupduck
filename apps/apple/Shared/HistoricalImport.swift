import Foundation
import Photos
import SwiftUI
import CryptoKit

struct HistoricalImportStatus: Decodable, Equatable {
  let run: Int64
  let state: String
  let checked: Int
  let pending: Int
  var snapshot_id: String? = nil
  var published: Int? = nil
  /// The core confirms publication for every frozen member, not just receipt.
  var isSaved: Bool { state == "scanned" && pending == 0 && published == checked }
}

/// Frozen membership for one historical scan. PhotoKit's fetch result is not
/// durable: enumerating it again after a restart would include newer photos.
@MainActor final class HistoricalScanCursor {
  private struct Membership: Codable {
    let receiver: String
    let ids: [String]
    var snapshotID: String? = nil
  }
  private struct Progress: Codable {
    var run: Int64?
    var offset: Int
  }
  let receiver: String
  let run: Int64
  let ids: [String]
  private let progressURL: URL
  var offset: Int

  private init(receiver: String, run: Int64, ids: [String], offset: Int, progressURL: URL) {
    self.receiver = receiver; self.run = run; self.ids = ids
    self.offset = offset; self.progressURL = progressURL
  }
  private static func paths(root: URL, receiver: String, snapshotID: String? = nil) -> (URL, URL, URL) {
    let digest = SHA256.hash(data: Data(receiver.utf8)).map { String(format: "%02x", $0) }.joined()
    let suffix = snapshotID.map { "-" + SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() } ?? ""
    let prefix = root.appendingPathComponent("historical-membership-\(digest)\(suffix)")
    return (prefix.appendingPathExtension("json"),
      root.appendingPathComponent("historical-progress-\(digest)\(suffix).json"),
      root.appendingPathComponent("historical-schema-\(digest)\(suffix).marker"))
  }
  private static func save<T: Encodable>(_ value: T, to url: URL) throws {
    #if os(iOS)
      let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    #else
      let options: Data.WritingOptions = [.atomic]
    #endif
    try JSONEncoder().encode(value).write(to: url, options: options)
  }
  /// Capture identifiers at the button press. Insertions during enumeration
  /// are removed using the persistent change token captured beforehand.
  @discardableResult static func capture(root: URL, receiver: String) async throws -> String {
    guard BackupEnvironment.usesPhotoLibrary else { throw Bridge.Failure(code: "source_unavailable") }
    let rule = BackupScopeStore.shared.rule
    let ids = try await Task.detached(priority: .utility) { () throws -> [String] in
      let token = try NSKeyedArchiver.archivedData(
        withRootObject: PHPhotoLibrary.shared().currentChangeToken, requiringSecureCoding: true)
      let options = photoLibraryFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
      let assets = PHAsset.fetchAssets(with: options)
      var result = [String]()
      result.reserveCapacity(assets.count)
      assets.enumerateObjects { asset, _, _ in result.append(asset.localIdentifier) }
      let included = rule.selectedIDs(from: Set(result))
      let inserted = try PhotoLibraryChanges.changes(since: token).1
      return result.filter { included.contains($0) && !inserted.contains($0) }
    }.value
    return try persistSnapshot(root: root, receiver: receiver, ids: ids)
  }
  /// Immutable adapter data; the shared core alone binds this identity to a run.
  static func persistSnapshot(root: URL, receiver: String, ids: [String]) throws -> String {
    let snapshotID = UUID().uuidString
    let paths = paths(root: root, receiver: receiver, snapshotID: snapshotID)
    try save(Membership(receiver: receiver, ids: ids, snapshotID: snapshotID), to: paths.0)
    try save(Progress(run: nil, offset: 0), to: paths.1)
    try save(true, to: paths.2)
    return snapshotID
  }
  static func load(root: URL, receiver: String, run: Int64, snapshotID: String? = nil) async throws -> HistoricalScanCursor {
    let paths = paths(root: root, receiver: receiver, snapshotID: snapshotID)
    let files = FileManager.default
    if !files.fileExists(atPath: paths.0.path) || !files.fileExists(atPath: paths.1.path) {
      // A missing frozen snapshot cannot be rebuilt from today's library.
      // The user must explicitly start a new scope; keep queued originals.
      throw Bridge.Failure(code: "history_snapshot_unavailable")
    }
    let membership = try JSONDecoder().decode(Membership.self, from: Data(contentsOf: paths.0))
    var progress = try JSONDecoder().decode(Progress.self, from: Data(contentsOf: paths.1))
    guard membership.receiver == receiver, membership.snapshotID == snapshotID, progress.run == nil || progress.run == run,
      (0...membership.ids.count).contains(progress.offset) else {
      throw Bridge.Failure(code: "history_snapshot_unavailable")
    }
    if progress.run == nil {
      progress.run = run
      try save(progress, to: paths.1)
    }
    if !files.fileExists(atPath: paths.2.path) { try save(true, to: paths.2) }
    return HistoricalScanCursor(receiver: receiver, run: run, ids: membership.ids,
      offset: progress.offset, progressURL: paths.1)
  }
  func advance(to next: Int) throws {
    try Self.save(Progress(run: run, offset: next), to: progressURL)
    offset = next
  }
}

extension BackupModel {
  func refreshHistoricalImport(clearError: Bool = false) async {
    guard ready, let target = pairing else { return }
    let version = historyControlRevision
    do {
      let data = try await Bridge.call(["op": "history_status", "receiver_id": target.receiverID])
      let status = try JSONDecoder().decode(HistoricalImportStatus?.self, from: data)
      guard pairing?.receiverID == target.receiverID, version == historyControlRevision else { return }
      let changedRun = historicalImport?.run != nil && historicalImport?.run != status?.run
      if historicalImport != status { historicalImport = status }
      // Polling must not erase a failed scan, permission or snapshot operation.
      if clearError || changedRun { historyError = nil }
    } catch { historyError = NSLocalizedString("history_operation_failed", comment: "") }
  }
  func controlHistoricalImport(_ action: String) async {
    guard ready, let target = pairing, !changingHistory else { return }
    changingHistory = true
    historyControlRevision += 1
    defer { changingHistory = false }
    if action != "pause", !(await authorizePhotos()) {
      historyError = NSLocalizedString("photos_permission_needed", comment: "")
      return
    }
    do {
      var command: [String: Any] = ["op": "history_control", "receiver_id": target.receiverID, "action": action]
      if action == "start" || action == "restart" {
        let snapshot = try await HistoricalScanCursor.capture(root: root, receiver: target.receiverID)
        guard pairing?.receiverID == target.receiverID else { return }
        command["snapshot_id"] = snapshot
      }
      let data = try await Bridge.call(command)
      guard pairing?.receiverID == target.receiverID else { return }
      historicalImport = try JSONDecoder().decode(HistoricalImportStatus.self, from: data)
      if action == "start" || action == "restart" { historicalCursor = nil }
      historyError = nil
      scheduleBackgroundWork()
      Task { await scanHistoricalImport() }
    } catch { historyError = NSLocalizedString("history_operation_failed", comment: "") }
  }
  func scanHistoricalImport() async {
    guard BackupEnvironment.usesPhotoLibrary, ready, !importing, !scanningHistory, !changingHistory, let target = pairing else { return }
    scanningHistory = true
    defer { scanningHistory = false }
    await refreshHistoricalImport()
    guard !paused, let status = historicalImport, status.state == "scanning" else { return }
    let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard access == .authorized || access == .limited else {
      historyError = NSLocalizedString("photos_permission_needed", comment: "")
      historicalCursor = nil
      return
    }
    guard await canPrepareForReceiver() else { return }
    let version = historyControlRevision
    do {
      if historicalCursor?.receiver != target.receiverID || historicalCursor?.run != status.run {
        let snapshot = try await HistoricalScanCursor.load(root: root,
          receiver: target.receiverID, run: status.run, snapshotID: status.snapshot_id)
        guard !Task.isCancelled, !paused, version == historyControlRevision,
          pairing?.receiverID == target.receiverID else { return }
        historicalCursor = snapshot
      }
      guard let cursor = historicalCursor else { return }
      let start = cursor.offset
      let end = min(start + 200, cursor.ids.count)
      let ids = Array(cursor.ids[start..<end])
      let sources = await Task.detached(priority: .utility) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: photoLibraryFetchOptions())
        var revisions = [String: String]()
        assets.enumerateObjects { asset, _, _ in
          let revision = String(Int64((asset.modificationDate ?? asset.creationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970 * 1000))
          revisions[asset.localIdentifier] = revision
        }
        return ids.compactMap { id -> [String]? in revisions[id].map { [id, $0] } }
      }.value
      guard !Task.isCancelled, !paused, version == historyControlRevision,
        pairing?.receiverID == target.receiverID else { return }
      var command: [String: Any] = ["op": "history_batch", "receiver_id": target.receiverID,
        "run": status.run, "sources": sources, "finished": end == cursor.ids.count]
      if let snapshot = status.snapshot_id { command["snapshot_id"] = snapshot }
      let data = try await Bridge.call(command)
      guard version == historyControlRevision, pairing?.receiverID == target.receiverID else { return }
      historicalImport = try JSONDecoder().decode(HistoricalImportStatus.self, from: data)
      try cursor.advance(to: end) // Replay after a crash is idempotent in Rust.
      if historicalImport?.state == "scanned" { historicalCursor = nil }
      historyError = nil
    } catch {
      guard version == historyControlRevision else { return }
      historyError = (error as? Bridge.Failure)?.code == "history_snapshot_unavailable"
        ? NSLocalizedString("error_history_snapshot_unavailable", comment: "")
        : NSLocalizedString("history_operation_failed", comment: "")
    }
  }
}

struct SourceBrowserItem: Decodable, Identifiable, Equatable {
  let cursor: Int64
  let source: String
  let revision: String
  let retry_at: Int64?
  let state: String?
  var error_code: String? = nil
  var request_id: String? = nil
  var sort_value: Int64? = nil
  var created_at_ms: Int64? = nil
  var id: String { request_id ?? source }
}


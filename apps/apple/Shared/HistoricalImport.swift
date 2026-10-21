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
    guard ready, !importing, !scanningHistory, !changingHistory, let target = pairing else { return }
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

struct HistoricalImportSettings: View {
  @ObservedObject var model: BackupModel
  var title: LocalizedStringKey = "history_title"
  var explanation: LocalizedStringKey = "history_explanation"
  var body: some View {
    #if os(macOS)
    VStack(alignment: .leading, spacing: 12) {
      Text(explanation).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
      if let status = model.historicalImport {
        LabeledContent("history_scan_status", value: NSLocalizedString("history_state_" + status.state, comment: ""))
        Text(String(format: NSLocalizedString("history_counts", comment: ""), status.checked, status.pending))
          .foregroundStyle(.secondary)
        if status.state == "scanning" {
          Button("history_pause") { Task { await model.controlHistoricalImport("pause") } }.duckSecondaryAction()
        } else if status.state == "paused" {
          Button("history_resume") { Task { await model.controlHistoricalImport("resume") } }.duckSecondaryAction()
        } else {
          Button("history_scan_again") { Task { await model.controlHistoricalImport("start") } }.duckSecondaryAction()
        }
      } else {
        Button("history_start") { Task { await model.controlHistoricalImport("start") } }.duckSecondaryAction()
      }
      if model.paused, model.historicalImport?.state == "scanning" {
        Text("history_backup_paused").foregroundStyle(.secondary)
        Button("resume_backup") { Task { if await model.setPaused(false) { await model.scanHistoricalImport() } } }.duckSecondaryAction()
      }
      if let error = model.historyError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
        if error == NSLocalizedString("error_history_snapshot_unavailable", comment: "") {
          Button("history_scan_again") { Task { await model.controlHistoricalImport("restart") } }.duckSecondaryAction()
        } else {
          Button("retry_task") { Task { await model.refreshHistoricalImport(clearError: true); await model.scanHistoricalImport() } }.duckSecondaryAction()
        }
      }
    }
      .disabled(!model.ready || model.pairing == nil || model.changingHistory || model.changingPause)
      .task { await model.refreshHistoricalImport() }
    #else
    Section {
      if let status = model.historicalImport {
        LabeledContent("history_scan_status", value: NSLocalizedString("history_state_" + status.state, comment: ""))
        Text(String(format: NSLocalizedString("history_counts", comment: ""), status.checked, status.pending))
          .foregroundStyle(.secondary)
        if status.state == "scanning" {
          Button("history_pause") { Task { await model.controlHistoricalImport("pause") } }
        } else if status.state == "paused" {
          Button("history_resume") { Task { await model.controlHistoricalImport("resume") } }
        } else {
          Button("history_scan_again") { Task { await model.controlHistoricalImport("start") } }
        }
      } else {
        Button("history_start") { Task { await model.controlHistoricalImport("start") } }
      }
      if model.paused, model.historicalImport?.state == "scanning" {
        Text("history_backup_paused").foregroundStyle(.secondary)
        Button("resume_backup") { Task { if await model.setPaused(false) { await model.scanHistoricalImport() } } }
      }
      if let error = model.historyError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
        if error == NSLocalizedString("error_history_snapshot_unavailable", comment: "") {
          Button("history_scan_again") { Task { await model.controlHistoricalImport("restart") } }
        } else {
          Button("retry_task") { Task { await model.refreshHistoricalImport(clearError: true); await model.scanHistoricalImport() } }
        }
      }
    } header: { Text(title) } footer: { Text(explanation) }
      .disabled(!model.ready || model.pairing == nil || model.changingHistory || model.changingPause)
      .task { await model.refreshHistoricalImport() }
    #endif
  }
}

/// A compact overview; detailed scan controls live with backup preferences.
struct HistoricalImportProgress: View {
  @ObservedObject var model: BackupModel
  var body: some View {
    if let status = model.historicalImport, status.state != "scanned" || status.pending > 0 {
      VStack(alignment: .leading, spacing: 8) {
        Label("history_title", systemImage: "photo.stack").font(.headline)
        Text(model.paused && status.state == "scanning" ? "history_backup_paused" : LocalizedStringKey("history_state_" + status.state))
        Text(String(format: NSLocalizedString("history_counts", comment: ""), status.checked, status.pending))
          .font(.callout).foregroundStyle(.secondary)
        if let error = model.historyError { Text(error).font(.callout).foregroundStyle(.orange) }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Preparation is durable work, but not yet a transfer job. Keep its browser separate.
struct SourceBrowser: View {
  @ObservedObject var model: BackupModel
  let history: Bool
  var descending = false
  var sort = "added"
  var inline = false
  @StateObject private var browser = SourceBrowserModel()
  @State private var retainedHistoryError: String?
  @State private var recoveringHistory = false
  @State private var errorRun: Int64?
  private var queryID: String {
    "\(history)|\(descending)|\(sort)|\(model.pairing?.receiverID ?? "")|\(model.queueRevision)|\(model.pendingImports)|\(model.importingSourceID ?? "")|\(model.historicalImport?.run ?? 0)|\(model.historicalImport?.checked ?? 0)|\(model.historicalImport?.state ?? "")"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if history {
        Text(LocalizedStringKey("history_state_" + (model.historicalImport?.state ?? "not_started")))
          .font(.callout).foregroundStyle(.secondary)
        Text("history_list_explanation").font(.caption).foregroundStyle(.secondary)
        if let error = model.historyError ?? retainedHistoryError {
          DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
            .accessibilityIdentifier("history.browser_error")
          Button(error == NSLocalizedString("error_history_snapshot_unavailable", comment: "") ? "history_scan_again" : "retry_task") {
            recoverHistory(restart: error == NSLocalizedString("error_history_snapshot_unavailable", comment: ""))
          }.duckSecondaryAction().disabled(recoveringHistory || model.changingHistory || !model.ready || model.pairing == nil)
        }
        if model.historyUnavailable {
          DuckNotice(title: "error_history_unavailable", tone: .attention)
            .accessibilityIdentifier("history.scope_unavailable")
        }
      } else if let reason = model.preparationReason {
        DuckNotice(title: LocalizedStringKey("error_" + reason), tone: .attention, symbol: "clock")
          .accessibilityIdentifier("preparation.browser_reason")
      }
      Text(String(format: NSLocalizedString("source_list_count", comment: ""), browser.items.count, browser.total))
        .font(.caption).foregroundStyle(.secondary)
      Group {
        #if os(iOS)
        if inline { sourceRows } else { ScrollView { sourceRows } }
        #else
        ScrollView { sourceRows }
        #endif
      }

    }.task(id: queryID) { await refresh() }
      .onChange(of: model.historyError) { _, error in
        if history, let error { retainedHistoryError = error; errorRun = model.historicalImport?.run }
      }
  }
  private var sourceRows: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
          if browser.loading && browser.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(24)
          } else if browser.failed {
            #if os(iOS)
            VStack(alignment: .leading, spacing: 12) {
              DuckNotice(title: "tasks_load_failed", tone: .failure)
              Button("retry_task") { Task { await refresh() } }.iosPrototypeAction()
            }
            #else
            Button("tasks_load_failed") { Task { await refresh() } }
              .frame(maxWidth: .infinity).padding(24)
            #endif
          } else if browser.items.isEmpty {
            #if os(iOS)
            DuckNotice(title: "tasks_empty_filtered")
            #else
            ContentUnavailableView("tasks_empty_filtered", systemImage: "photo.stack")
              .frame(maxWidth: .infinity).padding(.top, 24)
            #endif
          }
          ForEach(browser.items) { item in
            if history {
              SourceBrowserRow(item: item, active: model.importingSourceID == item.source,
                progress: model.exportProgress)
            } else {
              BackupTaskRow(item: BackupTaskItem(id: item.id, cursor: item.cursor,
                sort_value: item.sort_value, job: nil, preparation: item), model: model)
            }
            Divider()
          }
          if browser.hasMore {
            Button("load_more_tasks") { Task { await browser.loadMore() } }.padding(.vertical, 20)
          }
        }
  }
  private func recoverHistory(restart: Bool) {
    guard !recoveringHistory else { return }
    recoveringHistory = true
    Task {
      if restart { await model.controlHistoricalImport("restart") }
      else { await model.refreshHistoricalImport(clearError: true); await model.scanHistoricalImport() }
      retainedHistoryError = model.historyError
      errorRun = model.historicalImport?.run
      recoveringHistory = false
      await refresh()
    }
  }
  private func refresh() async {
    let receiver = model.pairing?.receiverID
    if history {
      if let error = model.historyError { retainedHistoryError = error; errorRun = model.historicalImport?.run }
      await model.refreshHistoricalImport()
      if retainedHistoryError != nil, errorRun != model.historicalImport?.run { retainedHistoryError = nil; errorRun = nil }
      if let error = model.historyError { retainedHistoryError = error; errorRun = model.historicalImport?.run }
    }
    await browser.refresh(receiver: receiver, history: history, run: model.historicalImport?.run, descending: descending, sort: sort)
    guard !Task.isCancelled, receiver == model.pairing?.receiverID, !browser.failed else { return }
    if !history { model.pendingImports = browser.total }
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

@MainActor final class SourceBrowserModel: ObservableObject {
  @Published var items: [SourceBrowserItem] = []
  @Published var total = 0
  @Published var loading = false
  @Published var failed = false
  @Published var hasMore = false
  private var receiver: String?
  private var history = false
  private var run: Int64?
  private var descending = false
  private var sort = "added"
  private var limit = 100
  private var generation = 0
  private struct Page: Decodable {
    let items: [SourceBrowserItem]
    let total: Int
    let run: Int64?
  }
  func loadMore() async {
    guard !loading else { return }
    limit += 100
    await refresh(receiver: receiver, history: history, run: run, descending: descending, sort: sort)
  }
  func refresh(receiver: String?, history: Bool, run: Int64?, descending: Bool = false, sort: String = "added") async {
    if self.receiver != receiver || self.history != history || self.descending != descending || self.sort != sort || (history && self.run != run) {
      items = []; total = 0; hasMore = false; limit = 100
    }
    self.descending = descending
    self.sort = sort
    self.receiver = receiver; self.history = history; self.run = run
    generation += 1
    let expected = generation
    guard let receiver else { items = []; total = 0; hasMore = false; loading = false; return }
    loading = true; failed = false
    defer { if generation == expected { loading = false } }
    do {
      if sort == "capture" {
        // Metadata only, in bounded batches off the main actor. Keep missing
        // PhotoKit dates as 0 so they remain unknown rather than using revision.
        while !Task.isCancelled {
          let data = try await Bridge.call(["op": "missing_browse_dates", "receiver_id": receiver, "history": history])
          let ids = try JSONDecoder().decode([String].self, from: data)
          if ids.isEmpty { break }
          let dates = await Task.detached(priority: .utility) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: photoLibraryFetchOptions())
            var found: [String: Int64] = [:]
            assets.enumerateObjects { asset, _, _ in
              found[asset.localIdentifier] = asset.creationDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
            }
            return ids.map { ($0, found[$0] ?? 0) }
          }.value
          guard expected == generation, !Task.isCancelled else { return }
          _ = try await Bridge.call(["op": "source_dates", "receiver_id": receiver, "dates": dates.map { [$0.0, $0.1] as [Any] }])
        }
        guard expected == generation, !Task.isCancelled else { return }
      }
      var result: [SourceBrowserItem] = []
      var cursor: Int64 = 0
      var afterValue: Int64?
      var total = 0
      var firstRun: Int64?
      repeat {
        var query: [String: Any] = ["op": "browse_sources", "receiver_id": receiver,
          "history": history, "after": cursor, "descending": descending, "sort": sort]
        if let afterValue { query["after_value"] = afterValue }
        let data = try await Bridge.call(query)
        let page = try JSONDecoder().decode(Page.self, from: data)
        guard expected == generation, !Task.isCancelled else { return }
        if cursor == 0 { firstRun = page.run }
        // A new scan cannot be joined to pages from the previous scan.
        if history && firstRun != page.run { return }
        result.append(contentsOf: page.items)
        total = page.total
        guard page.items.count == 100, let last = page.items.last else { break }
        cursor = last.cursor
        afterValue = last.sort_value
      } while result.count < limit
      if items != result { items = result }
      self.total = total
      hasMore = result.count < total && result.count >= limit
    } catch {
      guard expected == generation, !Task.isCancelled else { return }
      failed = true
    }
  }
}

struct SourceBrowserRow: View {
  let item: SourceBrowserItem
  let active: Bool
  let progress: Double?
  var topInset: CGFloat = 12
  @State private var title = ""
  @State private var kind = "photo"
  @State private var captured: Date?
  private var state: String { active ? "preparing" : item.error_code != nil ? "failed" : item.state ?? "preparing" }
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .caption) private var captionSize = 13
  @Environment(\.dynamicTypeSize) private var textSize
  private var thumbnailSize: CGFloat { textSize.isAccessibilitySize ? 48 : 54 }
  private var rowSpacing: CGFloat { 12 }
  private var verticalPadding: CGFloat { 12 }
  #else
  private var thumbnailSize: CGFloat { 44 }
  private var rowSpacing: CGFloat { 14 }
  private var verticalPadding: CGFloat { 12 }
  #endif
  #if os(macOS)
  private var macRow: some View {
    HStack(spacing: 14) {
      AssetThumbnail(sourceID: item.source, size: 44)
      VStack(alignment: .leading, spacing: 5) {
        Text(title.isEmpty ? NSLocalizedString("source_photo_unavailable", comment: "") : title)
          .font(.system(size: 14, weight: .semibold)).lineLimit(1)
        HStack(spacing: 6) {
          if !title.isEmpty {
            Label(LocalizedStringKey("library_filter_" + kind), systemImage: kind == "burst" ? "square.stack" : kind == "motion" ? "livephoto" : kind == "video" ? "video" : "photo")
          }
          if let captured { Text(captured.formatted(date: .abbreviated, time: .shortened)) }
          else { Text("design_capture_unknown") }
          Text("·")
          Text("source_system_library")
        }.font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 5) {
        Label(active ? "importing_originals" : LocalizedStringKey(item.error_code.map { "error_" + $0 } ?? "state_" + state), systemImage: taskSymbol(state))
          .font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary).lineLimit(1)
        if active {
          if let progress { ProgressView(value: progress).frame(width: 100, height: 8) }
          else { ProgressView().controlSize(.mini).frame(width: 12, height: 12) }
        } else if let retry = item.retry_at, retry > Int64(Date().timeIntervalSince1970) {
          Text(String(format: NSLocalizedString("task_retry_time", comment: ""), Date(timeIntervalSince1970: Double(retry)).formatted(date: .omitted, time: .standard)))
            .font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary).lineLimit(1)
        }
      }.fixedSize(horizontal: false, vertical: true)
    }.padding(.top, topInset).padding(.bottom, 12)
  }
  #endif
  var body: some View {
    Group {
    #if os(macOS)
      macRow
    #else
    HStack(spacing: rowSpacing) {
      AssetThumbnail(sourceID: item.source, size: thumbnailSize)
      VStack(alignment: .leading, spacing: 7) {
        Text(title.isEmpty ? NSLocalizedString("source_photo_unavailable", comment: "") : title)
          #if os(iOS)
            .iosPrototypeText(size: bodySize, weight: .semibold, lineHeight: 1.4).fixedSize(horizontal: false, vertical: true)
          #else
            .lineLimit(1)
          #endif
        HStack {
          Label(LocalizedStringKey("library_filter_" + kind), systemImage:
            kind == "burst" ? "square.stack" : kind == "motion" ? "livephoto" : kind == "video" ? "video" : "photo")
          if let captured { Text(captured.formatted(date: .abbreviated, time: .shortened)) }
        }
        #if os(iOS)
          .iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
        #else
          .font(.caption).foregroundStyle(.secondary)
        #endif
        HStack(spacing: 8) {
          Label(active ? "importing_originals" : LocalizedStringKey(item.error_code.map { "error_" + $0 } ?? "state_" + state),
            systemImage: taskSymbol(state))
            #if os(iOS)
              .fixedSize(horizontal: false, vertical: true)
            #else
              .lineLimit(1)
            #endif
          if active {
            if let progress { ProgressView(value: progress).frame(width: 100, height: 8) }
            else { ProgressView().controlSize(.mini).frame(width: 12, height: 12) }
          }
          Spacer(minLength: 0)
          if !active, let retry = item.retry_at, retry > Int64(Date().timeIntervalSince1970) {
            Text(String(format: NSLocalizedString("task_retry_time", comment: ""),
              Date(timeIntervalSince1970: Double(retry)).formatted(date: .omitted, time: .standard)))
              .lineLimit(1)
          }
        }
        #if os(iOS)
          .iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
        #else
          .font(.caption).foregroundStyle(.secondary)
        #endif

      }
      Spacer(minLength: 0)
    }.padding(.vertical, verticalPadding)
    #endif
    }
      .task(id: item.source) {
        let source = item.source
        let details = await Task.detached(priority: .utility) { () -> (String, String, Date?)? in
          guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [source], options: photoLibraryFetchOptions()).firstObject else { return nil }
          return (PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "",
            asset.burstIdentifier != nil ? "burst" : asset.mediaSubtypes.contains(.photoLive) ? "motion" : asset.mediaType == .video ? "video" : "photo",
            asset.creationDate)
        }.value
        guard !Task.isCancelled, let details else { return }
        title = details.0; kind = details.1; captured = details.2
      }
  }
}

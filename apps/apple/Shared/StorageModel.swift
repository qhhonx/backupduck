import Foundation
import Photos
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

struct StorageSettings: Codable, Equatable {
  var cache_budget_bytes: UInt64
  var receiver_budget_bytes: UInt64
  var min_free_bytes: UInt64
  var auto_reclaim: Bool
  var log_days: Int
  var log_limit: Int
}
struct StorageSnapshot: Decodable, Equatable {
  var settings: StorageSettings
  let used_bytes: UInt64
  let free_bytes: UInt64
  let export_allowance: UInt64
  let reason: String?
  var limitingReason: String {
    free_bytes > settings.min_free_bytes
      && free_bytes - settings.min_free_bytes > settings.cache_budget_bytes
        - min(used_bytes, settings.cache_budget_bytes)
      ? "local_cache_budget" : "local_free_space"
  }
}
enum StoragePreferenceScope { case all, cache }

struct StoragePreferences: View {
  @ObservedObject var model: BackupModel
  var scope: StoragePreferenceScope = .all
  @State private var logs = false
  var body: some View {
    controls
      .buttonStyle(.borderless)
      .pickerStyle(.menu)
      .disabled(model.savingStorage)
  }
  @ViewBuilder private var controls: some View {
    #if os(macOS)
      VStack(alignment: .leading, spacing: 14) { rows }
    #else
      // A Form must see separate rows. A VStack combines all controls into one
      // row and automatic picker/button actions can capture unrelated taps.
      rows
    #endif
  }
  @ViewBuilder private var rows: some View {
    Group {
      Text(LocalizedStringKey(
        scope == .cache
          ? "settings_cache" : "storage_settings"
      )).font(.headline).task { await model.refreshStorage() }
      if let snapshot = model.storage {
        Group {
          #if os(macOS)
            Text("mac_storage_cache_description").font(.footnote).foregroundStyle(.secondary)
          #else
            Text("storage_cache_description").font(.footnote).foregroundStyle(.secondary)
          #endif
          LabeledContent("storage_cache_used", value: bytes(snapshot.used_bytes))
          LabeledContent("storage_disk_free", value: bytes(snapshot.free_bytes))
          if let reason = snapshot.reason,
            ["local_free_space", "local_cache_budget"].contains(reason) {
            DuckNotice(title: LocalizedStringKey("error_" + reason), tone: .attention,
              symbol: "exclamationmark.circle")
              .accessibilityIdentifier("settings.cache_limit_reason")
          }
          Picker(
            "storage_cache_budget",
            selection: Binding(
              get: { Int(snapshot.settings.cache_budget_bytes >> 30) },
              set: { value in
                var settings = snapshot.settings
                settings.cache_budget_bytes = UInt64(value) << 30
                Task { await model.saveStorage(settings) }
              })
          ) { ForEach([1, 2, 5, 10, 20, 50], id: \.self) { Text("\($0) GB").tag($0) } }
          .accessibilityIdentifier("settings.cache_budget")
          Text("storage_cache_budget_help").font(.footnote).foregroundStyle(.secondary)
          Picker(
            "storage_min_free",
            selection: Binding(
              get: { Int(snapshot.settings.min_free_bytes >> 30) },
              set: { value in
                var settings = snapshot.settings
                settings.min_free_bytes = UInt64(value) << 30
                Task { await model.saveStorage(settings) }
              })
          ) { ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) GB").tag($0) } }
          Text("storage_min_free_help").font(.footnote).foregroundStyle(.secondary)
          Toggle(
            "storage_auto_reclaim",
            isOn: Binding(
              get: { snapshot.settings.auto_reclaim },
              set: { value in
                var settings = snapshot.settings
                settings.auto_reclaim = value
                Task { await model.saveStorage(settings) }
              }))
          #if os(macOS)
            Text("mac_storage_reclaim_note").font(.footnote).foregroundStyle(.secondary)
          #else
            Text("storage_reclaim_note").font(.footnote).foregroundStyle(.secondary)
          #endif
          if snapshot.used_bytes == 0 {
            Text("storage_cache_empty").foregroundStyle(.secondary)
          } else {
            Button {
              Task { await model.reclaimCache(reportResult: true) }
            } label: {
              Label(LocalizedStringKey(model.reclaimingCache ? "storage_reclaim_running" : "storage_reclaim_now"),
                systemImage: "arrow.clockwise")
            }.buttonStyle(.bordered)
              .disabled(model.reclaimingCache || !model.ready)
              .accessibilityIdentifier("settings.reclaim_cache")
            Text("storage_reclaim_check_help").font(.footnote).foregroundStyle(.secondary)
          }
          if let result = model.cacheReclaimResult {
            DuckNotice(title: LocalizedStringKey(result))
              .accessibilityIdentifier("settings.reclaim_result")
          }
        }

      } else if let error = model.storageError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
        Button("retry_task") { Task { await model.refreshStorage() } }
      } else {
        DuckLoadingState(scope == .cache ? "cache_settings_loading" : "settings_loading")
          .controlSize(.small)
      }
      if model.storage != nil, let error = model.storageError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
      }
      if let error = model.storageSettingsError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
          .accessibilityIdentifier("settings.storage_save_error")
      }
      if let error = model.cacheReclaimError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
          .accessibilityIdentifier("settings.cache_reclaim_error")
      }

      if scope == .all {
        Button {
          logs = true
        } label: {
          Label("settings_diagnostics", systemImage: "list.bullet.rectangle")
        }.accessibilityIdentifier("settings.activity_log")
          .sheet(isPresented: $logs) { NavigationStack { DiagnosticsView(model: model) } }
      }
    }
  }
  private func bytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
  }
}
/// The recent-activity preview only projects the fields it displays. Export keeps
/// the complete core snapshot, including fields unknown to this host.
struct ActivityEntry: Decodable, Identifiable, Equatable {
  let id: Int64
  let timestamp: Int64
  let code: String
  let job_id: Int64?
  let bytes: Int64?
  let context: ActivityContext?
  var title: String { Bundle.main.localizedString(forKey: "diagnostics_event_" + code, value: code, table: nil) }
  /// Raw event identity remains available to exports and internal callers only.
  var userFacingTitle: String {
    Bundle.main.localizedString(forKey: "diagnostics_event_" + code,
      value: NSLocalizedString("diagnostics_other_activity", comment: ""), table: nil)
  }
  var day: Date { timestamp > 0 ? Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double(timestamp))) : .distantPast }
  var time: String { timestamp > 0 ? Date(timeIntervalSince1970: Double(timestamp)).formatted(date: .omitted, time: .shortened) : "—" }
}
struct ActivityContext: Codable, Equatable {
  let queued: Int?
  let running: Int?
  let waiting: Int?
  let failed: Int?
  let pending_imports: Int?
  let discovery_pending: Int?
  let paused: Bool?
  let active_requests: Int?
  let next_retry_at: Int64?
  let http_status: Int?
  let system_error: Int?
  let bytes_sent: Int64?
  let bytes_expected: Int64?
  let execution: String?
  let phase: String?
  let reason: String?
}
struct ActivityLogUpdate: Decodable {
  let entries: [ActivityEntry]
  let oldest_id: Int64?
  let newest_id: Int64?
  let reset: Bool
}

@MainActor final class ActivityLogModel: ObservableObject {
  @Published private(set) var entries: [ActivityEntry] = []
  @Published private(set) var pendingCount = 0
  @Published private(set) var failed = false
  @Published private(set) var loaded = false
  var recentEntries: [ActivityEntry] { Array(entries.prefix(6)) }
  private var latest: [ActivityEntry] = []
  private(set) var cursor: Int64 = 0
  private let fetch: (Int64) async throws -> ActivityLogUpdate
  init(fetch: @escaping (Int64) async throws -> ActivityLogUpdate = { cursor in
    try JSONDecoder().decode(ActivityLogUpdate.self,
      from: await Bridge.call(["op": "activity_log", "receiver": false, "after": cursor]))
  }) { self.fetch = fetch }

  @discardableResult func refresh(followingNewest: () -> Bool) async -> Bool {
    do {
      let update = try await fetch(cursor)
      guard !Task.isCancelled else { return false }
      var merged = update.reset ? [] : latest
      if !update.entries.isEmpty {
        let incoming = Set(update.entries.map(\.id))
        merged.removeAll { incoming.contains($0.id) }
        merged = (update.entries + merged).sorted { $0.timestamp == $1.timestamp ? $0.id > $1.id : $0.timestamp > $1.timestamp }
      }
      if let oldest = update.oldest_id { merged.removeAll { $0.id < oldest } }
      else { merged = [] }
      latest = merged
      cursor = update.newest_id ?? 0
      let follow = followingNewest() || !loaded
      if follow { showLatest() }
      else {
        let shown = Set(entries.map(\.id))
        let count = latest.filter { !shown.contains($0.id) }.count
        if pendingCount != count { pendingCount = count }
      }
      if !loaded { loaded = true }
      if failed { failed = false }
      return follow
    } catch {
      if !Task.isCancelled && !failed { failed = true }
      return false
    }
  }
  func showLatest() {
    if entries != latest { entries = latest }
    if pendingCount != 0 { pendingCount = 0 }
  }
}

/// Preparation belongs to the visible app sheet. System sharing only receives a
/// finished immutable file, so snapshot/write failures cannot disappear in ShareLink.
@MainActor final class ActivityLogExportModel: ObservableObject {
  @Published private(set) var preparing = false
  @Published private(set) var url: URL?
  @Published private(set) var failed = false
  private let snapshot: () async throws -> Data
  private let write: (Data) async throws -> URL
  init(
    snapshot: @escaping () async throws -> Data = {
      try await Bridge.call(["op": "activity_log", "receiver": false])
    },
    write: @escaping (Data) async throws -> URL = { data in
      try await Task.detached(priority: .utility) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
          "BackupDuck-diagnostics-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("BackupDuck-diagnostics.json")
        try data.write(to: url, options: .atomic)
        return url
      }.value
    }
  ) { self.snapshot = snapshot; self.write = write }

  func prepare() async {
    guard !preparing else { return }
    preparing = true; failed = false; url = nil
    defer { preparing = false }
    do {
      let data = try await snapshot()
      try Task.checkCancellation()
      let result = try await write(data)
      try Task.checkCancellation()
      url = result
    } catch {
      if !Task.isCancelled { failed = true }
    }
  }
}

/// Settings navigation is pushed on iPhone and contained in the Mac detail pane.
/// Catalog start positions select these same production destinations.
struct DiagnosticsView: View {
  @ObservedObject var model: BackupModel
  var initialPage: String? = nil
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var journal = ActivityLogModel()
  @StateObject private var export = ActivityLogExportModel()
  @State private var save = false
  @State private var savedName: String?
  @State private var saveFailed = false
  @State private var didOpenInitial = false
  private var exportNote: String {
    if export.preparing { return NSLocalizedString("logs_export_preparing", comment: "") }
    if export.failed || saveFailed { return NSLocalizedString("diagnostics_export_failed", comment: "") }
    if let savedName { return String(format: NSLocalizedString("diagnostics_file_saved", comment: ""), savedName) }
    return NSLocalizedString("diagnostics_export_contents", comment: "")
  }
  private var dayGroups: [(Date, [ActivityEntry])] {
    let grouped = Dictionary(grouping: journal.recentEntries, by: \.day)
    return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
  }
  private var exportLabel: some View {
    HStack(spacing: DuckSpacing.small + DuckSpacing.xSmall) {
      DuckSettingsIcon(symbol: "square.and.arrow.up", color: DuckGlyph.blue)
      VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
        Text("diagnostics_export_title").font(.body).foregroundStyle(.primary)
        Text(exportNote).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private var settingsForm: some View {
    Form {
      Section {
        #if os(macOS)
        LabeledContent {
          Button("diagnostics_export_action", action: prepare)
            .buttonStyle(.bordered).disabled(export.preparing)
            .accessibilityIdentifier("activity.export")
        } label: { exportLabel }
        #else
        Button(action: prepare) {
          HStack(spacing: DuckSpacing.small) {
            exportLabel
            if export.preparing { ProgressView().controlSize(.small) }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
          }.modifier(DiagnosticPreferencePadding()).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(export.preparing)
          .accessibilityIdentifier("activity.export").modifier(DiagnosticSettingsRowInsets())
        #endif
      } footer: {
        Text("diagnostics_intro").font(.footnote)
          #if os(macOS)
          .foregroundStyle(.secondary)
          #endif
      }
      if journal.entries.isEmpty {
        Section {
          LabeledContent {
            EmptyView()
          } label: {
            Text(journal.failed ? "logs_load_failed" : journal.loaded ? "logs_empty" : "logs_loading")
              .font(.body).foregroundStyle(.secondary)
          }
        } header: {
          activityAreaTitle
        }
      } else {
        ForEach(dayGroups, id: \.0) { day, entries in
          Section {
            ForEach(entries) { entry in
              LabeledContent {
                Text(entry.time).font(.body.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
              } label: {
                Text(entry.userFacingTitle).font(.body).fixedSize(horizontal: false, vertical: true)
              }.accessibilityElement(children: .combine)
            }
          } header: {
            VStack(alignment: .leading, spacing: activitySectionGap) {
              if day == dayGroups.first?.0 {
                activityAreaTitle
              }
              Text(dayHeader(day))
                #if os(macOS)
                .font(.caption)
                #else
                .font(.footnote)
                #endif
                .foregroundStyle(DuckRole.secondaryText)
            }.textCase(nil)
          }
        }
      }
    }
    .formStyle(.grouped)
    #if os(macOS)
    .labeledContentStyle(DuckPreferenceRowStyle())
    #else
    .labeledContentStyle(.automatic)
    .environment(\.defaultMinListRowHeight, DuckPreferenceMetrics.rowHeight)
    .listSectionSpacing(.custom(activitySectionGap))
    #endif
  }
  private var activityAreaTitle: some View {
    Text("diagnostics_recent")
      #if os(macOS)
      .font(.headline)
      #else
      .font(.title3.weight(.semibold))
      #endif
      .foregroundStyle(DuckRole.primaryText)
      .textCase(nil)
      .accessibilityAddTraits(.isHeader)
  }
  private var activitySectionGap: CGFloat {
    #if os(macOS)
    DuckSpacing.medium
    #else
    DuckSpacing.large
    #endif
  }
  private func dayHeader(_ day: Date) -> String {
    if day == .distantPast { return NSLocalizedString("records_day_unknown", comment: "") }
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return NSLocalizedString("records_today", comment: "") }
    if calendar.isDateInYesterday(day) { return NSLocalizedString("records_yesterday", comment: "") }
    let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
    return day.formatted(sameYear ? .dateTime.month().day().weekday() : .dateTime.year().month().day())
  }
  var body: some View {
    settingsForm
    .navigationTitle("settings_diagnostics")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $save) {
      if let url = export.url {
        DiagnosticShareSheet(url: url) { completed, error in
          if completed { savedName = url.lastPathComponent }
          saveFailed = error != nil
          save = false
        }
      }
    }
    #else
    .fileExporter(isPresented: $save, document: DiagnosticDocument(url: export.url), contentType: .json,
      defaultFilename: export.url?.lastPathComponent ?? "BackupDuck-diagnostics.json") { result in
        switch result {
        case .success(let url): savedName = url.lastPathComponent; saveFailed = false
        case .failure: saveFailed = true
        }
      }
    #endif
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      await journal.refresh { true }
      guard !didOpenInitial else { return }; didOpenInitial = true
      // Only catalog callers pass a start position. Completion fixtures exercise
      // the same status row without dismissing a real system sheet automatically.
      if ["export-success", "export-failure", "export-sheet"].contains(initialPage ?? "") {
        await export.prepare()
        if initialPage == "export-success" { savedName = export.url?.lastPathComponent }
        if initialPage == "export-sheet" { save = export.url != nil }
      }
    }
  }
  private func prepare() {
    savedName = nil; saveFailed = false
    Task { await export.prepare(); save = export.url != nil }
  }
}

private struct DiagnosticSettingsRowInsets: ViewModifier {
  func body(content: Content) -> some View {
    #if os(iOS)
    // Explicit cell insets keep the 36 pt label at 52 pt on system versions
    // whose default grouped Form buttons add more vertical padding.
    content.listRowInsets(EdgeInsets(top: DuckSpacing.xSmall, leading: DuckSpacing.medium,
      bottom: DuckSpacing.xSmall, trailing: DuckSpacing.medium))
    #else
    content
    #endif
  }
}

private struct DiagnosticPreferencePadding: ViewModifier {
  func body(content: Content) -> some View {
    #if os(macOS)
    content.padding(.vertical, DuckSettingsMetrics.formIconRowPadding)
    #else
    content.frame(minHeight: DuckPreferenceMetrics.rowHeight - DuckSpacing.medium)
    #endif
  }
}

#if os(iOS)
private struct DiagnosticShareSheet: UIViewControllerRepresentable {
  let url: URL
  let completion: (Bool, Error?) -> Void
  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    controller.completionWithItemsHandler = { _, completed, _, error in completion(completed, error) }
    return controller
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else
private struct DiagnosticDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  let data: Data
  init(url: URL?) { data = url.flatMap { try? Data(contentsOf: $0) } ?? Data() }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#endif

/// PhotoKit streams into an app-owned file; enforce the Rust-provided budget
/// before writing each chunk, without buffering the complete original in memory.
final class BoundedExportWriter: @unchecked Sendable {
  private let lock = NSLock()
  private let file: FileHandle
  private let allowance: UInt64
  private let reason: String
  private let path: String
  private let reserve: UInt64
  private var written: UInt64 = 0
  private var checked: UInt64 = 0
  private var failure: Error?
  private var request: PHAssetResourceDataRequestID?
  init(url: URL, snapshot: StorageSnapshot) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    file = try FileHandle(forWritingTo: url)
    path = url.deletingLastPathComponent().path
    allowance = snapshot.export_allowance
    reason = snapshot.limitingReason
    reserve = snapshot.settings.min_free_bytes
  }
  func bind(_ id: PHAssetResourceDataRequestID) {
    lock.lock()
    request = id
    let cancelled = failure != nil
    lock.unlock()
    if cancelled { PHAssetResourceManager.default().cancelDataRequest(id) }
  }
  func consume(_ data: Data) {
    lock.lock()
    if failure == nil {
      do {
        guard UInt64(data.count) <= allowance - min(written, allowance) else {
          throw Bridge.Failure(code: reason)
        }
        if written - checked >= 4 << 20 || written == 0 {
          let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
          let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
          guard free > reserve + UInt64(data.count) + (8 << 20) else {
            throw Bridge.Failure(code: "local_free_space")
          }
          checked = written
        }
        try file.write(contentsOf: data)
        written += UInt64(data.count)
      } catch { failure = error }
    }
    let cancel = failure != nil ? request : nil
    lock.unlock()
    if let cancel { PHAssetResourceManager.default().cancelDataRequest(cancel) }
  }
  func cancel() {
    lock.lock()
    failure = CancellationError()
    let id = request
    lock.unlock()
    if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
  }
  func finish(_ error: Error?) -> Error? {
    lock.lock()
    defer { lock.unlock() }
    do { try file.close() } catch { if failure == nil { failure = error } }
    return failure ?? error
  }
}

struct WaitingStatus: View {
  @ObservedObject var model: BackupModel
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if let reason = model.waitingReason {
        Label(LocalizedStringKey("error_" + reason), systemImage: "clock").foregroundStyle(.orange)
        if let retry = model.summary.next_retry_at, retry > Int64(Date().timeIntervalSince1970) {
          Text(
            String(
              format: NSLocalizedString("retry_scheduled", comment: ""),
              Date(timeIntervalSince1970: Double(retry)).formatted(date: .omitted, time: .shortened)
            ))
        }
      }
      if model.pendingImports > 0 {
        Text(
          String(format: NSLocalizedString("imports_pending", comment: ""), model.pendingImports))
      }
    }.font(.caption)
  }
}

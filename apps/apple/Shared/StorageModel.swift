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
enum StoragePreferenceScope { case all, cache, logs }

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
          ? "settings_cache" : scope == .logs ? "settings_log_retention" : "storage_settings"
      )).font(.headline).task { await model.refreshStorage() }
      if let snapshot = model.storage {
        if scope != .logs {
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
        if scope == .all { Divider() }
        if scope != .cache {
          Picker(
            "logs_retention",
            selection: Binding(
              get: { snapshot.settings.log_days },
              set: { value in
                var settings = snapshot.settings
                settings.log_days = value
                Task { await model.saveStorage(settings) }
              })
          ) {
            ForEach([1, 7, 14, 30, 90], id: \.self) {
              Text(String(format: NSLocalizedString("logs_days", comment: ""), $0)).tag($0)
            }
          }
          Picker(
            "logs_limit",
            selection: Binding(
              get: { snapshot.settings.log_limit },
              set: { value in
                var settings = snapshot.settings
                settings.log_limit = value
                Task { await model.saveStorage(settings) }
              })
          ) { ForEach([1000, 5000, 10000, 20000], id: \.self) { Text("\($0)").tag($0) } }
        }
      } else if let error = model.storageError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
        Button("retry_task") { Task { await model.refreshStorage() } }
      } else {
        DuckLoadingState(scope == .cache ? "cache_settings_loading" : scope == .logs ? "log_settings_loading" : "settings_loading")
          .controlSize(.small)
      }
      if model.storage != nil, let error = model.storageError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
      }
      if let error = model.storageSettingsError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
          .accessibilityIdentifier("settings.storage_save_error")
      }
      if scope != .logs, let error = model.cacheReclaimError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
          .accessibilityIdentifier("settings.cache_reclaim_error")
      }

      if scope == .all {
        Button {
          logs = true
        } label: {
          Label("activity_log", systemImage: "list.bullet.rectangle")
        }.accessibilityIdentifier("settings.activity_log")
          .sheet(isPresented: $logs) { NavigationStack { DiagnosticsView(model: model) } }
      }
    }
  }
  private func bytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
  }
}
/// JSON values remain lossless for future log fields that this host does not know.
indirect enum DiagnosticValue: Codable, Equatable {
  case string(String), integer(Int64), unsigned(UInt64), number(Double), bool(Bool), null
  case array([DiagnosticValue]), object([String: DiagnosticValue])
  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() { self = .null }
    else if let v = try? value.decode(Bool.self) { self = .bool(v) }
    else if let v = try? value.decode(Int64.self) { self = .integer(v) }
    else if let v = try? value.decode(UInt64.self) { self = .unsigned(v) }
    else if let v = try? value.decode(Double.self) { self = .number(v) }
    else if let v = try? value.decode(String.self) { self = .string(v) }
    else if let v = try? value.decode([DiagnosticValue].self) { self = .array(v) }
    else { self = .object(try value.decode([String: DiagnosticValue].self)) }
  }
  func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .string(let v): try value.encode(v)
    case .integer(let v): try value.encode(v)
    case .unsigned(let v): try value.encode(v)
    case .number(let v): try value.encode(v)
    case .bool(let v): try value.encode(v)
    case .null: try value.encodeNil()
    case .array(let v): try value.encode(v)
    case .object(let v): try value.encode(v)
    }
  }
  var text: String {
    if case .string(let value) = self { return value }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
  }
  func fields(prefix: String) -> [(String, String)] {
    if case .object(let object) = self, !object.isEmpty {
      return object.keys.sorted().flatMap { object[$0]!.fields(prefix: prefix.isEmpty ? $0 : prefix + "." + $0) }
    }
    return [(prefix, text)]
  }
}

struct ActivityEntry: Decodable, Identifiable, Equatable {
  let id: Int64
  let timestamp: Int64
  let code: String
  let job_id: Int64?
  let bytes: Int64?
  let context: ActivityContext?
  let recorded: [String: DiagnosticValue]
  init(id: Int64, timestamp: Int64, code: String, job_id: Int64?, bytes: Int64?, context: ActivityContext?) {
    self.id = id; self.timestamp = timestamp; self.code = code; self.job_id = job_id; self.bytes = bytes; self.context = context
    var values: [String: DiagnosticValue] = ["id": .integer(id), "timestamp": .integer(timestamp), "code": .string(code)]
    if let job_id { values["job_id"] = .integer(job_id) }
    if let bytes { values["bytes"] = .integer(bytes) }
    if let context, let data = try? JSONEncoder().encode(context), let value = try? JSONDecoder().decode(DiagnosticValue.self, from: data) { values["context"] = value }
    recorded = values
  }
  enum CodingKeys: String, CodingKey { case id, timestamp, code, job_id, bytes, context }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(Int64.self, forKey: .id); timestamp = try c.decode(Int64.self, forKey: .timestamp)
    code = try c.decode(String.self, forKey: .code); job_id = try c.decodeIfPresent(Int64.self, forKey: .job_id)
    bytes = try c.decodeIfPresent(Int64.self, forKey: .bytes); context = try c.decodeIfPresent(ActivityContext.self, forKey: .context)
    recorded = try decoder.singleValueContainer().decode([String: DiagnosticValue].self)
  }
  var title: String { Bundle.main.localizedString(forKey: "diagnostics_event_" + code, value: code, table: nil) }
  var day: Date { timestamp > 0 ? Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double(timestamp))) : .distantPast }
  var time: String { timestamp > 0 ? Date(timeIntervalSince1970: Double(timestamp)).formatted(date: .omitted, time: .standard) : "—" }
  var fields: [(String, String)] {
    let order = ["id", "timestamp", "code", "job_id", "bytes", "context"]
    return (order.filter { recorded[$0] != nil } + recorded.keys.filter { !order.contains($0) }.sorted()).flatMap { key in
      let fields = recorded[key]!.fields(prefix: key)
      if key == "timestamp", timestamp > 0 {
        return [(key, "\(timestamp) · \(Date(timeIntervalSince1970: Double(timestamp)).formatted(date: .abbreviated, time: .standard))")]
      }
      return fields
    }
  }
  var json: String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(recorded)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  }
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

private struct ActivityLogReport: Transferable {
  let url: URL
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .json) { report in
      SentTransferredFile(report.url)
    }
  }
}

/// Settings navigation is pushed on iPhone and contained in the Mac detail pane.
/// Catalog start positions select these same production destinations.
struct DiagnosticsView: View {
  @ObservedObject var model: BackupModel
  var initialPage: String? = nil
  @State private var log = false
  @State private var settings = false
  @StateObject private var export = ActivityLogExportModel()
  @State private var save = false
  @State private var savedName: String?
  @State private var saveFailed = false
  @State private var didOpenInitial = false
  var body: some View {
    Form {
      Section {
        NavigationLink(isActive: $log) { ActivityLogView(embedded: true, initialDetail: initialPage == "detail") } label: {
          DuckSettingsLabel(title: "activity_log", symbol: "list.bullet.rectangle", color: DuckGlyph.blue)
        }.accessibilityIdentifier("diagnostics.log")
      } header: { Text("diagnostics_intro").textCase(nil) }
      Section("diagnostics_exports") {
        VStack(alignment: .leading, spacing: DuckSpacing.small) {
          Text("diagnostics_export_contents")
          if export.preparing {
            ProgressView("logs_export_preparing")
          } else if export.failed || saveFailed {
            Text("diagnostics_export_failed").foregroundStyle(.secondary)
            Button("retry_task") { prepare() }.accessibilityIdentifier("activity.export_retry")
          } else if let url = export.url {
            Text(String(format: NSLocalizedString(savedName == nil ? "diagnostics_file_ready" : "diagnostics_file_saved", comment: ""), savedName ?? url.lastPathComponent))
              .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("activity.export_ready")
            #if os(macOS)
            Button("logs_export_share") { save = true }.accessibilityIdentifier("activity.export_share")
            #else
            ShareLink(item: ActivityLogReport(url: url), preview: SharePreview(url.lastPathComponent)) {
              Label("logs_export_share", systemImage: "square.and.arrow.up")
            }.accessibilityIdentifier("activity.export_share")
            #endif
          } else {
            Button("logs_export") { prepare() }.accessibilityIdentifier("activity.export")
          }
        }.padding(.vertical, DuckSpacing.xSmall)
      }
      Section {
        NavigationLink(isActive: $settings) { DiagnosticLogSettings(model: model) } label: {
          DuckSettingsLabel(title: "settings_log_retention", symbol: "clock", color: DuckGlyph.gray)
        }.accessibilityIdentifier("diagnostics.settings")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("settings_diagnostics")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .fileExporter(isPresented: $save, document: DiagnosticDocument(url: export.url), contentType: .json,
      defaultFilename: export.url?.lastPathComponent ?? "BackupDuck-diagnostics.json") { result in
        switch result {
        case .success(let url): savedName = url.lastPathComponent; saveFailed = false
        case .failure: saveFailed = true
        }
      }
    .task {
      guard !didOpenInitial else { return }; didOpenInitial = true
      log = ["log", "empty", "failed", "detail"].contains(initialPage ?? "")
      settings = initialPage == "settings"
      if ["export-success", "export-failure"].contains(initialPage ?? "") { await export.prepare() }
    }
  }
  private func prepare() {
    savedName = nil; saveFailed = false
    Task { await export.prepare() }
  }
}

private struct DiagnosticDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  let data: Data
  init(url: URL?) { data = url.flatMap { try? Data(contentsOf: $0) } ?? Data() }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DiagnosticLogSettings: View {
  @ObservedObject var model: BackupModel
  var body: some View {
    Form {
      if let snapshot = model.storage {
        Section {
          Picker("logs_retention", selection: Binding(get: { snapshot.settings.log_days }, set: { value in
            var settings = snapshot.settings; settings.log_days = value
            Task { await model.saveStorage(settings, performMaintenance: false) }
          })) {
            ForEach(Array(Set([1, 7, 14, 30, 90, snapshot.settings.log_days])).sorted(), id: \.self) {
              Text(String(format: NSLocalizedString("logs_days", comment: ""), $0)).tag($0)
            }
          }.accessibilityIdentifier("settings.log_days")
          Picker("logs_limit", selection: Binding(get: { snapshot.settings.log_limit }, set: { value in
            var settings = snapshot.settings; settings.log_limit = value
            Task { await model.saveStorage(settings, performMaintenance: false) }
          })) {
            ForEach(Array(Set([1000, 5000, 10000, 20000, snapshot.settings.log_limit])).sorted(), id: \.self) {
              Text($0.formatted()).tag($0)
            }
          }.accessibilityIdentifier("settings.log_limit")
        } footer: { Text("diagnostics_retention_consequence") }
        .disabled(model.savingStorage)
      } else if model.storageError == nil { DuckLoadingState("log_settings_loading") }
      if model.storageError != nil {
        Section {
          Text("storage_settings_unavailable")
          Button("retry_task") { Task { await model.refreshStorage() } }
        }
      }
      if let error = model.storageSettingsError {
        Section { DuckNotice(title: LocalizedStringKey(error), tone: .failure) }
      }
    }
    .formStyle(.grouped).labeledContentStyle(DuckPreferenceRowStyle())
    .navigationTitle("settings_log_retention")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .task { await model.refreshStorage() }
  }
}

enum DiagnosticFilter: String, CaseIterable, Identifiable {
  case all, problems, transfers, storage
  var id: String { rawValue }
  func includes(_ entry: ActivityEntry) -> Bool {
    switch self {
    case .all: true
    case .problems: Self.problemsCodes.contains(entry.code) || entry.code.hasSuffix("_failed") || entry.code.hasSuffix("_rejected") || entry.code.hasSuffix("_blocked")
    case .transfers: entry.job_id != nil || Self.transfersCodes.contains(entry.code)
    case .storage: Self.storageCodes.contains(entry.code) || entry.code.hasPrefix("cache_")
    }
  }
  private static let problemsCodes: Set<String> = ["network", "capacity", "busy", "authentication", "integrity", "source_unavailable", "unsupported", "invalid_input", "conflict", "not_found", "storage", "internal", "history_unavailable", "low_space", "local_free_space", "local_cache_budget", "processing_low_space", "request_waiting_network"]
  private static let transfersCodes: Set<String> = ["transfer_received", "transfer_queued", "backup_paused", "backup_resumed", "publication_complete", "publication_failed", "upload_submitted", "commit_submitted", "manifest_submitted", "bundle_submitted", "request_completed", "request_failed", "request_waiting_network", "dispatch_waiting"]
  private static let storageCodes: Set<String> = ["storage", "capacity", "low_space", "local_free_space", "local_cache_budget", "processing_low_space", "preparation_storage_blocked", "source_location_restored"]
}

struct ActivityLogView: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var journal = ActivityLogModel()
  @State private var visibleID: Int64?
  @State private var detail: ActivityEntry?
  @State private var showDetail = false
  @State private var holdLatest = false
  @State private var openedInitial = false
  @State private var search = ""
  @State private var filter: DiagnosticFilter = .all
  var embedded = false
  var initialDetail = false
  private var entries: [ActivityEntry] {
    journal.entries.filter { filter.includes($0) && (search.isEmpty || ($0.title + " " + $0.json).localizedStandardContains(search)) }
  }
  private var dayGroups: [(Date, [ActivityEntry])] {
    let grouped = Dictionary(grouping: entries, by: \.day)
    return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
  }
  var body: some View {
    VStack(spacing: 0) {
      Picker("diagnostics_filter", selection: $filter) {
        ForEach(DiagnosticFilter.allCases) { Text(LocalizedStringKey("diagnostics_filter_" + $0.rawValue)).tag($0) }
      }.pickerStyle(.segmented).padding(DuckSpacing.medium).accessibilityIdentifier("activity.filter")
      if journal.failed && !journal.entries.isEmpty {
        HStack {
          Text("logs_load_failed").foregroundStyle(.secondary)
          Spacer()
          Button("retry_task") { Task { await refresh() } }.accessibilityIdentifier("activity.retry")
        }.padding(.horizontal, DuckSpacing.medium).padding(.bottom, DuckSpacing.small)
      }
      if journal.pendingCount > 0 {
        Button(String(format: NSLocalizedString("logs_new_count", comment: ""), journal.pendingCount)) {
          holdLatest = false; journal.showLatest(); visibleID = journal.entries.first?.id
        }.accessibilityIdentifier("activity.latest").padding(.bottom, DuckSpacing.small)
      }
      if journal.entries.isEmpty {
        if journal.loaded || journal.failed {
          ContentUnavailableView {
            Label(journal.failed ? "logs_load_failed" : "logs_empty", systemImage: journal.failed ? "exclamationmark.circle" : "list.bullet.rectangle")
          } description: { Text(journal.failed ? "diagnostics_read_failed_note" : "diagnostics_empty_note") } actions: {
            Button("retry_task") { Task { await refresh() } }.accessibilityIdentifier("activity.retry")
          }.accessibilityIdentifier("activity.empty")
        } else { DuckLoadingState("logs_loading") }
      } else if entries.isEmpty {
        ContentUnavailableView.search(text: search)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(dayGroups, id: \.0) { day, rows in
              Section {
                ForEach(rows) { entry in
                  Button { holdLatest = true; detail = entry; showDetail = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DuckSpacing.small) {
                      Text(entry.time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                      VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
                        Text(entry.title).font(.body).foregroundStyle(.primary)
                        if entry.title != entry.code { Text(entry.code).font(.caption.monospaced()).foregroundStyle(.secondary) }
                      }.frame(maxWidth: .infinity, alignment: .leading)
                      Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, DuckSpacing.small + DuckSpacing.xSmall).contentShape(Rectangle())
                  }.buttonStyle(.plain).id(entry.id).accessibilityIdentifier("activity.entry.\(entry.id)")
                  Divider()
                }
              } header: {
                Text(day == .distantPast ? NSLocalizedString("task_order_unknown", comment: "") : day.formatted(date: .abbreviated, time: .omitted))
                  .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.vertical, DuckSpacing.small).background(DuckRole.background)
              }
            }
          }.padding(.horizontal, DuckSpacing.medium).scrollTargetLayout()
        }.scrollPosition(id: $visibleID, anchor: .top).transaction { $0.animation = nil }
      }
    }
    .background(DuckRole.background)
    .navigationTitle("activity_log")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .searchable(text: $search, prompt: "diagnostics_search")
    .navigationDestination(isPresented: $showDetail) { if let detail { ActivityLogDetail(entry: detail) } }
    .onChange(of: search) { _, _ in visibleID = nil }
    .onChange(of: filter) { _, _ in visibleID = nil }
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      while !Task.isCancelled {
        await refresh()
        if initialDetail, !openedInitial, let entry = journal.entries.first {
          openedInitial = true; holdLatest = true; detail = entry; showDetail = true
        }
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
      }
    }
  }
  private func refresh() async {
    _ = await journal.refresh { !holdLatest && !showDetail && (visibleID == nil || visibleID == journal.entries.first?.id) }
  }
}

/// Immutable entry snapshot: decoding retains unknown fields as well as typed fields.
struct ActivityLogDetail: View {
  let entry: ActivityEntry
  @State private var copied: String?
  var body: some View {
    Form {
      Section {
        Text(entry.title).font(.headline)
      }
      Section {
        ForEach(entry.fields, id: \.0) { key, value in
          HStack(alignment: .top, spacing: DuckSpacing.small) {
            VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
              Text(key).font(.caption.monospaced()).foregroundStyle(.secondary)
              Text(value).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { copy(value, key: key) } label: {
              Label(copied == key ? "diagnostics_copied" : "diagnostics_copy", systemImage: copied == key ? "checkmark" : "doc.on.doc")
            }.labelStyle(.iconOnly).buttonStyle(.borderless).accessibilityIdentifier("activity.copy.\(key)")
          }.padding(.vertical, DuckSpacing.xSmall)
        }
      }
    }.formStyle(.grouped).navigationTitle("apple_log_detail_title")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(copied == "all" ? "diagnostics_copied" : "diagnostics_copy_all") { copy(entry.json, key: "all") }
          .accessibilityIdentifier("activity.copy_all")
      }
    }.accessibilityIdentifier("activity.detail")
  }
  private func copy(_ value: String, key: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    #else
    UIPasteboard.general.string = value
    #endif
    copied = key
  }
}

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

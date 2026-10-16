import Foundation
import Photos
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

struct StorageSettings: Codable {
  var cache_budget_bytes: UInt64
  var receiver_budget_bytes: UInt64
  var min_free_bytes: UInt64
  var auto_reclaim: Bool
  var log_days: Int
  var log_limit: Int
}
struct StorageSnapshot: Decodable {
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
          .sheet(isPresented: $logs) { ActivityLogView() }
      }
    }
  }
  private func bytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
  }
}
struct ActivityEntry: Decodable, Identifiable, Equatable {
  let id: Int64
  let timestamp: Int64
  let code: String
  let job_id: Int64?
  let bytes: Int64?
  let context: ActivityContext?
}
struct ActivityContext: Decodable, Equatable {
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
private struct ActivityContextFields: View {
  let context: ActivityContext
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      #if os(iOS)
      iosContextFields
      #else
      VStack(alignment: .leading, spacing: 5) {
        if let execution = context.execution {
          Text(LocalizedStringKey("logs_execution_" + execution))
        }
        if let reason = context.reason {
          Text(LocalizedStringKey("logs_reason_" + reason))
        }
        if let queued = context.queued, let running = context.running,
          let waiting = context.waiting, let failed = context.failed {
          Text(String(format: NSLocalizedString("logs_queue_counts", comment: ""), queued, running, waiting, failed))
        }
        if let pending = context.pending_imports, let discovery = context.discovery_pending {
          Text(String(format: NSLocalizedString("logs_import_counts", comment: ""), pending, discovery))
        }
        if let paused = context.paused {
          Text(LocalizedStringKey(paused ? "logs_backup_paused" : "logs_backup_enabled"))
        }
        if let active = context.active_requests {
          Text(String(format: NSLocalizedString("logs_active_requests", comment: ""), active))
        }
        if let phase = context.phase { Text(LocalizedStringKey("logs_phase_" + phase)) }
        if let sent = context.bytes_sent, let expected = context.bytes_expected {
          Text(String(format: NSLocalizedString("logs_request_bytes", comment: ""),
            ByteCountFormatter.string(fromByteCount: sent, countStyle: .file),
            ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)))
        }
        if let retry = context.next_retry_at {
          Text("logs_next_retry") + Text(" ") + Text(Date(timeIntervalSince1970: Double(retry)), format: .dateTime)
        }
        if let status = context.http_status, status > 0 {
          Text(String(format: NSLocalizedString("logs_http_status", comment: ""), status))
        }
        if let error = context.system_error {
          Text(String(format: NSLocalizedString("logs_system_error", comment: ""), error))
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      #endif
    }
    #if os(iOS)
      .foregroundStyle(DuckColors.textSecondary)
    #else
      .font(.caption).foregroundStyle(.secondary)
    #endif
  }
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  private var iosContextFields: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
      if let v = context.execution { contextField("apple_log_execution", NSLocalizedString("logs_execution_" + v, comment: "")) }
      if let v = context.reason { contextField("apple_log_reason", NSLocalizedString("logs_reason_" + v, comment: "")) }
      if let q = context.queued, let r = context.running, let w = context.waiting, let f = context.failed {
        contextField("apple_log_queue", String(format: NSLocalizedString("logs_queue_counts", comment: ""), q, r, w, f))
      }
      if let p = context.pending_imports, let d = context.discovery_pending {
        contextField("apple_log_originals", String(format: NSLocalizedString("logs_import_counts", comment: ""), p, d))
      }
      if let v = context.paused { contextField("apple_log_dispatch", NSLocalizedString(v ? "logs_backup_paused" : "logs_backup_enabled", comment: "")) }
      if let v = context.active_requests { contextField("apple_log_requests", String(v)) }
      if let v = context.phase { contextField("apple_log_phase", NSLocalizedString("logs_phase_" + v, comment: "")) }
      if let s = context.bytes_sent, let e = context.bytes_expected {
        contextField("apple_log_bytes", String(format: NSLocalizedString("logs_request_bytes", comment: ""), ByteCountFormatter.string(fromByteCount: s, countStyle: .file), ByteCountFormatter.string(fromByteCount: e, countStyle: .file)))
      }
      if let v = context.next_retry_at { contextField("logs_next_retry", Date(timeIntervalSince1970: Double(v)).formatted(date: .abbreviated, time: .standard)) }
      if let v = context.http_status, v > 0 { contextField("apple_log_http", String(v)) }
      if let v = context.system_error { contextField("apple_log_system_error", String(v)) }
    }
  }
  private func contextField(_ title: LocalizedStringKey, _ value: String) -> some View {
    GridRow(alignment: .top) {
      Text(title).iosPrototypeText(size: bodySize).frame(minWidth: 80, alignment: .leading)
      Text(value).iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.text).fixedSize(horizontal: false, vertical: true)
    }
  }
  #endif

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
        merged = (update.entries + merged).sorted { $0.id > $1.id }
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

private struct ActivityLogExportSheet: View {
  @StateObject private var export = ActivityLogExportModel()
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    DuckSheetLayout(title: "logs_export", busy: export.preparing,
      error: export.failed ? NSLocalizedString("logs_export_failed", comment: "") : nil) {
      Text("logs_privacy_note").foregroundStyle(.secondary)
      if export.preparing {
        DuckLoadingState("logs_export_preparing").accessibilityIdentifier("activity.export_preparing")
      } else if export.url != nil {
        DuckNotice(title: "logs_export_ready")
        Text("logs_export_share_note").foregroundStyle(.secondary)
      }
    } actions: {
      #if os(iOS)
      if export.preparing {
        Button {} label: { Text("logs_export_preparing").frame(maxWidth: .infinity) }
          .iosPrototypeAction(primary: true).disabled(true).accessibilityIdentifier("activity.export_preparing_action")
      } else {
      Button { dismiss() } label: { Text("close").frame(maxWidth: .infinity) }
        .iosPrototypeAction().disabled(export.preparing)
      if let url = export.url {
        ShareLink(item: ActivityLogReport(url: url), preview: SharePreview("BackupDuck-diagnostics.json")) {
          Text("logs_export_share").frame(maxWidth: .infinity)
        }.iosPrototypeAction(primary: true).accessibilityIdentifier("activity.export_share")
      } else {
        Button { Task { await export.prepare() } } label: { Text("retry_task").frame(maxWidth: .infinity) }
          .iosPrototypeAction(primary: true).disabled(export.preparing)
          .accessibilityIdentifier("activity.export_retry")
      }
      }
      #else
      Button("close") { dismiss() }.disabled(export.preparing).duckAction()
      if let url = export.url {
        ShareLink(item: ActivityLogReport(url: url), preview: SharePreview("BackupDuck-diagnostics.json")) {
          Text("logs_export_share")
        }.duckPrimaryAction().accessibilityIdentifier("activity.export_share")
      } else {
        Button("retry_task") { Task { await export.prepare() } }
          .duckPrimaryAction().disabled(export.preparing)
          .accessibilityIdentifier("activity.export_retry")
      }
      #endif
    }.task { await export.prepare() }
  }
}

struct ActivityLogView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var journal = ActivityLogModel()
  @State private var visibleID: Int64?
  @State private var detail: ActivityEntry?
  @State private var holdLatest = false
  @State private var exportPresented = false
  var embedded = false
  var body: some View {
    Group {
      if embedded { logContent }
      else {
        #if os(iOS)
        iosLogModal
        #else
        NavigationStack {
          logContent.padding().navigationTitle("activity_log")
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("settings_done") { dismiss() }.accessibilityIdentifier("activity.done")
              }
              ToolbarItem(placement: .cancellationAction) {
                Button("logs_export") { exportPresented = true }
                  .disabled(!journal.loaded).accessibilityIdentifier("activity.export")
              }
            }
        }
        #endif
      }
    }
    .sheet(isPresented: $exportPresented) { ActivityLogExportSheet() }
    .sheet(item: $detail) { ActivityLogDetail(entry: $0) }
    #if os(macOS)
      .frame(width: embedded ? nil : 680, height: embedded ? nil : 540)
    #endif
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      while !Task.isCancelled {
        let follow = await journal.refresh {
          !holdLatest && detail == nil && (visibleID == nil || visibleID == journal.entries.first?.id)
        }
        guard !Task.isCancelled else { return }
        #if os(iOS)
        // Preserve the opening privacy/live preamble. Explicit Show Latest or
        // already-following entries may still advance to a new first record.
        if follow, visibleID != nil { visibleID = journal.entries.first?.id }
        #else
        if follow { visibleID = journal.entries.first?.id }
        #endif
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
      }
    }
  }
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .caption) private var captionSize = 13
  @Environment(\.dynamicTypeSize) private var logTextSize
  private var iosLogModal: some View {
    VStack(spacing: 0) {
      DuckSheetHeader(title: "activity_log",titleIdentifier: "activity.title",
        closeIdentifier: "activity.close",close: { dismiss() })
      Divider()
      VStack(alignment: .leading, spacing: 12) {
          if !logTextSize.isAccessibilitySize {
            Text("logs_privacy_note").iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.textSecondary)
          }
          DuckActions {
            Text(LocalizedStringKey(journal.failed ? "logs_load_retrying" : "logs_live"))
              .iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
            Spacer(minLength: 0)
            Button {
              holdLatest = false; journal.showLatest(); visibleID = journal.entries.first?.id
            } label: {
              Text(journal.pendingCount > 0
                ? String(format: NSLocalizedString("logs_new_count", comment: ""), journal.pendingCount)
                : NSLocalizedString("logs_latest", comment: ""))
            }.iosPrototypeAction().accessibilityIdentifier("activity.latest")
          }
      }.padding(20)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          if logTextSize.isAccessibilitySize {
            Text("logs_privacy_note").iosPrototypeText(size: bodySize).foregroundStyle(DuckColors.textSecondary)
          }
          if journal.entries.isEmpty {
            if journal.failed { DuckNotice(title: "logs_load_retrying", tone: .failure) }
            else if journal.loaded { DuckNotice(title: "logs_empty").accessibilityIdentifier("activity.empty") }
            else { DuckLoadingState("logs_loading").accessibilityIdentifier("activity.loading") }
          }
          ForEach(journal.entries) { entry in
            Button { holdLatest = true; detail = entry } label: {
              HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                  Text(activityTime(entry)).iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
                  Text(LocalizedStringKey("event_" + entry.code)).iosPrototypeText(size: bodySize, weight: .semibold)
                  if let job = entry.job_id { Text(String(format: NSLocalizedString("logs_job_id", comment: ""), job)).iosPrototypeText(size: captionSize).foregroundStyle(DuckColors.textSecondary) }
                  if let amount = entry.bytes { Text(ByteCountFormatter.string(fromByteCount: amount, countStyle: .file)).iosPrototypeText(size: captionSize).foregroundStyle(DuckColors.textSecondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(DuckColors.textSecondary)
              }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(DuckColors.border, lineWidth: 1))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(DuckColors.text).id(entry.id)
              .accessibilityIdentifier("activity.details").accessibilityHint(Text("apple_log_details_open"))
          }
          if journal.failed && !journal.entries.isEmpty { DuckNotice(title: "logs_load_retrying", tone: .failure) }
        }.padding(.horizontal, 20).scrollTargetLayout()
      }.contentMargins(.vertical, 20, for: .scrollContent)
        .scrollPosition(id: $visibleID, anchor: .top).transaction { $0.animation = nil }
      Divider()
      DuckActions {
        Button { exportPresented = true } label: { Text("logs_export").frame(maxWidth: .infinity) }
          .iosPrototypeAction().disabled(!journal.loaded).accessibilityIdentifier("activity.export")
        Button { dismiss() } label: { Text("settings_done").frame(maxWidth: .infinity) }
          .iosPrototypeAction().accessibilityIdentifier("activity.done")
      }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)
    }.background(DuckColors.surface).foregroundStyle(DuckColors.text).presentationDetents([.large]).presentationDragIndicator(.visible)
      .presentationCornerRadius(22).iosPrototypeSheetHost().symbolVariant(.none)
  }
  #endif
  private var logContent: some View {
      VStack(alignment: .leading, spacing: 12) {
        if embedded {
          HStack {
            Text("activity_log").font(.system(size: 26, weight: .semibold))
            Spacer()
            Button("logs_export") { exportPresented = true }.duckSecondaryAction()
              .disabled(!journal.loaded).accessibilityIdentifier("activity.export")
          }
        }
        Text("logs_privacy_note").font(.footnote).foregroundStyle(.secondary)
        DuckActions {
          Label(LocalizedStringKey(journal.failed ? "logs_load_retrying" : "logs_live"),
            systemImage: journal.failed ? "exclamationmark.circle" : "dot.radiowaves.left.and.right")
            .foregroundStyle(journal.failed ? Color.orange : Color.secondary)
          Button {
            holdLatest = false; journal.showLatest()
            visibleID = journal.entries.first?.id
          } label: {
            Text(journal.pendingCount > 0
              ? String(format: NSLocalizedString("logs_new_count", comment: ""), journal.pendingCount)
              : NSLocalizedString("logs_latest", comment: ""))
          }.buttonStyle(.borderless).accessibilityIdentifier("activity.latest")
        }.font(.caption)
        if journal.entries.isEmpty {
          if journal.failed {
            DuckNotice(title: "logs_load_retrying", tone: .failure, symbol: "exclamationmark.circle")
          } else if journal.loaded {
            Text("logs_empty").foregroundStyle(.secondary).accessibilityIdentifier("activity.empty")
          } else {
            DuckLoadingState("logs_loading").accessibilityIdentifier("activity.loading")
          }
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(journal.entries) { entry in
              Button { holdLatest = true; detail = entry } label: {
                HStack(alignment: .center, spacing: 12) {
                  VStack(alignment: .leading, spacing: 5) {
                    Text(activityTime(entry)).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
                    Text(LocalizedStringKey("event_" + entry.code)).font(.system(size: 14, weight: .semibold))
                    if let job = entry.job_id { Text(String(format: NSLocalizedString("logs_job_id", comment: ""), job)).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary) }
                    if let amount = entry.bytes { Text(ByteCountFormatter.string(fromByteCount: amount, countStyle: .file)).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary) }
                  }.frame(maxWidth: .infinity, alignment: .leading)
                  Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
                }.padding(.vertical, 12).contentShape(Rectangle())
              }.buttonStyle(.plain).foregroundStyle(DuckColors.text).id(entry.id)
                .accessibilityIdentifier("activity.details").accessibilityHint(Text("apple_log_details_open"))
              Divider()
            }
          }.scrollTargetLayout()
        }.scrollPosition(id: $visibleID, anchor: .top)
          .transaction { $0.animation = nil }
      }
  }

  private func activityTime(_ entry: ActivityEntry) -> String {
    entry.timestamp > 0 ? Date(timeIntervalSince1970: Double(entry.timestamp)).formatted(date: .abbreviated, time: .standard)
      : NSLocalizedString("task_order_unknown", comment: "")
  }
}

/// The selected entry is an immutable snapshot; live polling must not replace
/// the record the user is currently reading or expand a long-list row.
struct ActivityLogDetail: View {
  let entry: ActivityEntry
  @Environment(\.dismiss) private var dismiss
  #if os(iOS)
  @ScaledMetric(relativeTo: .body) private var bodySize = 16
  @ScaledMetric(relativeTo: .caption) private var captionSize = 13
  #endif
  var body: some View {
    DuckSheetLayout(title: "apple_log_detail_title") {
      #if os(iOS)
      Text(LocalizedStringKey("event_" + entry.code)).iosPrototypeText(size: bodySize, weight: .semibold)
      #else
      Text(LocalizedStringKey("event_" + entry.code)).font(.system(size: 16, weight: .semibold))
      #endif
      VStack(alignment: .leading, spacing: 12) {
        LabeledContent("apple_log_time", value: entry.timestamp > 0 ? Date(timeIntervalSince1970: Double(entry.timestamp)).formatted(date: .abbreviated, time: .standard) : NSLocalizedString("task_order_unknown", comment: ""))
        LabeledContent("apple_log_code", value: entry.code)
        if let job = entry.job_id { Text(String(format: NSLocalizedString("logs_job_id", comment: ""), job)) }
        if let amount = entry.bytes { Text(ByteCountFormatter.string(fromByteCount: amount, countStyle: .file)) }
      }
      #if os(iOS)
      .iosPrototypeText(size: bodySize)
      #else
      .font(.system(size: 14))
      #endif
      if let context = entry.context { ActivityContextFields(context: context) }
      #if os(iOS)
      Text("logs_privacy_note").iosPrototypeText(size: captionSize, lineHeight: 1.6).foregroundStyle(DuckColors.textSecondary)
      #else
      Text("logs_privacy_note").font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
      #endif
    } actions: {
      #if os(iOS)
      Button { dismiss() } label: { Text("settings_done").frame(maxWidth: .infinity) }.iosPrototypeAction()
        .accessibilityIdentifier("activity.detail.done")
      #else
      Button("settings_done") { dismiss() }.duckSecondaryAction().keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("activity.detail.done")
      #endif
    }.textSelection(.enabled).accessibilityElement(children: .contain)
      .accessibilityIdentifier("activity.detail")
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

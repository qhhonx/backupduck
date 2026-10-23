import SwiftUI

/// Desktop presentation of the shared immediate-save storage contract.
/// Values and operations still belong to BackupModel; no second settings store.
struct MacStoragePanel: View {
  @ObservedObject var model: BackupModel
  @State private var reclaimSheet = false
  @State private var retryingStorage = false
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      MacThumbnailCacheGroup()
      if let snapshot = model.storage {
          MacPreferenceGroup(title: "ios_cache_preparation_group", note: "ios_cache_budget_note") {
            fact("storage_cache_used", bytes(snapshot.used_bytes))
            choice("storage_cache_budget", value: Int(snapshot.settings.cache_budget_bytes >> 30), options: [1,2,5,10,20,50], id: "settings.cache_budget", label: { "\($0) GB" }, first: false) { settings, v in settings.cache_budget_bytes = UInt64(v) << 30 }
          }
          if let reason = snapshot.reason, ["local_free_space","local_cache_budget"].contains(reason) {
            DuckNotice(title: LocalizedStringKey("error_" + reason), tone: .attention).accessibilityIdentifier("settings.cache_limit_reason")
          }
          MacPreferenceGroup(title: "ios_cache_reserve_group", note: "ios_cache_reserve_note") {
            fact("storage_disk_free", bytes(snapshot.free_bytes))
            choice("storage_min_free", value: Int(snapshot.settings.min_free_bytes >> 30), options: [1,2,5,10], id: "settings.min_free", label: { "\($0) GB" }, first: false) { settings, v in settings.min_free_bytes = UInt64(v) << 30 }
          }
          MacPreferenceGroup(title: "ios_cache_reclaim_group", note: "mac_storage_reclaim_note") {
            MacPreferenceRow(title: "storage_auto_reclaim") {
              Toggle("storage_auto_reclaim", isOn: Binding(get: { snapshot.settings.auto_reclaim }, set: { value in var settings=snapshot.settings; settings.auto_reclaim=value; Task { await model.saveStorage(settings) } }))
                .labelsHidden().toggleStyle(.switch).disabled(model.savingStorage || !model.ready)
            }
            Button { reclaimSheet = true } label: {
              MacPreferenceRow(title: "storage_reclaim_now", first: false) { MacPreferenceValue(value: nil, width: 168) }
            }.buttonStyle(.plain).disabled(model.reclaimingCache || model.savingStorage || !model.ready)
              .accessibilityIdentifier("settings.reclaim_cache")
          }
      } else if model.storageError == nil, !model.ready, let message = model.message,
        message != NSLocalizedString("pairing_unlock_wait", comment: ""), !retryingStorage {
        DuckNotice(title: "storage_settings_unavailable", tone: .failure)
        Button("retry_task") {
          retryingStorage = true
          Task { await model.open(); await model.refreshStorage(); retryingStorage = false }
        }.duckSecondaryAction()
      } else if model.storageError == nil { DuckLoadingState("cache_settings_loading") }
      if let error=model.storageError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure)
        Button("retry_task") { Task { await model.refreshStorage() } }.duckSecondaryAction()
      }
      if let error=model.storageSettingsError { DuckNotice(title: LocalizedStringKey(error), tone: .failure).accessibilityIdentifier("settings.storage_save_error") }

    }.task(id: model.ready) { await model.refreshStorage() }
      .sheet(isPresented: $reclaimSheet) { MacCacheReclaimSheet(model: model) }
  }
  private func fact(_ title: LocalizedStringKey, _ value: String) -> some View {
    MacPreferenceRow(title: title) { valueColumn(value, adjustable: false) }
  }
  private func choice(_ title: String, value: Int, options: [Int], id: String, label: @escaping (Int)->String, first: Bool = true,
    update: @escaping (inout StorageSettings,Int)->Void) -> some View {
    MacPreferenceRow(title: LocalizedStringKey(title), first: first) {
      MacPreferenceMenu(title: NSLocalizedString(title, comment: ""), selection: Binding(get: { value }, set: { v in
        guard var settings=model.storage?.settings else {return}
        update(&settings,v); Task { await model.saveStorage(settings) }
      }), options: options, label: label, enabled: !model.savingStorage && model.ready, identifier: id)
        .frame(width: 168, height: DuckPreferenceMetrics.desktopControlHeight)
    }
  }

  private func valueColumn(_ value: String, adjustable: Bool) -> some View {
    MacPreferenceValue(value: value, indicator: adjustable ? "chevron.up.chevron.down" : nil, width: 168)
  }

  /// Binary units, matching the budgets they are compared with (1 GB = 1024 MB).
  private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory) }
}

/// Browsing thumbnails, as on iPhone: usage, limit and clearing. On the Mac the
/// decoded thumbnail tables are the whole cache.
private struct MacThumbnailCacheGroup: View {
  @State private var used = MacThumbnailTables.usage
  @State private var budget = MacThumbnailTables.budgetMB
  @State private var clearing = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      MacPreferenceGroup(title: "library_thumbnail_cache", note: "library_thumbnail_cache_help") {
        MacPreferenceRow(title: "library_thumbnail_used") {
          MacPreferenceValue(value: bytes(used), indicator: nil, width: 168).accessibilityIdentifier("settings.thumbnail_used")
        }
        MacPreferenceRow(title: "storage_cache_budget", first: false) {
          MacPreferenceMenu(title: NSLocalizedString("storage_cache_budget", comment: ""), selection: Binding(get: { budget }, set: { value in
            budget = value; MacThumbnailTables.setBudget(value); used = MacThumbnailTables.usage
          }), options: [256, 512, 1024, 2048, 4096], label: { bytes($0 << 20) }, identifier: "settings.thumbnail_budget")
            .frame(width: 168, height: DuckPreferenceMetrics.desktopControlHeight)
        }
        Button {
          clearing = true
          Task { await MacThumbnailTables.clear(); used = MacThumbnailTables.usage; clearing = false }
        } label: {
          MacPreferenceRow(title: "library_thumbnail_clear", first: false) {
            if clearing { ProgressView().controlSize(.small).accessibilityLabel(Text("library_thumbnail_clearing")) }
            else { MacPreferenceValue(value: nil, width: 168) }
          }
        }.buttonStyle(.plain).disabled(clearing)
          .accessibilityValue(Text(clearing ? "library_thumbnail_clearing" : ""))
          .accessibilityIdentifier("settings.thumbnail_clear")
      }
    }.task { used = MacThumbnailTables.usage; budget = MacThumbnailTables.budgetMB }
  }
  private func bytes(_ value: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory) }
}

struct MacConcurrencyPanel: View {
  @ObservedObject var model: BackupModel
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      MacPreferenceRow(title: "transfer_concurrency") {
        MacPreferenceMenu(title: NSLocalizedString("transfer_concurrency", comment: ""),
          selection: Binding(get: { model.concurrentUploads }, set: { value in Task { await model.setConcurrentUploads(value) } }),
          options: Array(1...4), label: { $0.formatted() }, enabled: model.ready && !model.savingConcurrency,
          identifier: "settings.transfer_concurrency").frame(width: 168, height: DuckPreferenceMetrics.desktopControlHeight)
      }
      Text("mac_transfer_concurrency_note").font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)

      if let error=model.concurrencyError { DuckNotice(title: LocalizedStringKey(error), tone: .failure).accessibilityIdentifier("settings.transfer_concurrency_error") }
    }
  }
}

private struct MacCacheReclaimSheet: View {
  @ObservedObject var model: BackupModel
  @Environment(\.dismiss) private var dismiss
  @State private var started = false
  private var busy: Bool { !started || model.reclaimingCache }
  var body: some View {
    DuckSheetLayout(title: "storage_reclaim_now", busy: busy, error: model.cacheReclaimError) {
      Text("storage_reclaim_check_help").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
      if busy { ProgressView("storage_reclaim_running").frame(maxWidth: .infinity, minHeight: 100) }
      else if let result = model.cacheReclaimResult { DuckNotice(title: LocalizedStringKey(result)).accessibilityIdentifier("settings.reclaim_result") }
    } actions: {
      if model.cacheReclaimError != nil {
        Button("retry_task") { Task { await model.reclaimCache(reportResult: true) } }.duckPrimaryAction().disabled(busy)
      }
      Button("settings_done") { dismiss() }.duckSecondaryAction().disabled(busy)
    }.task { started = true; await model.reclaimCache(reportResult: true) }
  }
}

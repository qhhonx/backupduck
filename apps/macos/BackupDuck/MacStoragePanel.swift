import SwiftUI

/// Desktop presentation of the shared immediate-save storage contract.
/// Values and operations still belong to BackupModel; no second settings store.
struct MacStoragePanel: View {
  @ObservedObject var model: BackupModel
  var logs = false
  @State private var reclaimSheet = false
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if let snapshot = model.storage {
        if logs {
          MacPreferenceGroup(title: "settings_log_retention", note: "mac_fidelity_logs_only_note") {
          choice("logs_retention", value: snapshot.settings.log_days, options: [1,7,14,30,90], id: "settings.log_days", label: { $0 == 1 && Bundle.main.preferredLocalizations.first == "en" ? "1 day" : String(format: NSLocalizedString("logs_days", comment: ""), $0) }) { settings, v in settings.log_days = v }
          choice("logs_limit", value: snapshot.settings.log_limit, options: [1000,5000,10000,20000], id: "settings.log_limit", label: { String($0) }, first: false) { settings, v in settings.log_limit = v }
          }
        } else {
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
        }
      } else if model.storageError == nil { ProgressView("storage_loading") }
      if let error=model.storageError {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure)
        Button("retry_task") { Task { await model.refreshStorage() } }.duckSecondaryAction()
      }
      if let error=model.storageSettingsError { DuckNotice(title: LocalizedStringKey(error), tone: .failure).accessibilityIdentifier("settings.storage_save_error") }

    }.task { await model.refreshStorage() }
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

  private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) }
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

import SwiftUI

/// Mac presentation follows the desktop reference while the shared browser
/// continues to own paging, stable jobs and real protocol filtering.
struct MacTransferPage: View {
  @ObservedObject var model: BackupModel
  var sourceOptions: [(String, String)] = []
  @StateObject private var browser = TaskBrowserModel()
  @State private var filter: String
  @State private var sourceFilter = ""
  @State private var guide = false
  @State private var historySettings = false
  @State private var visibleJobID: String?
  @AppStorage("transferSortChoicesV2") private var savedOrders = "{}"
  private let filters = TransferUserCategories.keys
  private var sourcePage: Bool { filter == "preparing" || filter == "scanned" }
  init(model: BackupModel, filter: String = "all", sourceOptions: [(String, String)] = []) {
    self.model = model; self.sourceOptions = sourceOptions; _filter = State(initialValue: TransferUserCategories.initial(filter))
  }
  private var ordering: TransferOrdering {
    get { (try? JSONDecoder().decode([String: TransferOrdering].self, from: Data(savedOrders.utf8)))?[filter] ?? .recommended(filter) }
    nonmutating set {
      var choices = (try? JSONDecoder().decode([String: TransferOrdering].self, from: Data(savedOrders.utf8))) ?? [:]
      choices[filter] = newValue
      if let data = try? JSONEncoder().encode(choices) { savedOrders = String(decoding: data, as: UTF8.self) }
    }
  }
  private var queryID: String { "\(filter)|\(sourceFilter)|\(ordering.sort)|\(ordering.descending)|\(model.queueRevision)|\(model.pairing?.receiverID ?? "")" }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if sourcePage {
        Text(LocalizedStringKey(filter == "scanned" ? "task_title_scanned" : "state_preparing"))
          .font(.system(size: 20, weight: .semibold)).accessibilityIdentifier("transfers.title")
      }
      HStack(spacing: 12) {
        Text(String(format: NSLocalizedString("task_status_count", comment: ""), sourcePage ? model.transferCount(for: filter) : (browser.summary?.count(for: filter) ?? model.transferCount(for: filter))))
          .font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary).monospacedDigit()
          .accessibilityIdentifier("transfers.count")
        Spacer(minLength: 8)
        TransferSortControl(ordering: Binding(get: { ordering }, set: { ordering = $0 }), filter: filter)
          .duckSecondaryAction()
        Button { guide = true } label: {
          HStack(spacing: 4) { Text("design_status_guide"); Image(systemName: "chevron.right").font(.caption) }
        }.buttonStyle(.plain).foregroundStyle(DuckColors.action).frame(minHeight: 44)
          .accessibilityIdentifier("transfers.guide")
      }
      if !sourcePage {
        HStack(spacing: 12) {
          Picker("task_filter", selection: $filter) {
            ForEach(filters, id: \.self) { value in Text(LocalizedStringKey(filterKey(value))).tag(value) }
          }.duckDesktopSegments().accessibilityIdentifier("transfers.filter")
          if !sourceOptions.isEmpty {
            Picker("task_source_filter", selection: $sourceFilter) {
              Text("task_source_all").tag("")
              ForEach(sourceOptions, id: \.0) { Text($0.1).tag($0.0) }
            }.labelsHidden().pickerStyle(.menu).fixedSize().accessibilityIdentifier("transfers.source")
          }
        }
      }
      if sourcePage {
        if filter == "scanned" {
          Button("mac_library_existing") { historySettings = true }.duckSecondaryAction()
        }
        SourceBrowser(model: model, history: filter == "scanned", descending: ordering.descending, sort: ordering.sort)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            if browser.loading && browser.items.isEmpty && !browser.hasSnapshot {
              DuckNotice(title: "mac_fidelity_tasks_loading").accessibilityIdentifier("transfers.loading")
            } else if browser.failed {
              DuckNotice(title: "tasks_load_failed", tone: .failure)
              Button("retry_task") { Task { await refresh() } }.duckSecondaryAction()
            } else if browser.items.isEmpty {
              DuckNotice(title: "tasks_empty_filtered").accessibilityIdentifier("transfers.empty")
            }
            ForEach(browser.items) { item in
              BackupTaskRow(item: item, model: model, activityLabel: ordering.sort == "activity" ? "apple_transfer_activity_time" : nil)
              Divider()
            }
            if browser.hasMore {
              Button("load_more_tasks") { Task { await browser.loadMore() } }.duckSecondaryAction()
                .padding(.vertical, 20).disabled(browser.loading)
            }
          }.scrollTargetLayout().allowsHitTesting(!browser.loading)
        }.scrollPosition(id: $visibleJobID, anchor: .top)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .task(id: queryID) { if !["preparing", "scanned"].contains(filter) { await refresh() } }
      .sheet(isPresented: $guide) { TransferStatusGuide() }
      .sheet(isPresented: $historySettings) {
        DuckSheetLayout(title: "mac_library_existing", busy: model.changingHistory, error: model.historyError) {
          HistoricalImportSettings(model: model)
        } actions: {
          Button("settings_done") { historySettings = false }.duckSecondaryAction().disabled(model.changingHistory)
        }
      }
  }
  private func filterKey(_ value: String) -> String {
    switch value {
    case "all": "design_filter_all"
    case "active": "design_filter_active"
    case "attention": "design_filter_attention"
    case "saved": "design_filter_saved"
    case "scanned": "task_title_scanned"
    default: "state_" + value
    }
  }
  private func refresh() async {
    let target = model.pairing?.receiverID
    await browser.refresh(filter: filter, receiver: target, descending: ordering.descending, sort: ordering.sort,
      sourceFilter: sourceFilter.isEmpty ? nil : sourceFilter)
    guard !Task.isCancelled, sourceFilter.isEmpty, target == model.pairing?.receiverID,
      !browser.failed, let summary = browser.summary else { return }
    model.summary = summary
  }
}

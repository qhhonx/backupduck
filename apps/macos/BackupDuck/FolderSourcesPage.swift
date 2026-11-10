import AppKit
import SwiftUI

@MainActor final class MacFolderToolbarActions: ObservableObject {
  let backupAction = SelectionBackupAction()
  @Published private(set) var addRequest = 0
  private var consumedAddRequest = 0
  func requestAdd() { addRequest &+= 1 }
  func consumeAddRequest() -> Bool {
    guard consumedAddRequest != addRequest else { return false }
    consumedAddRequest = addRequest
    return true
  }
  var choose: () -> Void = {}
  var backUp: () -> Void = {}
  var settings: (String) -> Void = { _ in }
}

/// F0–F9: a photo browser; management lives in Settings › Folders.
struct FolderSourcesPage: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  var settings: (String) -> Void = { _ in }
  @ObservedObject private var browser: FolderBrowser
  private var active: Bool
  private var viewerOpen: Bool
  private var subtitleChanged: (String) -> Void
  private var visibleRange: MacVisibleRange?
  @ObservedObject private var toolbarActions: MacFolderToolbarActions
  @ObservedObject private var backupAction: SelectionBackupAction
  @ObservedObject private var gridSize = MacGridSize.shared
  @MainActor init(folders: FolderSources, backup: BackupModel, active: Bool = true, viewerOpen: Bool = false, subtitleChanged: @escaping (String) -> Void = { _ in }, visibleRange: MacVisibleRange? = nil, toolbarActions: MacFolderToolbarActions? = nil, settings: @escaping (String) -> Void = { _ in }) {
    self.folders = folders; self.backup = backup; self.settings = settings; self.browser = folders.browser; self.active = active; self.viewerOpen = viewerOpen; self.subtitleChanged = subtitleChanged; self.visibleRange = visibleRange
    let actions = toolbarActions ?? MacFolderToolbarActions()
    self.toolbarActions = actions
    self.backupAction = actions.backupAction
  }
  @State private var adding: URL?
  @State private var stopping: FolderSource?
  @StateObject private var navigation = MacLibraryNavigation()
  // The page is split into stages so each modifier chain type-checks on its own.
  var body: some View {
    commands
    .onAppear {
      toolbarActions.choose = choose
      toolbarActions.backUp = backUpSelected
      toolbarActions.settings = settings
    }
    .onChange(of: toolbarActions.addRequest, initial: true) { _, _ in
      if toolbarActions.consumeAddRequest() { choose() }
    }
    .onReceive(navigation.visibleRange.$title) { title in
      if browser.visibleRange.title != title { browser.visibleRange.title = title }
      if visibleRange?.title != title { visibleRange?.title = title }
    }
    .onChange(of: browser.key) { _, _ in
      navigation.visibleRange.title = browser.visibleRange.title
    }
    .onChange(of: folders.sources.map(\.id)) { _, ids in
      if case .folder(let id) = browser.scope, !ids.contains(id) { browser.scope = .all }
    }
    .onChange(of: browser.selection) { _, ids in if !ids.isEmpty { backupAction.selectionChanged() } }
    .confirmationDialog("selection_backup_repeat_title", isPresented: $backupAction.confirmingRepeat, titleVisibility: .visible) {
      Button("selection_backup_repeat_action") { Task { await backupAction.confirm() } }
      Button("cancel", role: .cancel) { backupAction.cancel() }
    } message: { Text("selection_backup_repeat_note") }
    .alert("selection_backup_failed_title", isPresented: backupFailed) {
      Button("settings_done") { backupAction.error = nil }
    } message: { Text(backupAction.error ?? "") }
    .task {
      if !browser.configured {
        browser.configured = true; browser.filter = folders.initialFilter
        if folders.initialFilter != .all { browser.scope = .all; browser.filter = folders.initialFilter }
        openInitialSheet()
      }
    }
    .task(id: reloadKey) {
      if !browser.search.isEmpty { try? await Task.sleep(for: .milliseconds(200)); if Task.isCancelled { return } }
      await folders.refreshFacts(); await browser.reload(folders)
    }
    .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
      if let adding { AddFolderSheet(url: adding, folders: folders, backup: backup, added: { id in browser.scope = .folder(id) }) { self.adding = nil } }
    }
    .background {
      FolderStopAlert(source: $stopping, folders: folders) { source in
        Task { _ = await folders.remove(source.id) }
      }.frame(width: 0, height: 0)
    }
  }
  private var content: some View {
    Group {
      if folders.loadFailed {
        ContentUnavailableView {
          Label("mac_folder_settings_unavailable", systemImage: "exclamationmark.folder")
        } actions: { Button("retry_task") { Task { await folders.open() } } }
      } else if !folders.loaded && !folders.isPreview {
        ProgressView("folders_counting").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if folders.sources.isEmpty {
        ContentUnavailableView {
          DuckIllustration(pose: .empty, size: 112)
          Text("folders_empty_title")
        } description: { Text("folders_empty_note") } actions: {
          Button("folders_add_button", action: choose).duckPrimaryButton()
        }
        .duckOpticalCenter()
      } else {
        VStack(spacing: 0) {
          if let error = browser.error ?? folders.error {
            HStack {
              Label(error, systemImage: "exclamationmark.triangle")
              Spacer()
              Button("retry_task") { Task { await browser.reload(folders); await folders.refreshFacts() } }
            }.font(.callout).padding(DuckSpacing.small)
          }
          Group {
            // The native collection stays mounted across scope/loading changes.
            // Membership readiness belongs to its data source, not view identity.
            MacFolderGrid(folders: folders, browser: browser, navigation: navigation, columns: gridSize.ordinaryColumns, active: active, resize: { gridSize.ordinaryColumns = $0 }, settings: settings, stop: { stopping = $0 })
              .allowsHitTesting(!backupAction.busy && browser.resultKey == browser.key)
              .overlay {
            switch browser.contentState {
            case .loading:
              ProgressView("folders_counting").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .filterEmpty:
              MacGridFilterEmpty(clear: browser.clearFilters)
            case .empty:
              if case .folder(let id) = browser.scope, let source = folders.sources.first(where: { $0.id == id }), folderScopeHasNotice(folders.facts[id]) {
                ScrollView { FolderScopeNotice(folders: folders, source: source).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DuckSpacing.medium) }
              } else { ContentUnavailableView("folders_no_photos", systemImage: "photo") }
            case .photos, .failed:
              EmptyView()
            }
              }
          }
        }
      }
    }
  }
  private var chrome: some View {
    content
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onChange(of: hidesBrowsing ? "" : subtitle, initial: true) { _, value in subtitleChanged(value) }
  }
  private var commands: some View {
    chrome
    .background {
      if active && !viewerOpen && !hidesBrowsing {
        MacToolbarSearch(text: $browser.search, presented: $browser.searchExpanded, prompt: "folders_search")
      }
    }
    .focusedSceneValue(\.historyZoom, active && !viewerOpen && !hidesBrowsing ? MacHistoryZoomActions(
      smaller: { gridSize.ordinaryColumns = min(9, MacLibraryDensity.step(gridSize.ordinaryColumns, by: 1)) },
      larger: { gridSize.ordinaryColumns = MacLibraryDensity.step(gridSize.ordinaryColumns, by: -1) }, canShrink: gridSize.ordinaryColumns < 9, canGrow: gridSize.ordinaryColumns > 3) : nil)
    .focusedSceneValue(\.folderCommands, !active || viewerOpen ? nil : FolderCommandActions(add: choose, search: beginSearch, filter: { browser.filter = $0 }, backUp: backUpSelected, canBackUp: !selectedPhotos.isEmpty && !backupAction.busy && !backupAction.added))
  }
  private func beginSearch() { browser.searchExpanded = true }
  /// Empty and unavailable pages show only their title (A10): there is nothing to
  /// view, filter or search, and the empty state offers Add Folder itself.
  private var hidesBrowsing: Bool { folders.loadFailed || folders.sources.isEmpty }
  private var backupFailed: Binding<Bool> {
    Binding(get: { backupAction.error != nil }, set: { if !$0 { backupAction.error = nil } })
  }
  /// Reloads the grid when the sources, filters, index, queue or receiver change.
  private var reloadKey: String {
    let sources = folders.sources.map(\.id).joined(separator: ",")
    let receiver = backup.pairing?.receiverID ?? ""
    return [sources, "\(browser.key)", "\(folders.indexRevision)", "\(backup.queueRevision)",
            "\(folders.revision)", receiver].joined(separator: "|")
  }
  private var subtitle: String {
    browser.selection.isEmpty ? "" : String(format: NSLocalizedString("grid_selected_count", comment: ""), browser.selection.count)
  }
  private var selectedPhotos: [FolderPhoto] {
    browser.sections.flatMap(\.photos).filter { browser.selection.contains($0.id) }
  }
  private func backUpSelected() {
    let photos = selectedPhotos
    let tokens = Set(photos.map(\.id))
    guard !photos.isEmpty, !backupAction.busy, !backupAction.confirmingRepeat else { return }
    let receiver = backup.pairing?.receiverID
    Task {
      var repeats = Set<String>()
      await backupAction.request(prepare: {
        guard let receiver, backup.pairing?.receiverID == receiver else {
          throw NSError(domain: "FolderSelection", code: 1,
            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("apple_selected_receiver_needed", comment: "")])
        }
        repeats = try await folders.selectedBackupRepeatSources(photos, receiver: receiver)
        guard backup.pairing?.receiverID == receiver else {
          throw NSError(domain: "FolderSelection", code: 1,
            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("apple_selected_receiver_needed", comment: "")])
        }
        return !repeats.isEmpty
      }, submit: {
        guard let receiver, backup.pairing?.receiverID == receiver else {
          folders.error = NSLocalizedString("apple_selected_receiver_needed", comment: "")
          return false
        }
        guard await folders.backUp(photos, receiver: receiver, repeatSources: repeats) else { return false }
        browser.completeSelection(tokens)
        Task { await browser.reload(folders) }
        return true
      }, failure: {
        let reason = folders.error
        folders.error = nil
        return reason
      })
    }
  }
  private func choose() {
    guard !folders.isPreview else { adding = URL(fileURLWithPath: "/Synthetic/\(folders.sources.first.map { folders.displayName($0) } ?? "Camera Exports")"); return }
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
    panel.allowsMultipleSelection = false; panel.prompt = NSLocalizedString("folder_choose", comment: "")
    panel.begin { result in if result == .OK { adding = panel.url } }
  }
  private func openInitialSheet() {
    if folders.initialSheet == "add" { choose() }
    if folders.initialSheet == "stop" { stopping = folders.sources.first }
  }
}
struct FolderFilterMenu: View {
  @ObservedObject var browser: FolderBrowser
  var body: some View {
    MacGridFilterMenu(shows: MacGridFilterMenu.backupViews, selected: browser.filter.rawValue,
      choose: { if let view = LibraryBackupView(rawValue: $0) { browser.filter = view } },
      type: $browser.type, identifier: "folders.filter")
  }
}

struct MacFolderToolbar: ToolbarContent {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  @ObservedObject var browser: FolderBrowser
  @ObservedObject var actions: MacFolderToolbarActions
  @ObservedObject var information: MacGridToolbarState
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      FolderFilterMenu(browser: browser)
      Button(action: { actions.choose() }) { Label("folders_add", systemImage: "folder.badge.plus") }
        .labelStyle(.iconOnly).help("folders_add")
        .disabled(!backup.ready || folders.loadFailed)
      Menu {
        if let source = contextualSource {
          if let facts = folders.facts[source.id], facts.not_backed_up > 0 || facts.needs_you > 0 {
            Button("folders_back_up_remaining") { Task { await folders.start(source.id) } }
              .disabled(!folders.canBackUp || source.pendingControl != nil)
          }
          Button("folder_reveal") { folders.reveal(source) }.disabled(folders.isPreview)
          Button("folders_settings") { actions.settings(source.id) }
        }
      } label: { Label("folder_more", systemImage: "ellipsis") }
        .menuIndicator(.hidden).help("folder_more").disabled(contextualSource == nil)
      MacGridInfoButton(state: information)
      MacSelectionBackupControl(action: actions.backupAction, count: browser.selection.count,
        identifier: "folders.backup_selected", submit: { actions.backUp() })
    }
  }
  private var contextualSource: FolderSource? {
    if case .folder(let id) = browser.scope { return folders.sources.first { $0.id == id } }
    guard browser.scope == .all else { return nil }
    let ids = Set(browser.sections.flatMap(\.photos).filter { browser.selection.contains($0.id) }.map(\.folder_id))
    return ids.count == 1 ? folders.sources.first { ids.contains($0.id) } : nil
  }
}


/// The in-flow summary and pinned parent share exact text, menu and wrapping.
struct FolderIdentityRow: View {
  @ObservedObject var folders: FolderSources
  let source: FolderSource
  var settings: (String) -> Void
  var stop: (FolderSource) -> Void
  private var facts: FolderFacts? { folders.facts[source.id] }
  var body: some View {
    HStack(alignment: .top) {
      Text(folders.displayName(source)).font(.headline).fixedSize(horizontal: false, vertical: true)
        .opacity(facts?.available == false ? 0.5 : 1)
      Spacer()
        Menu {
          if let facts, facts.not_backed_up > 0 || facts.needs_you > 0 {
            Button("folders_back_up_remaining") { Task { await folders.start(source.id) } }.disabled(!folders.canBackUp || source.pendingControl != nil)
          }
          Button("folder_reveal") { folders.reveal(source) }.disabled(folders.isPreview)
          Button("folders_settings") { settings(source.id) }
          Divider()
          Button("folders_stop_title") { stop(source) }.disabled(source.pendingControl != nil && source.pendingControl?.action != "remove")
        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          .accessibilityLabel(Text("folder_more"))
    }.padding(.vertical, DuckSpacing.small)
      .frame(minHeight: DuckSettingsMetrics.rowHeight, alignment: .center)
  }
}

struct FolderSectionHeader: View {
  @ObservedObject var folders: FolderSources
  let source: FolderSource
  var settings: (String) -> Void
  var stop: (FolderSource) -> Void
  var identityAccessibilityHidden = false
  @State private var explaining = false
  private var facts: FolderFacts? { folders.facts[source.id] }
  var body: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
      FolderIdentityRow(folders: folders, source: source, settings: settings, stop: stop)
        .accessibilityHidden(identityAccessibilityHidden)
      VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
        Text(folders.location(source)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Text(folderSentence(facts)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }.opacity(facts?.available == false ? 0.5 : 1)
      if let facts, !facts.unsupported_by_kind.isEmpty {
        HStack(spacing: DuckSpacing.xSmall) {
          Text(String(format: NSLocalizedString("folders_unsupported", comment: ""), facts.unsupported_by_kind.values.reduce(0, +)))
          Button { explaining = true } label: { Image(systemName: "info.circle") }.buttonStyle(.plain)
            .accessibilityLabel(Text("folders_unsupported_info"))
            .popover(isPresented: $explaining) {
              VStack(alignment: .leading, spacing: DuckSpacing.small) {
                Text("folders_unsupported_note")
                Text(facts.unsupported_by_kind.sorted { $0.key < $1.key }.map { "\($0.key.uppercased()): \($0.value)" }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                Button("folder_reveal") { folders.reveal(source) }.disabled(folders.isPreview)
              }.padding(DuckSpacing.medium).frame(width: 320)
            }
        }.font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.bottom, DuckSpacing.medium)
  }
}

@MainActor func stopTitle(_ source: FolderSource?, folders: FolderSources) -> String {
  String(format: NSLocalizedString("folders_stop_question", comment: ""), source.map { ($0.lastKnownPath.map { $0 as NSString })?.lastPathComponent ?? $0.name } ?? "")
}

/// A5: AppKit owns the alert and its prominent, Return-activated default action.
struct FolderStopAlert: NSViewRepresentable {
  @Binding var source: FolderSource?
  let folders: FolderSources
  var confirm: (FolderSource) -> Void

  @MainActor static func makeAlert(_ source: FolderSource, folders: FolderSources) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = stopTitle(source, folders: folders)
    alert.informativeText = NSLocalizedString("folders_stop_note", comment: "")
    let stop = alert.addButton(withTitle: NSLocalizedString("folders_stop", comment: ""))
    stop.keyEquivalent = "\r"
    alert.window.defaultButtonCell = stop.cell as? NSButtonCell
    let cancel = alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
    cancel.keyEquivalent = "\u{1b}"
    return alert
  }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> Anchor {
    let view = Anchor()
    view.windowChanged = { [weak coordinator = context.coordinator] window in coordinator?.schedule(window) }
    return view
  }
  func updateNSView(_ view: Anchor, context: Context) {
    context.coordinator.parent = self
    if let window = view.window { context.coordinator.schedule(window) }
  }
  static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) {
    view.windowChanged = nil
    coordinator.dismiss()
  }

  final class Anchor: NSView {
    var windowChanged: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let window { windowChanged?(window) }
    }
  }

  @MainActor final class Coordinator {
    var parent: FolderStopAlert
    private var alert: NSAlert?
    private var scheduled = false
    init(_ parent: FolderStopAlert) { self.parent = parent }

    func schedule(_ window: NSWindow) {
      guard !scheduled else { return }
      scheduled = true
      // Presentation and binding writes must happen outside SwiftUI's update.
      DispatchQueue.main.async { [weak self, weak window] in
        guard let self else { return }
        self.scheduled = false
        guard let window else { return }
        self.present(in: window)
      }
    }
    private func present(in window: NSWindow) {
      guard let source = parent.source else { dismiss(); return }
      guard alert == nil, window.attachedSheet == nil else { return }
      let alert = FolderStopAlert.makeAlert(source, folders: parent.folders)
      self.alert = alert
      alert.beginSheetModal(for: window) { [weak self] response in
        guard let self else { return }
        self.alert = nil
        self.parent.source = nil
        if response == .alertFirstButtonReturn { self.parent.confirm(source) }
      }
    }
    func dismiss() {
      guard let alert, let window = alert.window.sheetParent else { return }
      window.endSheet(alert.window, returnCode: .cancel)
    }
  }
}

struct AddFolderSheet: View {
  let url: URL
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  var added: (String) -> Void = { _ in }
  var close: () -> Void
  @State private var existing = true
  @State private var adding = false
  @State private var count: FolderSummary?
  @State private var error: String?
  var body: some View {
    DuckSheetLayout(title: LocalizedStringKey(String(format: NSLocalizedString("folders_add_named", comment: ""), url.lastPathComponent)), busy: adding, error: error, desktopFitsContent: true, form: true) {
      if let count {
        Text(String(format: NSLocalizedString("folders_count_size", comment: ""), folderMediaCount(count.media_kinds ?? .init(photos: count.files)), ByteCountFormatter.string(fromByteCount: Int64(clamping: count.bytes), countStyle: .file))).foregroundStyle(.secondary)
      } else { Text(error == nil ? "folders_counting" : "folders_count_failed").foregroundStyle(.secondary) }
      Picker("folders_add_decision", selection: $existing) {
        Text("folders_include_existing").tag(true)
        Text("folders_only_new").tag(false)
      }.pickerStyle(.radioGroup).disabled(adding)
      Text("folders_add_note").font(.callout).foregroundStyle(.secondary)
    } actions: {
      Button("cancel", action: close).keyboardShortcut(.cancelAction).disabled(adding)
      Button("folders_add_confirm") {
        adding = true
        Task {
          do {
            let previous = Set(folders.sources.map(\.id))
            if !folders.isPreview { try await folders.add(url, automatic: backup.autoBackup, existing: existing) }
            if let source = folders.sources.first(where: { !previous.contains($0.id) }) ?? (folders.isPreview ? folders.sources.first : nil) { added(source.id) }
            close()
          } catch { self.error = error.localizedDescription }
          adding = false
        }
      }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(adding || count == nil)
    }
    .task { await countFolder() }
  }
  private func countFolder() async {
    if folders.isPreview { count = folders.previewSummary ?? FolderSummary(files: 248, bytes: 1_240_000_000, unsupported: 12, scanning: false); return }
    _ = url.startAccessingSecurityScopedResource()
    defer { url.stopAccessingSecurityScopedResource() }
    do {
      _ = try await Bridge.call(["op": "folder", "command": ["action": "preview_begin", "root": url.path]])
      while !Task.isCancelled {
        let result = try JSONDecoder().decode(FolderSummary.self, from: await Bridge.call(["op": "folder", "command": ["action": "preview_step"]]))
        if !result.scanning { count = result; break }
        try await Task.sleep(for: .milliseconds(10))
      }
    } catch {
      if !Task.isCancelled { self.error = NSLocalizedString("folders_scan_failed", comment: "") }
    }
    _ = try? await Bridge.call(["op": "folder", "command": ["action": "preview_cancel"]])
  }
}

/// Present the system confirmation directly from its native control action.
/// No bookmark resolution or folder work runs before the sheet is attached.
struct FolderStopButton: NSViewRepresentable {
  let source: FolderSource
  let folders: FolderSources
  var confirm: (FolderSource) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(title: NSLocalizedString("folders_stop_button", comment: ""),
      target: context.coordinator, action: #selector(Coordinator.present(_:)))
    button.bezelStyle = .rounded; button.controlSize = .small
    button.setAccessibilityIdentifier("folders.stop")
    return button
  }
  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.parent = self; button.isEnabled = source.pendingControl == nil
  }
  @MainActor final class Coordinator: NSObject {
    var parent: FolderStopButton
    private var alert: NSAlert?
    init(_ parent: FolderStopButton) { self.parent = parent }
    @objc func present(_ button: NSButton) {
      guard let window = button.window, window.attachedSheet == nil, alert == nil else { return }
      let source = parent.source
      let alert = FolderStopAlert.makeAlert(source, folders: parent.folders)
      self.alert = alert
      alert.beginSheetModal(for: window) { [weak self] response in
        guard let self else { return }
        self.alert = nil
        if response == .alertFirstButtonReturn { self.parent.confirm(source) }
      }
    }
  }
}

func folderScopeHasNotice(_ facts: FolderFacts?) -> Bool {
  guard let facts else { return false }
  return facts.available == false || facts.needs_you > 0 || !facts.unsupported_by_kind.isEmpty
}

struct FolderScopeNotice: View {
  @ObservedObject var folders: FolderSources
  let source: FolderSource
  @State private var explaining = false
  var body: some View {
    if let facts = folders.facts[source.id] {
      VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
        if facts.available == false || facts.needs_you > 0 {
          Text(folderSentence(facts)).font(.callout).foregroundStyle(.secondary)
        }
        if !facts.unsupported_by_kind.isEmpty {
          HStack(spacing: DuckSpacing.xSmall) {
            Text(String(format: NSLocalizedString("folders_unsupported", comment: ""), facts.unsupported_by_kind.values.reduce(0, +)))
            Button { explaining = true } label: { Image(systemName: "info.circle") }.buttonStyle(.plain)
              .accessibilityLabel(Text("folders_unsupported_info"))
              .popover(isPresented: $explaining) {
                VStack(alignment: .leading, spacing: DuckSpacing.small) {
                  Text("folders_unsupported_note")
                  Text(facts.unsupported_by_kind.sorted { $0.key < $1.key }.map { "\($0.key.uppercased()): \($0.value)" }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                  Button("folder_reveal") { folders.reveal(source) }.disabled(folders.isPreview)
                }.padding(DuckSpacing.medium).frame(width: 320)
              }
          }.font(.caption).foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DuckSpacing.medium)
    }
  }
}

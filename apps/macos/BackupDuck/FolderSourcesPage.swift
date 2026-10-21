import AppKit
import SwiftUI

/// F0–F9: a photo browser; management lives in Settings › Folders.
struct FolderSourcesPage: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  var settings: (String) -> Void = { _ in }
  @ObservedObject private var browser: FolderBrowser
  init(folders: FolderSources, backup: BackupModel, settings: @escaping (String) -> Void = { _ in }) {
    self.folders = folders; self.backup = backup; self.settings = settings; self.browser = folders.browser
  }
  @State private var adding: URL?
  @State private var stopping: FolderSource?
  @State private var searching = false
  var body: some View {
    Group {
      if folders.loadFailed {
        ContentUnavailableView {
          Label("mac_folder_settings_unavailable", systemImage: "exclamationmark.folder")
        } actions: { Button("retry_task") { Task { await folders.open() } } }
      } else if !folders.loaded && !folders.isPreview {
        ProgressView("folders_counting").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if folders.sources.isEmpty {
        ContentUnavailableView {
          DuckBrandMark(size: DuckSpacing.xxLarge)
          Text("folders_empty_title")
        } description: { Text("folders_empty_note") } actions: { Button("folders_add", action: choose) }
      } else {
        VStack(spacing: 0) {
          if let error = browser.error ?? folders.error {
            HStack {
              Label(error, systemImage: "exclamationmark.triangle")
              Spacer()
              Button("retry_task") { Task { await browser.reload(folders); await folders.refreshFacts() } }
            }.font(.callout).padding(DuckSpacing.small)
          }
          if browser.loading { ProgressView("folders_counting").frame(maxWidth: .infinity, maxHeight: .infinity) }
          else if browser.sections.allSatisfy({ $0.photos.isEmpty }) && (!browser.search.isEmpty || browser.filter != .all) {
            ContentUnavailableView.search(text: browser.search)
          } else {
            MacFolderGrid(folders: folders, browser: browser, settings: settings, stop: { stopping = $0 })
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        FolderViewMenu(browser: browser)
        if browser.filter != .all {
          Button { browser.filter = .all } label: { Image(systemName: "xmark") }
            .help("folders_clear_filter").accessibilityLabel(Text("folders_clear_filter"))
        }
      }
      ToolbarItemGroup(placement: .primaryAction) {
        Button(action: choose) { Label("folders_add", systemImage: "folder.badge.plus") }
          .disabled(!backup.ready || folders.loadFailed)
        FolderSearchField(text: $browser.search, focus: $searching)
          .frame(idealWidth: 180, maxWidth: 220)
        if !browser.selected.isEmpty {
          Button("folders_back_up_selected") {
            Task { if await folders.backUp(browser.selected) { await browser.reload(folders) } }
          }.buttonStyle(.borderedProminent).disabled(backup.pairing == nil)
        }
      }
    }
    .focusedSceneValue(\.folderCommands, FolderCommandActions(add: choose, search: { searching = true }, view: { browser.byFolder = $0 }, filter: { browser.filter = $0 }, backUp: { Task { if await folders.backUp(browser.selected) { await browser.reload(folders) } } }, canBackUp: !browser.selected.isEmpty && backup.pairing != nil))
    .task {
      if !browser.configured {
        browser.configured = true; browser.filter = folders.initialFilter
        if folders.initialFilter != .all { browser.byFolder = false }
        openInitialSheet()
      }
    }
    .task(id: "\(folders.sources.map(\.id).joined(separator: ","))|\(browser.key)|\(folders.indexRevision)|\(backup.queueRevision)|\(folders.revision)|\(backup.pairing?.receiverID ?? "")") {
      if !browser.search.isEmpty { try? await Task.sleep(for: .milliseconds(200)); if Task.isCancelled { return } }
      await folders.refreshFacts(); await browser.reload(folders)
    }
    .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
      if let adding { AddFolderSheet(url: adding, folders: folders, backup: backup) { self.adding = nil } }
    }
    .background {
      FolderStopAlert(source: $stopping, folders: folders) { source in
        Task { _ = await folders.remove(source.id) }
      }.frame(width: 0, height: 0)
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
struct FolderViewMenu: View {
  @ObservedObject var browser: FolderBrowser
  var body: some View {
    Menu {
      Picker("folders_show", selection: $browser.byFolder) {
        Text("folders_by_folder").tag(true)
        Text("mac_library_all_photos").tag(false)
      }.pickerStyle(.inline)
      Divider()
      Picker("library_view_section", selection: $browser.filter) {
        ForEach(LibraryBackupView.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
      }.pickerStyle(.inline)
    } label: {
      Label(browser.filter == .all ? LocalizedStringKey("folders_view") : LocalizedStringKey(browser.filter.title), systemImage: "line.3.horizontal.decrease")
    }.help("folders_view")
  }
}

struct FolderSectionHeader: View {
  @ObservedObject var folders: FolderSources
  let source: FolderSource
  var settings: (String) -> Void
  var stop: (FolderSource) -> Void
  @State private var explaining = false
  private var facts: FolderFacts? { folders.facts[source.id] }
  var body: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
          Text(folders.displayName(source)).font(.headline)
          Text(folders.location(source)).font(.callout).foregroundStyle(.secondary)
          Text(folderSentence(facts)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.opacity(facts?.available == false ? 0.5 : 1)
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
      }
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
    }.padding(.horizontal, DuckSpacing.large).padding(.vertical, DuckSpacing.medium)
  }
}

@MainActor func stopTitle(_ source: FolderSource?, folders: FolderSources) -> String {
  String(format: NSLocalizedString("folders_stop_question", comment: ""), source.map { folders.displayName($0) } ?? "")
}

/// A5: AppKit owns the alert and its prominent, Return-activated default action.
struct FolderStopAlert: NSViewRepresentable {
  @Binding var source: FolderSource?
  let folders: FolderSources
  var confirm: (FolderSource) -> Void

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
      let alert = NSAlert()
      alert.alertStyle = .informational
      alert.messageText = stopTitle(source, folders: parent.folders)
      alert.informativeText = NSLocalizedString("folders_stop_note", comment: "")
      let stop = alert.addButton(withTitle: NSLocalizedString("folders_stop", comment: ""))
      stop.keyEquivalent = "\r"
      alert.window.defaultButtonCell = stop.cell as? NSButtonCell
      let cancel = alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
      cancel.keyEquivalent = "\u{1b}"
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
  var close: () -> Void
  @State private var existing = true
  @State private var adding = false
  @State private var count: FolderSummary?
  @State private var error: String?
  var body: some View {
    DuckSheetLayout(title: LocalizedStringKey(String(format: NSLocalizedString("folders_add_named", comment: ""), url.lastPathComponent)), busy: adding, error: error, desktopFitsContent: true, form: true) {
      if let count {
        Text(String(format: NSLocalizedString("folders_count_size", comment: ""), count.files, ByteCountFormatter.string(fromByteCount: Int64(clamping: count.bytes), countStyle: .file))).foregroundStyle(.secondary)
      } else { Text("folders_counting").foregroundStyle(.secondary) }
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
            if !folders.isPreview { try await folders.add(url, automatic: backup.autoBackup, existing: existing) }
            close()
          } catch { self.error = error.localizedDescription }
          adding = false
        }
      }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(adding)
    }
    .task { await countFolder() }
  }
  private func countFolder() async {
    if folders.isPreview { count = FolderSummary(files: 248, bytes: 1_240_000_000, unsupported: 12, scanning: false); return }
    _ = url.startAccessingSecurityScopedResource()
    defer { url.stopAccessingSecurityScopedResource() }
    do {
      _ = try await Bridge.call(["op": "folder", "command": ["action": "preview_begin", "root": url.path]])
      while !Task.isCancelled {
        let result = try JSONDecoder().decode(FolderSummary.self, from: await Bridge.call(["op": "folder", "command": ["action": "preview_step"]]))
        if !result.scanning { count = result; break }
        try await Task.sleep(for: .milliseconds(10))
      }
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    _ = try? await Bridge.call(["op": "folder", "command": ["action": "preview_cancel"]])
  }
}

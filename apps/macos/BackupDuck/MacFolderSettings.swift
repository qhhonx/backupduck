import AppKit
import SwiftUI

/// A6: canonical management destination, reached from Settings or a folder's
/// menu. A folder's page opens below the list inside the Settings pane.
struct MacFolderSettings: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  @Environment(\.duckSettingsNavigator) private var navigator
  @State private var adding: URL?
  var body: some View {
    Group {
      if folders.loadFailed {
        ContentUnavailableView {
          Label("mac_folder_settings_unavailable", systemImage: "exclamationmark.folder")
        } actions: { Button("retry_task") { Task { await folders.open() } } }
        .duckOpticalCenter()
      } else if !folders.loaded && !folders.isPreview {
        ProgressView("folders_counting").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if folders.sources.isEmpty {
        // The same empty state as the Folders position.
        ContentUnavailableView {
          DuckIllustration(pose: .empty, size: 112)
          Text("folders_empty_title")
        } description: { Text("folders_empty_note") } actions: {
          Button("folders_add_button", action: choose).duckPrimaryButton().disabled(!backup.ready)
        }
        .duckOpticalCenter()
      } else {
        Form {
          Section {
            ForEach(folders.sources) { source in
              Button { open(source.id) } label: {
                HStack {
                  Image(systemName: "folder").foregroundStyle(.secondary)
                  VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
                    Text(folders.displayName(source)).foregroundStyle(.primary)
                    Text(folders.location(source)).font(.callout).foregroundStyle(.secondary)
                    Text(folderSentence(folders.facts[source.id])).font(.callout).foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, minHeight: DuckSettingsMetrics.rowHeight, alignment: .leading)
                  .fixedSize(horizontal: false, vertical: true)
                  .contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          } footer: {
            VStack(alignment: .leading, spacing: DuckSpacing.small) {
              Button("folders_add_button", action: choose).disabled(!backup.ready)
              Text("folders_settings_note").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, DuckSpacing.small)
          }
        }.formStyle(.grouped)
      }
    }
    .overlay(alignment: .bottom) {
      if let error = folders.error { Text(error).font(.callout).padding(DuckSpacing.medium).background(DuckRole.elevatedSurface) }
    }
    .task(id: "\(folders.indexRevision)|\(backup.queueRevision)|\(backup.pairing?.receiverID ?? "")") { await folders.refreshFacts() }
    .task {
      // A start route (a folder's menu or the catalog) is consumed once.
      if let id = folders.initialSettingsFolder { folders.initialSettingsFolder = nil; open(id) }
      if folders.initialSheet == "add" { choose() }
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckFolderSettings"))) { note in
      if let id = note.object as? String { folders.initialSettingsFolder = nil; open(id) }
    }
    .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
      if let adding { AddFolderSheet(url: adding, folders: folders, backup: backup) { self.adding = nil } }
    }
  }
  private func open(_ id: String) {
    guard let navigator, let source = folders.sources.first(where: { $0.id == id }) else { return }
    navigator.open(DuckSettingsPage(title: Text(verbatim: folders.displayName(source)),
      content: AnyView(MacFolderDetail(folders: folders, backup: backup, sourceID: id))))
  }
  private func choose() {
    if folders.isPreview { adding = URL(fileURLWithPath: "/Synthetic/\(folders.sources.first.map { folders.displayName($0) } ?? "Camera Exports")"); return }
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.begin { result in if result == .OK { adding = panel.url } }
  }
}

/// One folder: where it is, what was backed up, its rules and stopping.
private struct MacFolderDetail: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  let sourceID: String
  @Environment(\.duckSettingsNavigator) private var navigator
  @State private var rules: FolderSource?
  @State private var stopping: FolderSource?
  var body: some View {
    Group {
      if let selected = folders.sources.first(where: { $0.id == sourceID }) {
        Form {
          Section {
            HStack(alignment: .top, spacing: DuckSpacing.small) {
              Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
              VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
                Text(folders.displayName(selected)).font(.headline)
                Text(folders.location(selected)).foregroundStyle(.secondary)
                Text(folderSentence(folders.facts[selected.id])).font(.callout).foregroundStyle(.secondary)
              }
            }.padding(.vertical, DuckSpacing.xSmall)
          }
          Section {
            LabeledContent("folders_location") {
              Button("folder_reveal") { folders.reveal(selected) }.controlSize(.small)
            }
            LabeledContent("folders_file_rules") {
              HStack(spacing: DuckSpacing.small) {
                Text(ruleSummary(selected)).foregroundStyle(.secondary)
                Button("settings_edit") { rules = selected }.controlSize(.small)
              }
            }
          }
          if selected.pendingControl != nil && !folders.recoveringControls.contains(selected.id) {
            Section {
              actionRow("mac_folder_recover_operation") {
                Task { if await folders.recoverPendingControl(selected.id), !folders.sources.contains(where: { $0.id == selected.id }) { navigator?.back() } }
              }
            }
          }
          Section {
            LabeledContent("settings_auto_backup") {
              FolderStopButton(source: selected, folders: folders) { source in
                Task { if await folders.remove(source.id) { navigator?.back() } }
              }.fixedSize()
            }
          }
        }.formStyle(.grouped)
      } else { Color.clear }
    }
    .task {
      if folders.initialSheet == "rules" { rules = folders.sources.first { $0.id == sourceID } }
      if folders.initialSheet == "stop" { stopping = folders.sources.first { $0.id == sourceID } }
    }
    .sheet(item: $rules) { source in FolderRulesSheet(folders: folders, source: source) { rules = nil } }
    .background {
      FolderStopAlert(source: $stopping, folders: folders) { source in
        Task { if await folders.remove(source.id) { navigator?.back() } }
      }.frame(width: 0, height: 0)
    }
  }
  private func ruleSummary(_ source: FolderSource) -> String {
    let included = source.includePatterns ?? []
    let excluded = source.excludePatterns ?? []
    if included.isEmpty && excluded.isEmpty { return NSLocalizedString("folders_rules_all", comment: "") }
    return String(format: NSLocalizedString("folders_rules_count", comment: ""), included.count, excluded.count)
  }
  private func actionRow(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    HStack {
      Button(title, action: action).buttonStyle(.bordered).controlSize(.small)
      Spacer(minLength: 0)
    }.frame(minHeight: DuckSettingsMetrics.formContentHeight)
  }
}

struct FolderRulesSheet: View {
  @ObservedObject var folders: FolderSources
  let source: FolderSource
  var close: () -> Void
  @State private var include: [String]
  @State private var exclude: [String]
  @State private var saving = false
  @State private var error: String?
  init(folders: FolderSources, source: FolderSource, close: @escaping () -> Void) {
    self.folders = folders; self.source = source; self.close = close
    _include = State(initialValue: source.includePatterns ?? [])
    _exclude = State(initialValue: source.excludePatterns ?? [])
  }
  var body: some View {
    DuckSheetLayout(title: "folders_file_rules", busy: saving, error: error, desktopFitsContent: true, form: true) {
      Text(folders.displayName(source)).font(.headline)
      VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
        Text("folders_skip")
        FolderTokens(tokens: $exclude, placeholder: "Drafts/", title: "folders_skip").frame(minHeight: DuckSettingsMetrics.rowHeight)
      }
      VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
        Text("folders_only")
        FolderTokens(tokens: $include, placeholder: "IMG_*", title: "folders_only").frame(minHeight: DuckSettingsMetrics.rowHeight)
      }
      Text("folders_rules_note").font(.callout).foregroundStyle(.secondary)
    } actions: {
      Button("cancel", action: close).keyboardShortcut(.cancelAction).disabled(saving)
      Button("device_save") {
        NSApp.keyWindow?.makeFirstResponder(nil)
        saving = true
        Task {
          do {
            if !folders.isPreview { try await folders.saveRules(source.id, include: include, exclude: exclude) }
            close()
          } catch { self.error = NSLocalizedString("folders_rules_error", comment: "") }
          saving = false
        }
      }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(saving)
    }
  }
}

/// System token fields preserve each pattern as one editable token.
private struct FolderTokens: NSViewRepresentable {
  @Binding var tokens: [String]
  let placeholder: String
  let title: String
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSTokenField {
    let field = NSTokenField()
    field.delegate = context.coordinator
    field.tokenizingCharacterSet = CharacterSet(charactersIn: ",\n")
    field.placeholderString = placeholder
    field.setAccessibilityLabel(NSLocalizedString(title, comment: ""))
    return field
  }
  func updateNSView(_ field: NSTokenField, context: Context) {
    context.coordinator.parent = self
    if field.currentEditor() == nil, (field.objectValue as? [String] ?? []) != tokens { field.objectValue = tokens }
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTokenField, context: Context) -> CGSize? {
    // Token fields have an unbounded intrinsic width inside a grouped Form.
    // Use the form's proposed width to keep AppKit and SwiftUI layout convergent.
    CGSize(width: proposal.width ?? 320, height: max(DuckSettingsMetrics.rowHeight, nsView.intrinsicContentSize.height))
  }
  final class Coordinator: NSObject, NSTokenFieldDelegate {
    var parent: FolderTokens
    init(_ parent: FolderTokens) { self.parent = parent }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTokenField else { return }
      parent.tokens = (field.objectValue as? [String] ?? []).filter { !$0.isEmpty }
    }
    func controlTextDidEndEditing(_ notification: Notification) { controlTextDidChange(notification) }
  }
}

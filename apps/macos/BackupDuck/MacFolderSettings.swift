import AppKit
import SwiftUI

/// A6: canonical management destination, reached from Settings or a folder's menu.
struct MacFolderSettings: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  @State var selectedID: String?
  @State private var adding: URL?
  @State private var rules: FolderSource?
  @State private var stopping: FolderSource?
  private var selected: FolderSource? { folders.sources.first { $0.id == selectedID } }
  var body: some View {
    Group {
      if let selected {
        VStack(alignment: .leading, spacing: 0) {
          Button { selectedID = nil } label: { Label("settings_folders", systemImage: "chevron.left") }
            .buttonStyle(.bordered).padding(.horizontal, DuckSpacing.large).padding(.top, DuckSpacing.medium)
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
              actionRow("folder_reveal") { folders.reveal(selected) }
              actionRow("folders_file_rules") { rules = selected }
            } footer: { Text("folders_rules_hint") }
            if selected.pendingControl != nil && !folders.recoveringControls.contains(selected.id) {
              Section {
                actionRow("mac_folder_recover_operation") {
                  Task { if await folders.recoverPendingControl(selected.id), !folders.sources.contains(where: { $0.id == selected.id }) { selectedID = nil } }
                }
              }
            }
            Section {
              actionRow("folders_stop_title") { stopping = selected }.disabled(selected.pendingControl != nil)
            }
          }.formStyle(.grouped)
        }
      } else {
        Form {
          Section {
            ForEach(folders.sources) { source in
              Button { selectedID = source.id } label: {
                HStack {
                  Image(systemName: "folder").foregroundStyle(.secondary)
                  VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
                    Text(folders.displayName(source)).foregroundStyle(.primary)
                    Text(folders.location(source)).font(.callout).foregroundStyle(.secondary)
                    Text(folderSentence(folders.facts[source.id])).font(.callout).foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, minHeight: DuckSettingsMetrics.rowHeight, alignment: .leading)
                  .fixedSize(horizontal: false, vertical: true)
                  .contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          } footer: {
            VStack(alignment: .leading, spacing: DuckSpacing.small) {
              Button("folders_add", action: choose).buttonStyle(.bordered).controlSize(.regular)
                .disabled(!backup.ready || folders.loadFailed)
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
      if let id = folders.initialSettingsFolder { selectedID = id }
      if folders.initialSheet == "rules" { rules = selected ?? folders.sources.first }
      if folders.initialSheet == "stop" { stopping = selected ?? folders.sources.first }
      if folders.initialSheet == "add" { choose() }
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckFolderSettings"))) { note in selectedID = note.object as? String }
    .sheet(item: $rules) { source in FolderRulesSheet(folders: folders, source: source) { rules = nil } }
    .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
      if let adding { AddFolderSheet(url: adding, folders: folders, backup: backup) { self.adding = nil } }
    }
    .background {
      FolderStopAlert(source: $stopping, folders: folders) { source in
        Task { if await folders.remove(source.id) { selectedID = nil } }
      }.frame(width: 0, height: 0)
    }
  }
  private func actionRow(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).frame(maxWidth: .infinity, minHeight: DuckSettingsMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(.primary)
  }
  private func choose() {
    if folders.isPreview { adding = URL(fileURLWithPath: "/Synthetic/\(folders.sources.first.map { folders.displayName($0) } ?? "Camera Exports")"); return }
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.begin { result in if result == .OK { adding = panel.url } }
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

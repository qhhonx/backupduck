import AppKit
import SwiftUI

struct FolderSourcesPage: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  private var selection: String? {
    get { folders.selectedSourceID }
    nonmutating set { folders.selectedSourceID = newValue }
  }
  @State private var adding: URL?
  @State private var removing: String?
  @State private var showHelp = false
  @State private var issuesPage = false
  @State private var rulesSource: FolderSource?
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if selection == nil {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 8) {
            Text("mac_nav_sources").font(.system(size: 26, weight: .semibold))
            Text("folder_readonly_note").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
          }
          Spacer()
          Button { showHelp = true } label: { Image(systemName: "questionmark.circle").frame(width: 32, height: 32) }.buttonStyle(.plain).help("folder_help")
          Button("folder_add", action: choose).duckSecondaryAction()
            .disabled(!backup.ready || folders.loadFailed)
        }
      }
      if backup.paused {
        HStack {
          Label("folder_global_paused", systemImage: "pause.circle")
          Spacer()
          Button("mac_resume_all") { Task { await backup.setPaused(false) } }.duckSecondaryAction()
            .disabled(!backup.ready || backup.pairing == nil || backup.changingPause)
        }.font(.callout).padding(12)
          .background(DuckColors.subtle, in: RoundedRectangle(cornerRadius: 10))
      }
      if let error = backup.pauseError { DuckNotice(title: LocalizedStringKey(error), tone: .failure) }
      if folders.loadFailed {
        DuckNotice(title: "mac_folder_settings_unavailable", tone: .failure)
        Button("retry_task") { Task { await folders.open() } }.duckSecondaryAction()
          .accessibilityIdentifier("folder.reload_config")
      } else if let selection, let source = folders.sources.first(where: { $0.id == selection }) {
        Button { if issuesPage { issuesPage = false } else { self.selection = nil } } label: {
          Label(LocalizedStringKey(issuesPage ? "folder_open" : "sources_back"), systemImage: "chevron.left")
        }
        if issuesPage { FolderIssuesPage(folders: folders, backup: backup, source: source) }
        else {
          FolderSourceDetail(folders: folders, backup: backup, source: source,
            openIssues: { issuesPage = true }, editRules: { rulesSource = source }).id(source.id)
        }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            ForEach(folders.sources) { source in
              FolderSourceCard(folders: folders, backup: backup, source: source,
                open: { selection = source.id; issuesPage = false },
                openIssues: { selection = source.id; issuesPage = true },
                editRules: { rulesSource = source }, remove: { removing = source.id })
            }
            if folders.sources.isEmpty {
              DuckSurface {
                VStack(alignment: .leading, spacing: 20) {
                  DuckBrandMark(size: 60)
                  Text("folder_sources_empty").font(.headline)
                  Text("folder_readonly_note").foregroundStyle(DuckColors.textSecondary)
                  Button("folder_add", action: choose).duckPrimaryAction()
                    .disabled(!backup.ready || folders.loadFailed)
                }
              }
            }
          }
        }
      }
      if let error = folders.error, !folders.loadFailed {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.triangle")
      }
    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .sheet(item: $rulesSource) { source in FolderRulesSheet(folders: folders, source: source) { rulesSource = nil } }
      .sheet(isPresented: $showHelp) {
        DuckSheetLayout(title: "folder_help") {
          Text("folder_automatic").font(.headline)
          Text("folder_automatic_guide")
          Text("folder_backup_now").font(.headline)
          Text("folder_manual_guide")
          DuckNotice(title: "folder_readonly_note")
        } actions: {
          Button("settings_done") { showHelp = false }.duckSecondaryAction()
            .keyboardShortcut(.cancelAction)
        }
      }

      .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
        if let adding { AddFolderSheet(url: adding, folders: folders) { self.adding = nil } }
      }
      .sheet(isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
        if let removing, let source = folders.sources.first(where: { $0.id == removing }) {
          FolderRemoveSheet(folders: folders, source: source) { self.removing = nil }
        }
      }

  }
  private func choose() {
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
    panel.allowsMultipleSelection = false; panel.prompt = NSLocalizedString("folder_choose", comment: "")
    panel.begin { result in if result == .OK { adding = panel.url } }
  }
}
private struct FolderSourceCard: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  let source: FolderSource
  let open: () -> Void
  let openIssues: () -> Void
  let editRules: () -> Void
  let remove: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 5) {
          Text(folders.displayName(source)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
          Text(folders.displayPath(source)).font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
            .lineLimit(1).truncationMode(.middle).help(folders.displayPath(source))
        }
        Spacer()
        Menu {
          Button("folder_rules", action: editRules).duckSecondaryAction().disabled(source.pendingControl != nil && source.pendingControl?.action != "rules")
          Button("folder_check") { folders.check(source.id, userInitiated: true) }.disabled(source.pendingControl != nil)
          Button("folder_reveal") { folders.reveal(source) }
          if let checked = source.lastCheck {
            Text(NSLocalizedString("folder_last_check", comment: "") + " " + checked.formatted(date: .abbreviated, time: .shortened))
          }
          if let summary = folders.summaries[source.id], summary.unsupported > 0 {
            Text(String(format: NSLocalizedString("folder_unsupported", comment: ""), summary.unsupported))
          }
          Divider()
          Button("folder_remove", role: .destructive, action: remove).disabled(source.pendingControl != nil && source.pendingControl?.action != "remove")
        } label: { Label("folder_more", systemImage: "ellipsis") }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      }
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          FolderSourceStatus(folders: folders, backup: backup, source: source)
          if let summary = folders.summaries[source.id] {
            Text(String(format: NSLocalizedString("folder_count", comment: ""), summary.files,
              ByteCountFormatter.string(fromByteCount: Int64(summary.bytes), countStyle: .file)))
              .font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
          .background(DuckColors.subtle, in: RoundedRectangle(cornerRadius: 12))
        if !source.issues.isEmpty {
          Button(action: openIssues) { Text(String(format: NSLocalizedString("folder_issues", comment: ""), source.issues.count)) }
            .duckSecondaryAction().foregroundStyle(DuckColors.attention)
        }
      }
      FolderSourceActions(folders: folders, backup: backup, source: source, open: open)
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(DuckColors.border, lineWidth: 1))
  }
}
private struct FolderSourceStatus: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  let source: FolderSource
  private var key: String {
    FolderSourcePresentation.status(source: source, phase: folders.phases[source.id],
      action: folders.actionMessages[source.id], executing: folders.recoveringControls.contains(source.id),
      paused: backup.paused, paired: backup.pairing != nil)
  }
  var body: some View { Text(LocalizedStringKey(key)).font(.callout).foregroundStyle(.secondary) }
}
private struct FolderSourceActions: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  let source: FolderSource
  var open: (() -> Void)? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if FolderControlPresentation(pending: source.pendingControl,
        executing: folders.recoveringControls.contains(source.id)) == .needsRecovery {
        Button("mac_folder_recover_operation") { Task { await folders.recoverPendingControl(source.id) } }
          .duckPrimaryAction().disabled(folders.recoveringControls.contains(source.id))
          .accessibilityIdentifier("folder.recover_operation")
      }
      DuckActions { buttons; Spacer(minLength: 12); automatic }
        .fixedSize(horizontal: false, vertical: true)
    }
  }
  private var automatic: some View {
    Toggle("folder_automatic", isOn: Binding(get: { source.automaticActive },
      set: { folders.setAutomatic(source.id, $0) }))
      .toggleStyle(.switch).controlSize(.small).fixedSize()
      .help("folder_automatic_hint").disabled(folders.starting.contains(source.id) || source.pendingControl != nil)
  }
  @ViewBuilder private var buttons: some View {
    if let open {
      Button("folder_open", action: open).duckSecondaryAction()
    }
    if source.manualActive {
      Button("folder_stop_manual") { folders.pause(source.id) }
        .duckSecondaryAction().help("folder_pause_help").disabled(folders.starting.contains(source.id) || source.pendingControl != nil)
    } else {
      Button(LocalizedStringKey(folders.starting.contains(source.id) ? "folder_starting" : "folder_backup_now")) { Task { await folders.start(source.id) } }.duckSecondaryAction().help("folder_backup_help")
        .disabled(!backup.ready || backup.pairing == nil || folders.starting.contains(source.id) || source.pendingControl != nil)
    }
  }
}
struct AddFolderSheet: View {
  let url: URL
  @ObservedObject var folders: FolderSources
  var close: () -> Void
  @State private var automatic = true
  @State private var existing = true
  @State private var include = ""
  @State private var exclude = ""
  @State private var rulesExpanded = false
  @State private var adding = false
  @State private var error: String?
  var body: some View {
    DuckSheetLayout(title: "folder_add", busy: adding, error: error) {
      VStack(alignment: .leading, spacing: 6) {
        Text(url.lastPathComponent).font(.headline)
        Text(url.path).font(.caption).foregroundStyle(DuckColors.textSecondary)
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      }
      Text("folder_scan_note").font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
      option("folder_include_existing", note: "mac_fidelity_folder_existing_note", value: $existing)
        .disabled(adding).accessibilityIdentifier("folder.add.existing")
      option("folder_automatic", note: "mac_fidelity_folder_auto_note", value: $automatic)
        .disabled(adding).accessibilityIdentifier("folder.add.automatic")
      Button { rulesExpanded.toggle() } label: {
        MacPreferenceRow(title: "folder_rules") {
          Image(systemName: rulesExpanded ? "chevron.down" : "chevron.right").foregroundStyle(DuckColors.action).frame(width: 16)
        }
      }.buttonStyle(.plain).disabled(adding).accessibilityIdentifier("folder.add.rules")
      if rulesExpanded { FolderRuleFields(include: $include, exclude: $exclude).disabled(adding) }
      Text("folder_readonly_note").font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
      if adding { ProgressView("settings_saving").accessibilityIdentifier("folder.add.busy") }
    } actions: {
      Button("cancel", action: close).disabled(adding).duckSecondaryAction()
        .keyboardShortcut(.cancelAction)
      Button("folder_add", action: add).duckPrimaryAction()
        .disabled(adding || (!existing && !automatic)).keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("folder.add.confirm")
    }
  }
  private func option(_ title: LocalizedStringKey, note: LocalizedStringKey, value: Binding<Bool>) -> some View {
    MacPreferenceRow(title: title, note: note) {
      Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch)
    }
  }
  private func add() {
    guard !adding else { return }
    adding = true; error = nil
    Task {
      defer { adding = false }
      do {
        try await folders.add(url, automatic: automatic, existing: existing,
          include: FolderRuleFields.lines(include), exclude: FolderRuleFields.lines(exclude))
        close()
      } catch let failure as Bridge.Failure where failure.code == "conflict" {
        error = NSLocalizedString("folder_overlap_error", comment: "")
      } catch let failure as FolderRuleError {
        error = NSLocalizedString("folder_rules_invalid", comment: "") + " " + failure.localizedDescription
      } catch { self.error = error.localizedDescription }
    }
  }
}
private struct FolderSourceDetail: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  let source: FolderSource
  let openIssues: () -> Void
  let editRules: () -> Void
  @State private var entries: [FolderEntry] = []
  @State private var more = true
  @State private var loading = false
  @State private var error: String?
  @State private var visible = Set<String>()
  @AppStorage("macFolderListLayout") private var layout = "flat"
  @AppStorage("macFolderFileSort") private var sort = FolderFileSort.modifiedNewest
  @AppStorage("macFolderTreeDescending") private var treeDescending = false
  @State private var request = UUID()
  @State private var loadedContext: String?
  @StateObject private var tree = FolderTreeModel()
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text(folders.displayName(source)).font(.system(size: 26, weight: .semibold))
          Text(folders.displayPath(source)).font(.caption).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.middle)
          FolderSourceStatus(folders: folders, backup: backup, source: source)
        }
        Spacer()
        if !source.issues.isEmpty {
          Button(action: openIssues) { Label(String(format: NSLocalizedString("folder_issues", comment: ""), source.issues.count), systemImage: "exclamationmark.triangle") }
            .foregroundStyle(.orange).accessibilityIdentifier("folder.issues")
        }
        Button("folder_rules", action: editRules).duckSecondaryAction().disabled(source.pendingControl != nil && source.pendingControl?.action != "rules")
      }
      FolderSourceActions(folders: folders, backup: backup, source: source)
      HStack(alignment: .center) {
        FolderSortControl(layout: layout, sort: $sort, treeDescending: $treeDescending)
          .fixedSize(horizontal: true, vertical: true)
        Spacer()
        Picker("folder_list_layout", selection: $layout) {
          Text("folder_list_flat").tag("flat")
          Text("folder_list_tree").tag("folders")
        }.duckDesktopSegments(width: 180)
      }
      if layout == "flat", let error {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
          .accessibilityIdentifier("folder.files_load_error")
        Button("retry_task") { Task { await reload() } }.duckSecondaryAction().disabled(loading)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if layout == "folders" {
            ForEach(tree.rows) { row in
              VStack(alignment: .leading, spacing: 0) {
                if let child = row.child {
                  if child.is_directory {
                    Button {
                      Task { await tree.toggle(child.relative, source: source.id, folders: folders) }
                    } label: {
                      HStack(spacing: 10) {
                        Image(systemName: tree.expanded.contains(child.relative) ? "chevron.down" : "chevron.right").frame(width: 12)
                        Image(systemName: "folder").foregroundStyle(.tint)
                        Text((child.relative as NSString).lastPathComponent).lineLimit(1)
                        Spacer()
                      }.padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(child.relative)
                  } else if let entry = child.entry {
                    FolderFileRow(folders: folders, source: source, entry: entry, nested: true)
                      .onAppear { visible.insert(entry.relative) }
                      .onDisappear { visible.remove(entry.relative) }
                  }
                } else if tree.loading.contains(row.directory) {
                  ProgressView().padding(.vertical, 12)
                } else {
                  if let message = tree.errors[row.directory] { Text(message).font(.caption).foregroundStyle(.orange) }
                  Button(LocalizedStringKey(tree.errors[row.directory] == nil ? "folder_load_more" : "retry_task")) {
                    Task { await tree.load(row.directory, source: source.id, folders: folders) }
                  }.padding(.vertical, 12)
                }
                Divider()
              }.padding(.leading, CGFloat(min(row.depth, 10) * 18))
            }
            if tree.rows.isEmpty { Text("folder_empty").foregroundStyle(.secondary).padding(.vertical, 24) }
          } else {
            ForEach(entries) { entry in
              FolderFileRow(folders: folders, source: source, entry: entry)
                .onAppear { visible.insert(entry.relative) }
                .onDisappear { visible.remove(entry.relative) }
              Divider()
            }
            if more { Button("folder_load_more") { Task { await load() } }.padding(.vertical, 16).disabled(loading) }
            if entries.isEmpty {
              if loading { ProgressView().padding(.vertical, 24) }
              else if error == nil { Text("folder_empty").foregroundStyle(.secondary).padding(.vertical, 24) }
            }
          }
        }
      }
    }
    .task(id: "\(source.id)|\(folders.indexRevision)|\(layout)|\(sort.rawValue)|\(treeDescending)") {
      if layout == "folders" { await tree.refresh(source: source.id, folders: folders, descending: treeDescending) }
      else { await reload() }
    }
    .task(id: "\(folders.revision)|\(backup.queueRevision)|\(visible.sorted().joined(separator: "|"))") {
      try? await Task.sleep(nanoseconds: 150_000_000)
      guard !Task.isCancelled else { return }
      if let states = try? await folders.states(source.id, relatives: Array(visible.prefix(400))) {
        guard !Task.isCancelled else { return }
        for i in entries.indices where visible.contains(entries[i].relative) && entries[i].state != states[entries[i].relative] { entries[i].state = states[entries[i].relative] }
        tree.apply(states, visible: visible)
      }
    }
  }
  private func load() async {
    guard !loading else { return }
    let expected = request
    loading = true
    defer { if request == expected { loading = false } }
    do {
      let page = try await folders.page(source.id, offset: entries.count, sort: sort)
      guard request == expected, !Task.isCancelled else { return }
      entries.append(contentsOf: page); more = page.count == 100; error = nil
    } catch { if request == expected, !Task.isCancelled { self.error = error.localizedDescription } }
  }
  private func reload() async {
    let expected = UUID(); request = expected
    let selectedSort = sort
    let context = source.id + "|" + selectedSort.rawValue
    if loadedContext != context { entries = []; more = false; loadedContext = context }
    let limit = max(100, entries.count)
    loading = true; error = nil
    defer { if request == expected { loading = false } }
    do {
      var result: [FolderEntry] = []
      for offset in stride(from: 0, to: limit, by: 100) {
        let page = try await folders.page(source.id, offset: offset, sort: selectedSort)
        guard request == expected, !Task.isCancelled else { return }
        result.append(contentsOf: page)
        if page.count < 100 { break }
      }
      entries = result; more = result.count > 0 && result.count % 100 == 0
    } catch { if request == expected, !Task.isCancelled { self.error = error.localizedDescription } }
  }
}

private struct FolderIssuesPage: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  let source: FolderSource
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("folder_issue_details").font(.title2)
      Text(folders.displayPath(source)).font(.caption).foregroundStyle(.secondary)
      Text("folder_issues_explanation").foregroundStyle(.secondary)
      if source.issues.isEmpty { Label("folder_no_issues", systemImage: "checkmark.circle").padding(.vertical, 24) }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          ForEach(source.issues.keys.sorted(), id: \.self) { path in
            FolderIssueRow(folders: folders, backup: backup, source: source, path: path)
            Divider()
          }
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
private struct FolderRuleFields: View {
  @Binding var include: String
  @Binding var exclude: String
  static func lines(_ text: String) -> [String] {
    text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("folder_rules_note").font(.system(size: 14))
      Text("folder_rules_include").font(.system(size: 14))
      Text("folder_rules_include_note").font(.system(size: 12)).foregroundStyle(.secondary)
      TextEditor(text: $include).font(.system(size: 14, design: .monospaced)).frame(height: 96)
        .padding(8).background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DuckColors.border))
        .accessibilityLabel("folder_rules_include")
      Text("folder_rules_exclude").font(.system(size: 14))
      Text("folder_rules_exclude_note").font(.system(size: 12)).foregroundStyle(.secondary)
      TextEditor(text: $exclude).font(.system(size: 14, design: .monospaced)).frame(height: 96)
        .padding(8).background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DuckColors.border))
        .accessibilityLabel("folder_rules_exclude")
      DisclosureGroup("folder_rules_pattern_help") {
        VStack(alignment: .leading, spacing: 8) {
          Text("folder_rules_path_note")
          example("folder_rules_include_example", explanation: "folder_rules_include_example_note")
          example("folder_rules_exclude_example", explanation: "folder_rules_exclude_example_note")
          Text(verbatim: NSLocalizedString("folder_rules_examples", comment: ""))
        }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 4)
      }.font(.callout)
    }
  }
  private func example(_ pattern: String, explanation: LocalizedStringKey) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(verbatim: NSLocalizedString(pattern, comment: "")).font(.system(.caption, design: .monospaced))
        .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
      Text(explanation).font(.caption).foregroundStyle(.secondary)
    }
  }
}
struct FolderRulesSheet: View {
  @ObservedObject var folders: FolderSources
  let source: FolderSource
  let close: () -> Void
  @State private var include: String
  @State private var exclude: String
  @State private var saving = false
  @State private var error: String?
  init(folders: FolderSources, source: FolderSource, close: @escaping () -> Void) {
    self.folders = folders; self.source = source; self.close = close
    _include = State(initialValue: (source.includePatterns ?? []).joined(separator: "\n"))
    _exclude = State(initialValue: (source.excludePatterns ?? []).joined(separator: "\n"))
  }
  private var pending: Bool { folders.sources.first { $0.id == source.id }?.pendingControl != nil }
  var body: some View {
    DuckSheetLayout(title: "folder_rules", busy: saving, error: error) {
      Text(folders.displayName(source)).font(.headline)
      FolderRuleFields(include: $include, exclude: $exclude).disabled(saving || pending)
      if pending && !saving && !folders.recoveringControls.contains(source.id) {
        Text("mac_folder_operation_incomplete").foregroundStyle(DuckColors.attention)
      }
      DuckNotice(title: "folder_rules_effect")
      if saving { ProgressView("settings_saving") }
    } actions: {
      Button(LocalizedStringKey(pending ? "settings_done" : "cancel"), action: close).disabled(saving).duckSecondaryAction()
        .keyboardShortcut(.cancelAction)
      Button(LocalizedStringKey(pending ? "mac_folder_recover_operation" : "folder_rules_save"), action: save).duckPrimaryAction()
        .disabled(saving).keyboardShortcut(.defaultAction).accessibilityIdentifier("folder.rules.save")
    }
  }
  private func save() {
    guard !saving else { return }
    saving = true; error = nil
    Task {
      defer { saving = false }
      do {
        if pending {
          guard await folders.recoverPendingControl(source.id) else { error = folders.error; return }
        } else {
          try await folders.saveRules(source.id, include: FolderRuleFields.lines(include), exclude: FolderRuleFields.lines(exclude))
        }
        close()
      } catch {
        self.error = pending ? error.localizedDescription : NSLocalizedString("folder_rules_invalid", comment: "") + " " + error.localizedDescription
      }
    }
  }
}

private struct FolderIssueRow: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  let source: FolderSource
  let path: String
  @State private var details = false
  private var issue: FolderIssue? { source.issueDetails?[path] }
  var body: some View {
    Button { details = true } label: {
      HStack(alignment: .firstTextBaseline, spacing: 16) {
        Image(systemName: "exclamationmark.triangle").foregroundStyle(DuckColors.attention)
        VStack(alignment: .leading, spacing: 6) {
          Text((path as NSString).lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
          Text(path).font(.caption).foregroundStyle(DuckColors.textSecondary).lineLimit(1)
            .truncationMode(.middle)
          Text(LocalizedStringKey("folder_issue_" + (issue?.reason ?? "unknown")))
            .font(.callout).foregroundStyle(DuckColors.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right").foregroundStyle(DuckColors.textSecondary)
      }.padding(.vertical, 8).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("folder.issue." + path)
      .sheet(isPresented: $details) {
        FolderIssueDetail(folders: folders, backup: backup, sourceID: source.id, path: path)
      }
  }
}
struct FolderIssueDetail: View {
  @ObservedObject var folders: FolderSources
  @ObservedObject var backup: BackupModel
  let sourceID: String
  let path: String
  @Environment(\.dismiss) private var dismiss
  @State private var busy = false
  @State private var ignore = false
  private var source: FolderSource? { folders.sources.first { $0.id == sourceID } }
  private var retrying: Bool { (source?.retryPaths ?? []).contains(path) }
  var body: some View {
    DuckSheetLayout(title: "folder_issue_details", busy: busy, error: folders.error) {
      Text((path as NSString).lastPathComponent).font(.headline)
        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      Text(path).font(.callout.monospaced()).foregroundStyle(DuckColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      if let source {
        DuckNotice(title: LocalizedStringKey("folder_issue_" + (source.issueDetails?[path]?.reason ?? "unknown")),
          tone: .attention, symbol: "exclamationmark.triangle")
        if let detail = source.issueDetails?[path]?.detail {
          Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        if retrying {
          DuckNotice(title: "folder_retry_waiting", message: backup.paused ? "folder_global_wait" : "folder_retry_requested")
            .accessibilityIdentifier("folder.issue.retry_feedback")
        }
        Button("folder_reveal") { folders.reveal(source, relative: path) }.duckSecondaryAction()
        Button("folder_ignore_version") { ignore = true }.duckSecondaryAction()
          .disabled(busy || source.pendingControl != nil).accessibilityIdentifier("folder.issue.ignore")
      }
      DuckNotice(title: "folder_ignore_note")
    } actions: {
      Button("settings_done") { dismiss() }.duckSecondaryAction().disabled(busy)
        .keyboardShortcut(.cancelAction)
      Button(LocalizedStringKey(source?.pendingControl != nil ? "mac_folder_recover_operation" : retrying ? "folder_retry_waiting" : "retry_task")) {
        busy = true; folders.error = nil
        Task {
          if source?.pendingControl != nil { _ = await folders.recoverPendingControl(sourceID) }
          else { _ = await folders.retry(sourceID, relative: path) }
          busy = false
        }
      }.duckPrimaryAction()
        .disabled((retrying && source?.pendingControl == nil) || busy || !backup.ready || backup.pairing == nil || source == nil)
        .accessibilityIdentifier("folder.issue.retry")
    }
    .confirmationDialog("folder_ignore_version", isPresented: $ignore) {
      Button("folder_ignore_version", role: .destructive) {
        busy = true; folders.error = nil
        Task {
          let ignored = await folders.dismissIssue(sourceID, relative: path)
          busy = false
          if ignored { dismiss() }
        }
      }
    } message: { Text("folder_ignore_note") }
  }
}

enum FolderFileSort: String, CaseIterable, Identifiable {
  case modifiedNewest = "modified_desc"
  case modifiedOldest = "modified_asc"
  case pathAscending = "path_asc"
  case pathDescending = "path_desc"
  case sizeLargest = "size_desc"
  case sizeSmallest = "size_asc"
  var id: String { rawValue }
  var title: String { "folder_sort_" + rawValue }
}

// Keep the native popup and its items alive while queue/source state refreshes.
// SwiftUI's Menu + Picker creates a submenu that can close during those updates.
struct FolderSortControl: NSViewRepresentable {
  let layout: String
  @Binding var sort: FolderFileSort
  @Binding var treeDescending: Bool
  private var options: [String] {
    layout == "folders" ? ["name_asc", "name_desc"] : FolderFileSort.allCases.map(\.rawValue)
  }
  private var selected: String { layout == "folders" ? (treeDescending ? "name_desc" : "name_asc") : sort.rawValue }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: true)
    button.isBordered = false
    button.setAccessibilityIdentifier("folder.sort")
    button.toolTip = NSLocalizedString("folder_sort", comment: "")
    updateNSView(button, context: context)
    return button
  }
  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.parent = self
    if context.coordinator.options != options {
      let menu = NSMenu()
      menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
      for value in options {
        let item = NSMenuItem(title: NSLocalizedString("folder_sort_" + value, comment: ""),
          action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
        item.target = context.coordinator; item.representedObject = value
        menu.addItem(item)
      }
      button.menu = menu
      context.coordinator.options = options
    }
    let title = NSLocalizedString("folder_sort_" + selected, comment: "")
    if button.title != title {
      button.title = title
      button.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
      button.imagePosition = .imageLeading
      button.invalidateIntrinsicContentSize()
    }
    for item in button.itemArray.dropFirst() {
      let state: NSControl.StateValue = item.representedObject as? String == selected ? .on : .off
      if item.state != state { item.state = state }
    }
  }
  final class Coordinator: NSObject {
    var parent: FolderSortControl
    var options: [String] = []
    init(_ parent: FolderSortControl) { self.parent = parent }
    @objc func choose(_ item: NSMenuItem) {
      guard let value = item.representedObject as? String else { return }
      if parent.layout == "folders" { parent.treeDescending = value == "name_desc" }
      else if let sort = FolderFileSort(rawValue: value) { parent.sort = sort }
    }
  }
}

struct FolderChild: Decodable, Identifiable {
  let relative: String
  let is_directory: Bool
  var entry: FolderEntry?
  var id: String { relative }
}
struct FolderChildren: Decodable {
  var rows: [FolderChild]
  let has_more: Bool
}
@MainActor private final class FolderTreeModel: ObservableObject {
  struct Row: Identifiable {
    let child: FolderChild?
    let directory: String
    let depth: Int
    var id: String { child.map { "child:" + $0.relative } ?? "page:" + directory }
  }
  @Published var children: [String: [FolderChild]] = [:]
  @Published var expanded = Set<String>()
  @Published var more = Set<String>()
  @Published var loading = Set<String>()
  @Published var errors: [String: String] = [:]
  private var generation = 0
  private var descending = false
  var rows: [Row] {
    var result: [Row] = []
    func visit(_ directory: String, depth: Int) {
      for child in children[directory] ?? [] {
        result.append(Row(child: child, directory: directory, depth: depth))
        if child.is_directory, expanded.contains(child.relative) { visit(child.relative, depth: depth + 1) }
      }
      if more.contains(directory) || loading.contains(directory) || errors[directory] != nil {
        result.append(Row(child: nil, directory: directory, depth: depth))
      }
    }
    visit("", depth: 0)
    return result
  }
  func toggle(_ directory: String, source: String, folders: FolderSources) async {
    if expanded.contains(directory) { expanded.remove(directory); return }
    expanded.insert(directory)
    if children[directory] == nil { await load(directory, source: source, folders: folders) }
  }
  func load(_ directory: String, source: String, folders: FolderSources) async {
    guard !loading.contains(directory) else { return }
    loading.insert(directory); errors[directory] = nil
    let expected = generation
    defer { if generation == expected { loading.remove(directory) } }
    do {
      let page = try await folders.children(source, directory: directory, offset: children[directory]?.count ?? 0, descending: descending)
      guard generation == expected, !Task.isCancelled else { return }
      children[directory, default: []].append(contentsOf: page.rows)
      if page.has_more { more.insert(directory) } else { more.remove(directory) }
    } catch {
      if generation == expected, !Task.isCancelled { errors[directory] = error.localizedDescription }
    }
  }
  func refresh(source: String, folders: FolderSources, descending: Bool) async {
    generation += 1
    self.descending = descending
    let expected = generation
    loading.removeAll()
    // Refresh only the root and directories that are currently expanded.
    for directory in [""] + expanded.sorted() {
      let limit = max(100, children[directory]?.count ?? 0)
      children[directory] = nil; more.remove(directory); errors[directory] = nil
      for _ in stride(from: 0, to: limit, by: 100) {
        guard generation == expected, !Task.isCancelled else { return }
        await load(directory, source: source, folders: folders)
        if !more.contains(directory) { break }
      }
    }
    // Cached closed directories must be queried again after an index change.
    for directory in Array(children.keys) where !directory.isEmpty && !expanded.contains(directory) {
      children[directory] = nil; more.remove(directory); errors[directory] = nil
    }
  }
  func apply(_ states: [String: String], visible: Set<String>) {
    for directory in Array(children.keys) {
      guard var rows = children[directory] else { continue }
      var changed = false
      for index in rows.indices where visible.contains(rows[index].relative) && rows[index].entry?.state != states[rows[index].relative] {
        let state = states[rows[index].relative]
        rows[index].entry?.state = state; changed = true
      }
      if changed { children[directory] = rows }
    }
  }
}

private struct FolderFileRow: View {
  @ObservedObject var folders: FolderSources
  @State private var details = false
  let source: FolderSource
  let entry: FolderEntry
  var nested = false
  var body: some View {
    Button { details = true } label: {
    HStack(spacing: 14) {
      MacFileThumbnail(source: source, relative: entry.relative, revision: entry.revision,
        video: entry.media_type.hasPrefix("video/"), size: 44)
      VStack(alignment: .leading, spacing: 4) {
        Text((entry.relative as NSString).lastPathComponent).font(.system(size: 14, weight: .semibold))
          .lineLimit(1).help(entry.relative)
        HStack(spacing: 6) {
          Text(LocalizedStringKey(entry.media_type.hasPrefix("video/") ? "library_filter_video" : "library_filter_photo"))
          Text("·")
          if entry.modified_ms > 0 {
            Text(Date(timeIntervalSince1970: Double(entry.modified_ms) / 1000), format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
              .help("folder_modified_time").accessibilityIdentifier("folder.file_modified")
          } else { Text("task_order_unknown") }
          Text("·")
          Text(folders.displayName(source))
        }.font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 4) {
        Label(LocalizedStringKey(entry.state.map { "state_" + $0 } ?? "folder_not_queued"), systemImage: taskSymbol(entry.state))
          .font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
        Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
          .font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
      }.fixedSize(horizontal: true, vertical: false)
    }.padding(.vertical, 12).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("folder.file." + entry.relative)
      .sheet(isPresented: $details) {
        FolderFileDetail(folders: folders, source: source, entry: entry)
      }
  }
}

struct FolderFileDetail: View {
  @ObservedObject var folders: FolderSources
  let source: FolderSource
  let entry: FolderEntry
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    DuckSheetLayout(title: "mac_file_details", error: folders.error) {
      Text((entry.relative as NSString).lastPathComponent).font(.system(size: 16, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      VStack(spacing: 0) {
        field("mac_fidelity_relative_path", value: entry.relative)
        field("folder_modified_time", value: entry.modified_ms > 0
          ? Date(timeIntervalSince1970: Double(entry.modified_ms) / 1000).formatted(date: .abbreviated, time: .shortened)
          : NSLocalizedString("task_order_unknown", comment: ""))
        field("design_file_size", value: ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
        field("task_source_filter", value: folders.displayName(source))
        field("mac_fidelity_status_title", value: NSLocalizedString(entry.state.map { "state_" + $0 } ?? "folder_not_queued", comment: ""))
      }
      DuckNotice(title: "mac_file_source_note")
      DisclosureGroup("design_file_type") { Text(entry.media_type).font(.system(size: 12)).textSelection(.enabled) }
    } actions: {
      Button("settings_done") { dismiss() }.duckSecondaryAction().keyboardShortcut(.cancelAction)
      Button("folder_reveal") { folders.reveal(source, relative: entry.relative) }.duckSecondaryAction()
      Button("nav_transfers") {
        dismiss()
        NotificationCenter.default.post(name: Notification.Name("BackupDuckShowTransfers"), object: nil)
      }.duckSecondaryAction()
    }
  }
  private func field(_ title: LocalizedStringKey, value: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(title).font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary).frame(width: 130, alignment: .leading)
      Text(value).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() }
  }
}


struct FolderRemoveSheet: View {
  @ObservedObject var folders: FolderSources
  let source: FolderSource
  var close: () -> Void
  @State private var removing = false
  @State private var error: String?
  private var pending: Bool { folders.sources.first { $0.id == source.id }?.pendingControl != nil }
  var body: some View {
    DuckSheetLayout(title: "folder_remove", busy: removing, error: error, desktopWidth: 480, desktopMinHeight: 240, desktopIdealHeight: 320) {
      Text(String(format: NSLocalizedString("mac_fidelity_remove_question", comment: ""), folders.displayName(source))).font(.system(size: 16, weight: .semibold))
      Text("folder_remove_note").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary).fixedSize(horizontal: false, vertical: true)
      DuckNotice(title: "mac_fidelity_remove_boundary", tone: .attention)
      if removing { ProgressView("settings_saving") }
    } actions: {
      Button(LocalizedStringKey(pending ? "settings_done" : "cancel"), action: close).duckSecondaryAction().disabled(removing)
        .keyboardShortcut(.cancelAction)
      Button(LocalizedStringKey(pending ? "mac_folder_recover_operation" : "folder_remove"), role: .destructive) {
        guard !removing else { return }
        removing = true; error = nil
        Task {
          let succeeded = await folders.remove(source.id)
          removing = false
          if succeeded { close() }
          else { error = folders.error ?? NSLocalizedString("error_internal", comment: "") }
        }
      }.buttonStyle(MacDestructiveOutlineStyle()).disabled(removing)
        .accessibilityIdentifier("folder.remove.confirm")
    }
  }
}

/// Role/tint alone is overridden by the macOS bordered capsule style. This
/// desktop confirmation variant keeps an actual Button and explicit danger
/// foreground and outline, matching its distinct destructive action contract.
private struct MacDestructiveOutlineStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 14))
      .foregroundStyle(DuckColors.failure)
      .padding(.horizontal, 14).padding(.vertical, 10)
      .background(DuckColors.failure.opacity(configuration.isPressed ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 8))
      .overlay { RoundedRectangle(cornerRadius: 8).stroke(DuckColors.failure, lineWidth: 1) }
      .contentShape(RoundedRectangle(cornerRadius: 8)).opacity(enabled ? 1 : 0.48)
  }
}

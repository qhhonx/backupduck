import AppKit
import SwiftUI

/// Settings as defined in `design/settings.md`, in the Mac dialect System
/// Settings uses: a list column (identity header, category rows
/// with values, help last, quiet footer) and a detail pane with a grouped form.
/// Shown in the design catalog until migration step 6 replaces `MacPreferences`.
struct MacSettings: View {
  enum Page: Hashable { case devices, autoBackup, appearance, language, help, about, diagnostics, advanced }

  @ObservedObject var model: BackupModel
  @ObservedObject var folders: FolderSources
  var showFolders: () -> Void
  /// Devices live in the identity header (design/navigation.md, D3).
  @ObservedObject private var feedback = TesterFeedback.shared
  @AppStorage("duckAppearance") private var appearance = "system"
  @State private var page: Page? = .autoBackup
  @State private var renaming = false
  @State private var retrying = false
  @State private var connecting = false
  private var values: DuckSettingsValues { DuckSettingsValues(model: model) }

  var body: some View {
    HStack(spacing: 0) {
      list.frame(width: DuckSettingsMetrics.listWidth)
      Divider()
      detail.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .task { if model.deviceSnapshot == nil { await model.refreshDeviceStatus() } }
    // Row geometry from DuckSettingsMetrics (design/visual-language.md, V7):
    // the category list through the list row default, detail forms through the row styles.
    .environment(\.defaultMinListRowHeight, DuckSettingsMetrics.rowHeight)
    .labeledContentStyle(DuckPreferenceRowStyle())
    .toggleStyle(DuckPreferenceToggleStyle())
    .task(id: model.ready) { if model.ready { await model.refreshStorage() } }
    .task { await feedback.check() }
    .sheet(isPresented: $renaming) { DeviceNameEditor(model: model, name: model.deviceSnapshot?.device.name ?? "") }
  }

  private var list: some View {
    List(selection: $page) {
      header.selectionDisabled()
      if model.message != nil && !model.ready { openFailedCard.selectionDisabled() }
      Section {
        // Devices live in Settings (design/navigation.md, D3).
        row(.devices, "settings_devices", "smartphone", DuckGlyph.green,
          model.peerDevice?.name ?? NSLocalizedString("settings_pair_first", comment: ""))
        row(.autoBackup, "settings_auto_backup", "arrow.triangle.2.circlepath", DuckGlyph.blue, values.autoBackup)
        // Folders are edited in their own sidebar position; this row goes there.
        Button(action: showFolders) {
          LabeledContent {
            Text(String(format: NSLocalizedString("settings_folders_value", comment: ""), folders.sources.count))
          } label: { DuckSettingsLabel(title: "settings_folders", symbol: "folder", color: DuckGlyph.teal) }
        }.buttonStyle(.plain).selectionDisabled()
      }
      Section {
        row(.appearance, "apple_appearance", "circle.lefthalf.filled", DuckGlyph.indigo,
          NSLocalizedString("apple_appearance_" + appearance, comment: ""))
        row(.language, "apple_language", "globe", DuckGlyph.teal, languageName)
      }
      Section {
        row(.help, "settings_help_center", "questionmark", DuckGlyph.orange, nil)
        if feedback.available {
          Button { NSWorkspace.shared.open(TesterFeedback.group) } label: {
            LabeledContent { Text(verbatim: "Telegram") } label: {
              DuckSettingsLabel(title: "settings_feedback", symbol: "bubble.left.and.bubble.right.fill", color: DuckGlyph.blue)
            }
          }.buttonStyle(.plain).selectionDisabled()
        }
        row(.about, "about_title", "info", DuckGlyph.gray, nil)
      } footer: {
        VStack(spacing: 4) {
          Text(DuckSettingsValues.version)
          HStack(spacing: 12) {
            Button("settings_diagnostics") { page = .diagnostics }.buttonStyle(.link)
            Button("settings_advanced") { page = .advanced }.buttonStyle(.link)
          }
        }
        .font(.caption).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity).padding(.top, 16)
      }
    }
  }

  private func row(_ target: Page, _ title: LocalizedStringKey, _ symbol: String, _ color: Color, _ value: String?) -> some View {
    LabeledContent {
      if let value { Text(value) }
    } label: { DuckSettingsLabel(title: title, symbol: symbol, color: color) }
      .tag(target)
  }

  /// This device, and the device it backs up to. Edit renames it.
  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "laptopcomputer")
        .font(.title2).foregroundStyle(.white)  // design-exception: white glyph on the avatar circle
        .frame(width: 48, height: 48)
        .background(DuckGlyph.blue, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.deviceSnapshot?.device.name ?? "—").font(.headline)
        if let subtitle = values.pairedSubtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
      }
      Spacer(minLength: 0)
      Button("settings_edit") { renaming = true }.disabled(model.deviceSnapshot == nil)
    }
    .padding(.vertical, 8)
  }

  private var openFailedCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      DuckNotice(title: "settings_open_failed", tone: .attention, symbol: "exclamationmark.triangle.fill")
      if let message = model.message, message != NSLocalizedString("pairing_unlock_wait", comment: "") {
        Text(message).font(.subheadline).foregroundStyle(.secondary)
      }
      Button("retry_task") {
        guard !retrying else { return }
        retrying = true
        Task { await model.open(); retrying = false }
      }.disabled(retrying)
    }
    .padding(.vertical, 6)
  }

  private var detail: some View {
    detailContent.navigationTitle(pageTitle)
  }

  private var pageTitle: LocalizedStringKey {
    switch page {
    case .devices: "settings_devices"
    case .autoBackup: "settings_auto_backup"
    case .appearance: "apple_appearance"
    case .language: "apple_language"
    case .help: "settings_help_center"
    case .about: "about_title"
    case .diagnostics: "settings_diagnostics"
    case .advanced: "settings_advanced"
    case nil: "nav_settings"
    }
  }

  @ViewBuilder private var detailContent: some View {
    switch page {
    case .devices:
      DevicePage(model: model) { connecting = true }
        .sheet(isPresented: $connecting) { MacConnectSheet(model: model) }
    case .autoBackup: MacAutoBackupSettings(model: model)
    case .appearance: MacAppearanceSettings()
    case .language: MacLanguageSettings(languageName: languageName)
    case .help: NavigationStack { HelpCenter() }
    case .about: MacAboutSettings()
    case .diagnostics: ActivityLogView(embedded: true)
    case .advanced: MacAdvancedSettings(model: model)
    case nil: Color.clear
    }
  }

  private var languageName: String {
    Locale.current.localizedString(forLanguageCode: Bundle.main.preferredLocalizations.first ?? "en") ?? "—"
  }
}

private struct MacAutoBackupSettings: View {
  @ObservedObject var model: BackupModel
  @ObservedObject private var scope = BackupScopeStore.shared
  @State private var editing: BackupScopeDestination?
  var body: some View {
    Form {
      Section {
        Toggle("settings_auto_switch", isOn: Binding(get: { model.autoBackup }, set: { value in Task { await model.setAutoBackup(value) } }))
          .toggleStyle(.switch)
          .disabled(!model.ready || model.pairing == nil || model.changingAutoBackup)
      } footer: {
        if let error = model.autoBackupError {
          DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
        } else if model.ready {
          Text(model.pairing == nil ? NSLocalizedString("settings_auto_footer_unpaired", comment: "")
            : String(format: NSLocalizedString("settings_auto_footer_mac", comment: ""), DuckSettingsValues(model: model).receiverName))
            .foregroundStyle(.secondary)
        }
      }
      Section("settings_includes") {
        LabeledContent("settings_media_types") {
          Button(scope.typesSummary) { editing = .types }.buttonStyle(.link)
        }
        LabeledContent("settings_albums") {
          Button(scope.albumsSummary) { editing = .albums }.buttonStyle(.link)
        }
      }
    }
    .formStyle(.grouped)
    .sheet(item: $editing) { destination in
      MacScopeEditorSheet(destination: destination)
    }
  }
}

/// Appearance and how lists look: the display choices together.
private struct MacAppearanceSettings: View {
  @AppStorage("duckAppearance") private var appearance = "system"
  @AppStorage("macListThumbnails") private var thumbnails = true
  @AppStorage("macFolderListLayout") private var folderLayout = "flat"
  var body: some View {
    Form {
      Picker("apple_appearance", selection: $appearance) {
        Text("apple_appearance_system").tag("system")
        Text("apple_appearance_light").tag("light")
        Text("apple_appearance_dark").tag("dark")
      }.pickerStyle(.segmented)
      Section("mac_list_display_settings") {
        Toggle("mac_fidelity_thumbnail_title", isOn: $thumbnails).toggleStyle(.switch)
        Picker("folder_list_layout", selection: $folderLayout) {
          Text("folder_list_flat").tag("flat")
          Text("folder_list_tree").tag("folders")
        }
      }
    }
    .formStyle(.grouped)
  }
}

private struct MacLanguageSettings: View {
  let languageName: String
  @State private var failed = false
  var body: some View {
    Form {
      Section {
        LabeledContent("apple_language", value: languageName)
        Button("apple_language_open_settings") {
          failed = !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
      } footer: {
        Text(failed ? "mac_language_open_failed" : "mac_language_system_note").foregroundStyle(failed ? DuckRole.failure : .secondary)
      }
    }
    .formStyle(.grouped)
  }
}

private struct MacAboutSettings: View {
  var body: some View {
    Form {
      LabeledContent("settings_version", value: DuckSettingsValues.version)
      Section("updates_title") { UpdateSettings() }
      Link("official_website", destination: URL(string: "https://backupduck.app")!)
    }
    .formStyle(.grouped)
  }
}

/// Advanced: clearing caches that otherwise clear themselves.
private struct MacAdvancedSettings: View {
  @ObservedObject var model: BackupModel
  @State private var thumbnailBytes = MacThumbnailTables.usage
  var body: some View {
    Form {
      Section {
        LabeledContent("settings_temp_files") {
          HStack {
            Text(model.storage.map { ByteCountFormatter.string(fromByteCount: Int64($0.used_bytes), countStyle: .file) } ?? "—").foregroundStyle(.secondary)
            Button("settings_clear_now") { Task { await model.reclaimCache(reportResult: true) } }.disabled(!model.ready || model.reclaimingCache)
          }
        }
      } footer: {
        Text(model.cacheReclaimResult.map { LocalizedStringKey($0) } ?? "settings_temp_files_note").foregroundStyle(.secondary)
      }
      Section {
        LabeledContent("settings_thumbnails") {
          HStack {
            Text(ByteCountFormatter.string(fromByteCount: Int64(thumbnailBytes), countStyle: .file)).foregroundStyle(.secondary)
            Button("settings_clear_now") { Task { await MacThumbnailTables.clear(); thumbnailBytes = MacThumbnailTables.usage } }
          }
        }
      } footer: {
        Text("settings_thumbnails_note").foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .task(id: model.ready) { if model.ready { await model.refreshStorage() } }
  }
}

/// A6: task-owned album choices keep immediate persistence and system Done.
private struct MacScopeEditorSheet: View {
  let destination: BackupScopeDestination
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    DuckSheetLayout(title: destination == .types ? "settings_media_types" : "settings_albums") {
      BackupScopeEditor(destination: destination).frame(minHeight: 440)
    } actions: {
      Button("settings_done") { dismiss() }.duckPrimaryAction()
    }
  }
}

import AppKit
import SwiftUI

enum MacSettingsSection: String { case backup, cache, diagnostics, help }
enum MacSettingsRoute: String {
  case cache, logRetention, listDisplay, diagnostics, language, help, about
  case helpConnection, helpLibrary, helpFolders, helpBackground, helpResults, helpRecovery, helpPermissions
  var title: String {
    switch self {
    case .cache: "settings_cache"
    case .logRetention: "settings_log_retention"
    case .listDisplay: "mac_list_display_settings"
    case .diagnostics: "activity_log"
    case .language: "apple_language"
    case .help: "help_title"
    case .about: "about_title"
    case .helpConnection: "mac_fidelity_help_connection"
    case .helpLibrary: "mac_fidelity_help_library"
    case .helpFolders: "mac_fidelity_help_folders"
    case .helpBackground: "mac_fidelity_help_background"
    case .helpResults: "mac_fidelity_help_results"
    case .helpRecovery: "mac_fidelity_help_recovery"
    case .helpPermissions: "mac_fidelity_help_permissions"
    }
  }
  var isHelpTopic: Bool { rawValue.hasPrefix("help") && self != .help }
}

struct MacPreferences: View {
  @ObservedObject var model: BackupModel
  @ObservedObject var folders: FolderSources
  var showFolders: (() -> Void)? = nil
  var titleChanged: (String) -> Void = { _ in }
  @Environment(\.openWindow) private var openWindow
  @State private var route: MacSettingsRoute?
  @State private var renaming = false
  @AppStorage("macListThumbnails") private var thumbnails = true
  @AppStorage("macFolderListLayout") private var folderLayout = "flat"
  @AppStorage("duckAppearance") private var appearance = "system"
  @State private var languageOpenFailed = false
  @MainActor init(model: BackupModel, folders: FolderSources? = nil, showFolders: (() -> Void)? = nil,
    titleChanged: @escaping (String) -> Void = { _ in }, initialRoute: MacSettingsRoute? = nil) {
    self.model = model; self.folders = folders ?? .shared; self.showFolders = showFolders; self.titleChanged = titleChanged
    _route = State(initialValue: initialRoute)
  }
  private func cacheBytes(_ bytes: UInt64) -> String {
    if bytes == 0 { return "0 KB" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file; formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(clamping: bytes))
  }
  private var languageName: String {
    Locale.current.localizedString(forLanguageCode: Bundle.main.preferredLocalizations.first ?? "en") ?? "—"
  }
  var body: some View {
    Group {
      if route == .diagnostics {
        VStack(alignment: .leading, spacing: 16) { backButton; ActivityLogView(embedded: true) }.padding(28)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if let route {
              backButton
              detail(route)
            } else {
              VStack(alignment: .leading, spacing: 8) {
                Text("nav_settings").font(.system(size: 26, weight: .semibold))
                Text("mac_settings_simple_note").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
              }
              mainCards
            }
          }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }.background(DuckColors.canvas).tint(DuckColors.action)
      .onAppear {
        if UserDefaults.standard.string(forKey: "macRequestedSettingsRoute") == "about" { showAbout() }
        titleChanged(route?.title ?? "nav_settings")
      }
      .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowAbout"))) { _ in showAbout() }
      .onChange(of: route) { _, value in titleChanged(value?.title ?? "nav_settings") }
      .sheet(isPresented: $renaming) { DeviceNameEditor(model: model, name: model.deviceSnapshot?.device.name ?? "") }
  }
  private var mainCards: some View {
    VStack(alignment: .leading, spacing: 20) {
    HStack(alignment: .top, spacing: 20) {
      VStack(alignment: .leading, spacing: 20) {
        settingsCard("device_identity") {
          settingsLink("device_this_device", value: model.deviceSnapshot?.device.name ?? "—", first: true) { renaming = true }
            .disabled(model.deviceSnapshot == nil || model.savingDevice).accessibilityIdentifier("device.rename")
          if let error = model.deviceError {
            DuckNotice(title: LocalizedStringKey(error), tone: .failure)
            Button("retry_task") { Task { await model.refreshDeviceStatus() } }.duckSecondaryAction()
          }
        }
        settingsCard("nav_library") {
          PreviewCloudSetting().padding(.horizontal, 20).frame(minHeight: DuckPreferenceMetrics.rowHeight)
        }
        settingsCard("apple_local_storage") {
          settingsLink("settings_cache", value: model.storage.map {
            "\(cacheBytes($0.used_bytes)) / \(cacheBytes($0.settings.cache_budget_bytes))"
          }, first: true) { route = .cache }.accessibilityIdentifier("settings.cache")
        }

      }.frame(maxWidth: .infinity)
      VStack(alignment: .leading, spacing: 20) {
        settingsCard("apple_display_language") {
          settingRow("apple_appearance", first: true) {
            MacPreferenceMenu(title: NSLocalizedString("apple_appearance", comment: ""), selection: $appearance,
              options: ["system", "light", "dark"], label: { NSLocalizedString("apple_appearance_" + $0, comment: "") },
              identifier: "settings.appearance").frame(width: 130, height: DuckPreferenceMetrics.desktopControlHeight)
          }
          settingsLink("apple_language", value: languageName) { route = .language }
          settingsLink("mac_list_display_settings") { route = .listDisplay }
        }
        settingsCard("settings_diagnostics") {
          settingsLink("activity_log", first: true) { route = .diagnostics }.accessibilityIdentifier("settings.activity_log")
          settingsLink("settings_log_retention") { route = .logRetention }.accessibilityIdentifier("settings.log_retention")
        }
      }.frame(maxWidth: .infinity)
    }
        settingsCard("apple_help_about") {
          settingsLink("help_title", first: true) { route = .help }
          settingsLink("about_title", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") { route = .about }
        }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  @ViewBuilder private func detail(_ route: MacSettingsRoute) -> some View {
    switch route {
    case .cache:
      MacStoragePanel(model: model)
    case .logRetention:
      MacStoragePanel(model: model, logs: true)
    case .listDisplay:
      settingsCard("mac_list_display_settings") {
        settingRow("mac_fidelity_thumbnail_title", note: "mac_fidelity_thumbnail_note", first: true) {
          Toggle("list_thumbnails", isOn: $thumbnails).labelsHidden().toggleStyle(.switch)
        }
        settingRow("mac_fidelity_file_list_title", note: "mac_fidelity_file_list_note") {
          MacPreferenceMenu(title: NSLocalizedString("folder_list_layout", comment: ""), selection: $folderLayout,
            options: ["flat", "folders"], label: { NSLocalizedString($0 == "flat" ? "folder_list_flat" : "folder_list_tree", comment: "") },
            identifier: "settings.folder_layout").frame(width: 130, height: DuckPreferenceMetrics.desktopControlHeight)
        }
      }
    case .language:
      Text("mac_language_system_note").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
      Text(languageName).font(.system(size: 14))
      Button("apple_language_open_settings", action: openLanguage).duckPrimaryAction()
      if languageOpenFailed { DuckNotice(title: "mac_language_open_failed", tone: .failure) }
    case .help:
      Text("help_title").font(.system(size: 26, weight: .semibold))
      MacPreferenceGroup {
        ForEach([MacSettingsRoute.helpConnection, .helpLibrary, .helpFolders, .helpBackground, .helpResults, .helpRecovery, .helpPermissions], id: \.self) { topic in
          settingsLink(LocalizedStringKey(topic.title)) { self.route = topic }
        }
      }
    case .helpConnection:
      helpGroup("mac_fidelity_help_pair_direction", [("mac_fidelity_help_pair_title", "mac_fidelity_help_pair_note")])
      helpGroup("mac_fidelity_help_network", [("mac_fidelity_help_lan", "mac_receiver_connection_note")])
    case .helpLibrary:
      helpGroup("mac_fidelity_help_new_existing", [("auto_backup_new", "mac_fidelity_help_new_boundary"), ("mac_fidelity_existing_photos_title", "mac_fidelity_help_frozen_history"), ("mac_fidelity_help_selected", "mac_fidelity_help_selected_note")])
    case .helpFolders:
      helpGroup("mac_fidelity_help_source_independent", [("mac_fidelity_help_existing_auto", "mac_fidelity_help_existing_auto_note"), ("folder_rules", "mac_fidelity_help_rules_note"), ("folder_remove", "mac_fidelity_help_remove_note")])
    case .helpBackground:
      helpGroup("mac_fidelity_help_keep_running", [("mac_fidelity_help_close_window", "mac_running_note"), ("pause_backup", "mac_global_pause_note"), ("mac_fidelity_help_history_pause", "mac_fidelity_help_history_pause_note")])
    case .helpResults:
      helpGroup("mac_fidelity_help_three_facts", [("state_received", "mac_fidelity_phase_received"), ("state_published", "mac_fidelity_phase_published"), ("mac_fidelity_help_google", "design_cloud_boundary")])
    case .helpRecovery:
      helpGroup("mac_fidelity_help_recovery_paths", [("state_failed", "mac_fidelity_help_send_retry"), ("state_publication_failed", "mac_fidelity_help_album_retry"), ("logs_export", "mac_fidelity_help_export_path"), ("updates_title", "mac_fidelity_help_update_path")])
    case .helpPermissions:
      helpGroup("mac_fidelity_help_local_access", [("mac_fidelity_help_photo_permission", "mac_fidelity_help_photo_access"), ("mac_fidelity_help_folder_access", "mac_fidelity_help_folder_access_note"), ("settings_cache", "mac_fidelity_help_cache_pressure")])
    case .about:
      Text("about_title").font(.system(size: 26, weight: .semibold))
      MacPreferenceGroup {
      MacPreferenceRow(title: "about_app_version") {
        Text("\(Bundle.main.object(forInfoDictionaryKey: "BackupDuckReleaseVersion") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
          .foregroundStyle(DuckColors.textSecondary).monospacedDigit()
      }
        .accessibilityIdentifier("about.version")
      }
      MacContentSection(title: "updates_title") { UpdateSettings() }
      Link("official_website", destination: URL(string: "https://backupduck.app")!)
        .duckSecondaryAction().accessibilityIdentifier("about.website")
    case .diagnostics: EmptyView()
    }
  }
  private var backButton: some View {
    Button {
      if route?.isHelpTopic == true { route = .help } else { route = nil }
    } label: { Label("mac_fidelity_back", systemImage: "chevron.left") }
      .buttonStyle(.plain).foregroundStyle(DuckColors.action).frame(minHeight: 32).accessibilityIdentifier("settings.back")
  }
  private func showAbout() {
    UserDefaults.standard.removeObject(forKey: "macRequestedSettingsRoute")
    route = .about
  }
  private func settingsCard<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) -> some View {
    MacPreferenceGroup(title: title, content: content)
  }
  private func settingRow<Control: View>(_ title: LocalizedStringKey, note: LocalizedStringKey? = nil, first: Bool = false, symbol: String? = nil,
    @ViewBuilder control: @escaping () -> Control) -> some View {
    MacPreferenceRow(title: title, note: note, first: first, control: control)
  }
  private func settingsLink(_ title: LocalizedStringKey, note: LocalizedStringKey? = nil, value: String? = nil, first: Bool = false, symbol: String = "gearshape",
    action: @escaping () -> Void) -> some View {
    Button(action: action) {
      settingRow(title, note: note, first: first, symbol: symbol) {
        MacPreferenceValue(value: value)
      }.contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
  private func helpGroup(_ title: LocalizedStringKey, _ rows: [(String, String)]) -> some View {
    settingsCard(title) {
      ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
        settingRow(LocalizedStringKey(row.0), note: LocalizedStringKey(row.1), first: index == 0) { EmptyView() }
          .textSelection(.enabled)
      }
    }
  }
  private func openLanguage() {
    languageOpenFailed = !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
  private func manageFolders() {
    if let showFolders { showFolders() }
    else {
      UserDefaults.standard.set("sources", forKey: "macRequestedDestination")
      openWindow(id: "main")
      NotificationCenter.default.post(name: Notification.Name("BackupDuckShowFolders"), object: nil)
    }
  }
}

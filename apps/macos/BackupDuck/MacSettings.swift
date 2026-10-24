import AppKit
import SwiftUI

/// Settings as defined in `design/settings.md`, in the Mac dialect System
/// Settings uses: a list column (identity header, category rows
/// with values, help last, quiet footer) and a detail pane with a grouped form.
struct MacSettings: View {
  enum Page: Hashable { case devices, folders, autoBackup, appearance, language, help, about, diagnostics, advanced }

  @ObservedObject var model: BackupModel
  @ObservedObject var folders: FolderSources
  var showFolders: () -> Void
  var scopeStore: BackupScopeStore
  var albumsModel: ScopeAlbumsModel
  var initialScopeDestination: BackupScopeDestination?
  var initialScopeSearch: String
  var initialDiagnosticsPage: String?
  var openInitialDetail: ((DuckSettingsNavigator) -> Void)?
  var updateSection: MacUpdateSection?
  @State private var openedInitialDetail = false
  @AppStorage("duckAppearance") private var appearance = "system"
  @State private var page: Page? = .autoBackup
  /// Pages opened below the selected category, inside the detail pane.
  @State private var pages: [DuckSettingsPage] = []
  @State private var renaming = false
  @State private var retrying = false
  @State private var connecting = false
  private var values: DuckSettingsValues { DuckSettingsValues(model: model) }

  @MainActor init(model: BackupModel, folders: FolderSources, showFolders: @escaping () -> Void,
    initialPage: Page? = nil, scopeStore: BackupScopeStore? = nil,
    albumsModel: ScopeAlbumsModel? = nil, initialScopeDestination: BackupScopeDestination? = nil, initialScopeSearch: String = "", initialDiagnosticsPage: String? = nil, openInitialDetail: ((DuckSettingsNavigator) -> Void)? = nil, updateSection: MacUpdateSection? = nil) {
    self.openInitialDetail = openInitialDetail; self.updateSection = updateSection
    self.initialDiagnosticsPage = initialDiagnosticsPage
    self.model = model; self.folders = folders; self.showFolders = showFolders
    self.scopeStore = scopeStore ?? .shared; self.albumsModel = albumsModel ?? .shared
    self.initialScopeDestination = initialScopeDestination; self.initialScopeSearch = initialScopeSearch
    _page = State(initialValue: initialPage ?? (folders.initialSettingsFolder != nil || folders.initialSheet == "rules" || folders.previewSettings ? .folders : .autoBackup))
  }

  var body: some View {
    HStack(spacing: 0) {
      list.frame(width: DuckSettingsMetrics.listWidth)
      Divider()
      detail.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .task { if model.deviceSnapshot == nil { await model.refreshDeviceStatus() } }
    .onAppear {
      guard !openedInitialDetail else { return }
      openedInitialDetail = true
      // Start routes use the same pane navigator as interactive links.
      if let destination = initialScopeDestination, page == .autoBackup, pages.isEmpty {
        navigator.open(DuckSettingsPage(title: Text(LocalizedStringKey(destination.title)), content: AnyView(
          BackupScopeEditor(destination: destination, store: scopeStore, model: albumsModel, search: destination == .albums ? initialScopeSearch : ""))))
      }
      openInitialDetail?(navigator)
    }
    // Row geometry from DuckSettingsMetrics (design/visual-language.md, V7):
    // the category list through the list row default, detail forms through the row styles.
    .buttonStyle(.bordered)
    .environment(\.defaultMinListRowHeight, DuckSettingsMetrics.rowHeight)
    .labeledContentStyle(DuckPreferenceRowStyle())
    .toggleStyle(DuckPreferenceToggleStyle())
    .task(id: model.ready) { if model.ready { await model.refreshStorage() } }
    .onAppear { consumeAboutRequest() }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowAbout"))) { _ in
      page = .about
      UserDefaults.standard.removeObject(forKey: "macRequestedSettingsRoute")
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckFolderSettings"))) { _ in page = .folders }
    .sheet(isPresented: $renaming) { DeviceNameEditor(model: model, name: model.deviceSnapshot?.device.name ?? "") }
  }

  private func consumeAboutRequest() {
    guard UserDefaults.standard.string(forKey: "macRequestedSettingsRoute") == "about" else { return }
    page = .about
    UserDefaults.standard.removeObject(forKey: "macRequestedSettingsRoute")
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
        row(.folders, "settings_folders", "folder", DuckGlyph.teal,
          String(format: NSLocalizedString("settings_folders_value", comment: ""), folders.sources.count))
      }
      Section {
        row(.appearance, "apple_appearance", "circle.lefthalf.filled", DuckGlyph.indigo,
          NSLocalizedString("apple_appearance_" + appearance, comment: ""))
        row(.language, "apple_language", "globe", DuckGlyph.teal, languageName)
      }
      Section {
        row(.help, "settings_help_center", "questionmark", DuckGlyph.orange, nil)
        DuckFeedbackMenu().selectionDisabled()
        DuckRateBackupDuckRow().selectionDisabled()
      }
      Section {
        row(.about, "about_title", "info", DuckGlyph.gray, DuckSettingsValues.releaseVersion)
      } footer: {
        HStack(spacing: DuckSpacing.xSmall) {
          Button("settings_diagnostics") { page = .diagnostics }.buttonStyle(.link)
            .accessibilityIdentifier("settings.diagnostics")
          Text(verbatim: "·")
          Button("settings_advanced") { page = .advanced }.buttonStyle(.link)
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

  /// The selected category, or the page last opened below it. The list column
  /// and its selection stay; Back (⌘[) returns one page.
  private var navigator: DuckSettingsNavigator {
    DuckSettingsNavigator(open: { pages.append($0) }, back: { _ = pages.popLast() })
  }

  private var detail: some View {
    Group {
      if let top = pages.last { top.content.navigationTitle(top.title).id(pages.count) }
      else { detailContent.navigationTitle(pageTitle) }
    }
    .environment(\.duckSettingsNavigator, navigator)
    .toolbar {
      if !pages.isEmpty {
        ToolbarItem(placement: .navigation) {
          Button(action: navigator.back) { Label("mac_fidelity_back", systemImage: "chevron.left") }
            .labelStyle(.iconOnly).keyboardShortcut("[", modifiers: .command)
            .accessibilityIdentifier("settings.secondary.back")
        }
      }
    }
    .onChange(of: page) { _, _ in pages = [] }
  }

  private var pageTitle: LocalizedStringKey {
    switch page {
    case .folders: "settings_folders"
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
    case .folders: MacFolderSettings(folders: folders, backup: model)
    case .devices:
      DevicePage(model: model) { connecting = true }
        .sheet(isPresented: $connecting) { MacConnectSheet(model: model) }
    case .autoBackup:
      MacAutoBackupSettings(model: model, scope: scopeStore, albums: albumsModel, initialSearch: initialScopeSearch)
    case .appearance: MacAppearanceSettings()
    case .language: MacLanguageSettings(languageName: languageName)
    case .help: HelpCenter()
    case .about: MacAboutSettings(updateSection: updateSection)
    case .diagnostics: DiagnosticsView(model: model, initialPage: initialDiagnosticsPage)
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
  @ObservedObject var scope: BackupScopeStore
  var albums: ScopeAlbumsModel
  var initialSearch: String
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
      Section {
        DuckSettingsLink(title: Text(LocalizedStringKey(BackupScopeDestination.types.title))) { editor(.types) } label: {
          LabeledContent("settings_media_types", value: scope.typesSummary)
        }.accessibilityIdentifier("backup.scope.types")
        DuckSettingsLink(title: Text(LocalizedStringKey(BackupScopeDestination.albums.title))) { editor(.albums) } label: {
          LabeledContent("settings_specific_albums", value: scope.albumsSummary)
        }.accessibilityIdentifier("backup.scope.albums")
      } header: { Text("settings_includes") } footer: {
        if scope.loadFailed { DuckNotice(title: "scope_load_failed", tone: .failure, symbol: "exclamationmark.circle") }
        else { Text("settings_includes_footer") }
      }
      BackupNotificationPreferences()
    }
    .formStyle(.grouped)
    .navigationTitle("settings_auto_backup")
  }
  private func editor(_ destination: BackupScopeDestination) -> BackupScopeEditor {
    BackupScopeEditor(destination: destination, store: scope, model: albums, search: destination == .albums ? initialSearch : "")
  }
}

/// Appearance and how lists look: the display choices together.
private struct MacAppearanceSettings: View {
  @AppStorage("duckAppearance") private var appearance = "system"
  @AppStorage("macListThumbnails") private var thumbnails = true
  var body: some View {
    Form {
      Picker("apple_appearance", selection: $appearance) {
        Text("apple_appearance_system").tag("system")
        Text("apple_appearance_light").tag("light")
        Text("apple_appearance_dark").tag("dark")
      }.pickerStyle(.segmented)
      Section("mac_list_display_settings") {
        Toggle("mac_fidelity_thumbnail_title", isOn: $thumbnails).toggleStyle(.switch)

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
        LabeledContent("apple_language") {
          HStack {
            Text(languageName)
            Button("apple_language_open_settings") {
              // Language & Region, where the per-app language lives; System Settings otherwise.
              failed = !(NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                || NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")))
            }
          }
        }
      } footer: {
        Text(failed ? "mac_language_open_failed" : "mac_language_system_note").foregroundStyle(failed ? DuckRole.failure : .secondary)
      }
    }
    .formStyle(.grouped)
  }
}

struct MacAboutSettings: View {
  var updateSection: MacUpdateSection? = nil
  var body: some View {
    Form {
      DuckAboutIdentitySection()
      DuckAboutAuthorSection()
      if let updateSection { updateSection } else { UpdateSettings() }
      DuckAboutLinksSection()
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
            Button("settings_clear_now") { Task { await model.reclaimCache() } }.disabled(!model.ready || model.reclaimingCache)
              .accessibilityIdentifier("settings.cache.clear")
          }
        }
      } footer: {
        DuckCacheCleanupFooter(error: model.cacheReclaimError)
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

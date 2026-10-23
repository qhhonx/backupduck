import SwiftUI
import UIKit

/// Settings as defined in `design/settings.md`, in the iPhone dialect:
/// identity header, a contextual card, category rows with icon tiles and
/// values, help last and a quiet footer. Used by the app and design catalog.
struct IOSSettings: View {
  @ObservedObject var model: BackupModel
  var showBottom = false
  @AppStorage("duckAppearance") private var appearance = "system"
  @Environment(\.openURL) private var openURL
  @State private var editingName = false
  @State private var diagnostics = false
  @State private var advanced = false
  @State private var retrying = false
  private var values: DuckSettingsValues { DuckSettingsValues(model: model) }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
      Form {
        header
        if model.message != nil && !model.ready { openFailedCard }
        Section {
          // Devices live in Settings (design/navigation.md, D3).
          NavigationLink { IOSDevicePage(model: model) } label: {
            LabeledContent { Text(model.peerDevice?.name ?? NSLocalizedString("settings_pair_first", comment: "")) } label: {
              DuckSettingsLabel(title: "settings_devices", symbol: "smartphone", color: DuckGlyph.green)
            }
          }.accessibilityIdentifier("settings.devices")
          NavigationLink { IOSAutoBackupSettings(model: model) } label: {
            LabeledContent { Text(values.autoBackup) } label: { DuckSettingsLabel(title: "settings_auto_backup", symbol: "arrow.triangle.2.circlepath", color: DuckGlyph.blue) }
          }.accessibilityIdentifier("settings.auto_backup")
        }
        Section {
          Picker(selection: $appearance) {
            Text("apple_appearance_system").tag("system")
            Text("apple_appearance_light").tag("light")
            Text("apple_appearance_dark").tag("dark")
          } label: { DuckSettingsLabel(title: "apple_appearance", symbol: "circle.lefthalf.filled", color: DuckGlyph.indigo) }
            .accessibilityIdentifier("settings.appearance")
          Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          } label: {
            LabeledContent { Text(languageName) } label: { DuckSettingsLabel(title: "apple_language", symbol: "globe", color: DuckGlyph.teal) }
          }
          .foregroundStyle(.primary)
          .accessibilityIdentifier("settings.language")
        }
        Section {
          NavigationLink {
            HelpCenter()
          } label: { DuckSettingsLabel(title: "settings_help_center", symbol: "questionmark", color: DuckGlyph.orange) }
            .accessibilityIdentifier("settings.help")
          DuckFeedbackMenu()
          DuckRateBackupDuckRow()
        }
        Section {
          NavigationLink { IOSAboutSettings() } label: {
            LabeledContent { Text(DuckSettingsValues.releaseVersion) } label: {
              DuckSettingsLabel(title: "about_title", symbol: "info", color: DuckGlyph.gray)
            }
          }.accessibilityIdentifier("settings.about").id("settings.bottom")
        } footer: {
          footer
        }
      }
      .environment(\.defaultMinListRowHeight, DuckPreferenceMetrics.rowHeight)
      .navigationTitle("nav_settings")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("settings_edit") { editingName = true }.disabled(model.deviceSnapshot == nil)
        }
      }
      .navigationDestination(isPresented: $diagnostics) {
        DiagnosticsView(model: model)
      }
      .navigationDestination(isPresented: $advanced) { IOSAdvancedSettings(model: model) }
      .task { if model.deviceSnapshot == nil { await model.refreshDeviceStatus() } }
      .onAppear { if showBottom { proxy.scrollTo("settings.bottom", anchor: .bottom) } }
      }
    }
    .sheet(isPresented: $editingName) {
      if let name = model.deviceSnapshot?.device.name { DeviceNameEditor(model: model, name: name) }
    }
  }

  /// This device, and the device it backs up to.
  private var header: some View {
    Section {
      VStack(spacing: 6) {
        Image(systemName: UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")
          .font(.largeTitle)
          .foregroundStyle(.white)  // design-exception: white glyph on the avatar circle
          .frame(width: 84, height: 84)
          .background(DuckGlyph.blue, in: Circle())
          .accessibilityHidden(true)
          .padding(.bottom, 6)
        Text(model.deviceSnapshot?.device.name ?? "—").font(.title2.weight(.semibold))
        // V1: state as a soft pill with one colored dot.
        DuckPill(title: Text(values.pairedSubtitle ?? NSLocalizedString("settings_pair_first", comment: "")),
          dot: model.pairing == nil ? Color.secondary : model.hubStatus.isProblem ? DuckRole.attention : DuckRole.saved)
          .padding(.top, 2)
      }
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)
      .accessibilityElement(children: .combine)
    }
    .listRowBackground(Color.clear)
  }

  /// The engine failed to open: the cause and one action, said once (I3).
  private var openFailedCard: some View {
    Section {
      DuckStateCard(symbol: "exclamationmark.triangle.fill", tone: DuckRole.attention, title: Text("settings_open_failed"),
        note: model.message.flatMap { $0 == NSLocalizedString("pairing_unlock_wait", comment: "") ? nil : Text($0) }, action: {
        DuckTintedButton("retry_task") {
          guard !retrying else { return }
          retrying = true
          Task { await model.open(); retrying = false }
        }.disabled(retrying)
      })
    }
    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
  }

  private var footer: some View {
    HStack(spacing: DuckSpacing.xSmall) {
      Button("settings_diagnostics") { diagnostics = true }
      Text(verbatim: "·").foregroundStyle(.secondary)
      Button("settings_advanced") { advanced = true }
    }.font(.footnote)
    .frame(maxWidth: .infinity)
    .padding(.top, 24)
  }

  private var languageName: String {
    Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "—"
  }
}

/// Auto Backup: the switch and what it includes.
private struct IOSAutoBackupSettings: View {
  @ObservedObject var model: BackupModel
  @ObservedObject private var scope = BackupScopeStore.shared
  var body: some View {
    Form {
      Section {
        Toggle("settings_auto_switch", isOn: Binding(get: { model.autoBackup }, set: { value in Task { await model.setAutoBackup(value) } }))
          .disabled(!model.ready || model.pairing == nil || model.changingAutoBackup)
      } footer: {
        if let error = model.autoBackupError {
          DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
        } else if model.ready {
          Text(model.pairing == nil ? NSLocalizedString("settings_auto_footer_unpaired", comment: "")
            : String(format: NSLocalizedString("settings_auto_footer", comment: ""), DuckSettingsValues(model: model).receiverName))
        }
      }
      Section {
        NavigationLink { BackupScopeEditor(destination: .types) } label: {
          LabeledContent("settings_media_types", value: scope.typesSummary)
        }
        NavigationLink { BackupScopeEditor(destination: .albums) } label: {
          LabeledContent("settings_specific_albums", value: scope.albumsSummary)
        }
      } header: {
        Text("settings_includes")
      } footer: {
        if scope.loadFailed { DuckNotice(title: "scope_load_failed", tone: .failure, symbol: "exclamationmark.circle") } else { Text("settings_includes_footer") }
      }
      BackupNotificationPreferences()
    }
    .navigationTitle("settings_auto_backup")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Advanced: clearing caches that otherwise clear themselves.
private struct IOSAdvancedSettings: View {
  @ObservedObject var model: BackupModel
  @State private var thumbnailBytes: Int?
  @State private var clearingThumbnails = false
  var body: some View {
    Form {
      Section {
        LabeledContent("settings_temp_files", value: model.storage.map { ByteCountFormatter.string(fromByteCount: Int64($0.used_bytes), countStyle: .file) } ?? "—")
        Button("settings_clear_now") { Task { await model.reclaimCache(reportResult: true) } }
          .disabled(!model.ready || model.reclaimingCache)
      } footer: {
        Text(model.cacheReclaimResult.map { LocalizedStringKey($0) } ?? "settings_temp_files_note")
      }
      Section {
        LabeledContent("settings_thumbnails", value: thumbnailBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—")
        Button("settings_clear_now") {
          clearingThumbnails = true
          Task { _ = await ThumbnailDiskCache.shared.removeAll(); thumbnailBytes = await ThumbnailDiskCache.shared.usage(); clearingThumbnails = false }
        }.disabled(clearingThumbnails)
      } footer: {
        Text("settings_thumbnails_note")
      }
    }
    .navigationTitle("settings_advanced")
    .navigationBarTitleDisplayMode(.inline)
    .task { thumbnailBytes = await ThumbnailDiskCache.shared.usage() }
    .task(id: model.ready) { if model.ready { await model.refreshStorage() } }
  }
}

private struct IOSAboutSettings: View {
  var body: some View {
    Form {
      DuckAboutAuthorSection()
      Section { DuckAboutVersionLabel() }
      DuckAboutLinksSection()
    }
    .navigationTitle("about_title")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// A settings sub-page by name, so the design catalog can open it directly.
struct IOSSettingsDetail: View {
  let name: String
  @ObservedObject var model: BackupModel
  var body: some View {
    switch name {
    case "devices": IOSDevicePage(model: model)
    case "autoBackup": IOSAutoBackupSettings(model: model)
    case "advanced": IOSAdvancedSettings(model: model)
    case "about": IOSAboutSettings()
    case "help": HelpCenter()
    case let topic where topic.hasPrefix("help."):
      if let found = (HelpCenter.tasks + HelpCenter.problems).first(where: { "help." + $0.id == topic }) { HelpArticle(topic: found) }
    default: ContentUnavailableView(name, systemImage: "questionmark")
    }
  }
}

/// The shared device page with the iPhone's connect sheet.
struct IOSDevicePage: View {
  @ObservedObject var model: BackupModel
  @State private var connecting = false
  var body: some View {
    DevicePage(model: model) { connecting = true }
      .sheet(isPresented: $connecting) { IOSConnectSheet(model: model, reconnect: false) }
  }
}

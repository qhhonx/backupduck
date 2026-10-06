import SwiftUI

struct IOSSettingsPage: View {
  @ObservedObject var model: BackupModel
  @State private var logs = false
  var body: some View {
    NavigationStack {
      Form {
        Section("device_identity") { DeviceIdentitySettings(model: model) }
        Section {
          NavigationLink {
            IOSBackupPreferences(model: model)
          } label: {
            Label("backup_settings", systemImage: "arrow.triangle.2.circlepath")
          }
          NavigationLink {
            Form { Section { StoragePreferences(model: model, scope: .cache) } }
              .navigationTitle("settings_cache").navigationBarTitleDisplayMode(.inline)
          } label: {
            Label("settings_cache", systemImage: "internaldrive")
          }
          .accessibilityIdentifier("settings.cache")
        }
        Section("settings_diagnostics") {
          Button {
            logs = true
          } label: {
            Label("activity_log", systemImage: "list.bullet.rectangle")
          }
          .buttonStyle(.borderless).accessibilityIdentifier("settings.activity_log")
          NavigationLink {
            Form { Section { StoragePreferences(model: model, scope: .logs) } }
              .navigationTitle("settings_log_retention").navigationBarTitleDisplayMode(.inline)
          } label: {
            Label("settings_log_retention", systemImage: "clock.arrow.circlepath")
          }
        }
        Section {
          NavigationLink { BackupHelp() } label: {
            Label("help_title", systemImage: "questionmark.circle")
          }.accessibilityIdentifier("settings.help")
          LabeledContent(
            "settings_version",
            value: "\(Bundle.main.object(forInfoDictionaryKey: "BackupDuckReleaseVersion") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
          Text("settings_about_description").font(.footnote).foregroundStyle(.secondary)
        } header: {
          Text("brand_name")
        }
      }.scrollContentBackground(.hidden)
      .background(DuckColors.canvas)
      .navigationTitle("nav_settings")
    }.sheet(isPresented: $logs) { ActivityLogView() }
  }
}

private struct IOSBackupPreferences: View {
  @ObservedObject var model: BackupModel
  @AppStorage("keepScreenAwakeDuringBackup") private var keepScreenAwake = false
  var body: some View {
    Form {
      Section {
        Toggle(
          "auto_backup_new",
          isOn: Binding(
            get: { model.autoBackup },
            set: { enabled in
              Task { await model.setAutoBackup(enabled) }
            })
        ).disabled(!model.ready || model.pairing == nil || model.changingAutoBackup)
        if model.discoveryPending > 0 {
          LabeledContent("discovery_pending", value: model.discoveryPending.formatted())
        }
        if model.historyUnavailable { Text("error_history_unavailable").foregroundStyle(.orange) }
      } footer: {
        Text("auto_backup_explanation")
      }
      TransferConcurrencySettings(model: model)
      HistoricalImportSettings(model: model)
      Section {
        Toggle("keep_screen_awake_during_backup", isOn: $keepScreenAwake)
      } footer: {
        Text("keep_screen_awake_explanation")
      }
      Section {
        Label("wifi_only", systemImage: "wifi")
        Text("background_explanation").foregroundStyle(.secondary)
        Text("background_force_quit").foregroundStyle(.secondary)
      } header: {
        Text("background_section")
      }
    }.navigationTitle("backup_settings").navigationBarTitleDisplayMode(.inline)
  }
}

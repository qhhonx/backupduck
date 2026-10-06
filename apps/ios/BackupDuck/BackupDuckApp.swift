import SwiftUI

@main struct BackupDuckApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = BackupModel.shared
  @StateObject private var library = PhotoLibraryModel()
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("keepScreenAwakeDuringBackup") private var keepScreenAwake = false
  private var shouldKeepScreenAwake: Bool {
    keepScreenAwake && scenePhase == .active && model.ready && !model.paused
      && model.pairing != nil && !model.waitingForNetwork && !model.receiverUnavailable
      && (model.importing || model.summary.running > 0 || model.summary.queued > 0
        || model.pendingImports > 0 || model.discoveryPending > 0)
  }
  var body: some Scene {
    WindowGroup {
      TabView {
        IOSLibraryPage(library: library, model: model).tabItem {
          Label("nav_library", systemImage: "photo.on.rectangle")
        }
        IOSBackupPage(model: model).tabItem {
          Label("nav_backup", systemImage: "arrow.triangle.2.circlepath")
        }
        IOSReceiverPage(model: model).tabItem {
          Label("nav_receiver", systemImage: "externaldrive.badge.wifi")
        }
        IOSSettingsPage(model: model).tabItem {
          Label("nav_settings", systemImage: "gearshape")
        }
      }.tint(DuckColors.action).task { await model.open() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = shouldKeepScreenAwake }
        .onChange(of: shouldKeepScreenAwake) { _, awake in
          UIApplication.shared.isIdleTimerDisabled = awake
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
          if phase == .active {
            BackgroundTransfer.shared.enteredForeground()
            Task { await library.open() }
            Task { await model.becameActive() }
          }
          if phase == .background {
            UIApplication.shared.isIdleTimerDisabled = false
            BackgroundTransfer.shared.enteredBackground()
            model.scheduleBackgroundWork()
          }
        }
    }
  }
}

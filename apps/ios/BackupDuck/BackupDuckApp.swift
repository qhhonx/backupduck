import SwiftUI

@main struct BackupDuckApp: App {
  init() {
    LaunchTrace.mark("app init")
    PhotoLibraryModel.prewarm()
    if #available(iOS 26.0, *) { } else {
      // Legacy scroll-edge appearance must not turn transparent above media.
      let appearance = UITabBarAppearance()
      appearance.configureWithOpaqueBackground()
      appearance.backgroundColor = UIColor(DuckColors.surface)
      UITabBar.appearance().standardAppearance = appearance
      UITabBar.appearance().scrollEdgeAppearance = appearance
    }
  }
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var selectedTab = 0
  @StateObject private var model = BackupModel.shared
  @StateObject private var library = PhotoLibraryModel()
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("keepScreenAwakeDuringBackup") private var keepScreenAwake = false
  @AppStorage("duckAppearance") private var appearance = "system"
  private var colorScheme: ColorScheme? {
    appearance == "dark" ? .dark : appearance == "light" ? .light : nil
  }
  private var shouldKeepScreenAwake: Bool {
    keepScreenAwake && scenePhase == .active && model.ready && !model.paused
      && model.pairing != nil && !model.waitingForNetwork && !model.receiverUnavailable
      && (model.importing || model.summary.running > 0 || model.summary.queued > 0
        || model.pendingImports > 0 || model.discoveryPending > 0)
  }
  var body: some Scene {
    WindowGroup {
      TabView(selection: $selectedTab) {
        IOSLibraryPage(library: library, model: model).duckTabSurface().tabItem { IOSAppTab.library.label }.tag(IOSAppTab.library.rawValue)
        IOSBackupPage(model: model).duckTabSurface().tabItem { IOSAppTab.backup.label }.tag(IOSAppTab.backup.rawValue)
        IOSReceiverPage(model: model).duckTabSurface().tabItem { IOSAppTab.receiver.label }.tag(IOSAppTab.receiver.rawValue)
        IOSSettingsPage(model: model).duckTabSurface().tabItem { IOSAppTab.settings.label }.tag(IOSAppTab.settings.rawValue)
      }.duckLibraryTabMinimization(selected: selectedTab == IOSAppTab.library.rawValue).background(DuckColors.canvas.ignoresSafeArea()).preferredColorScheme(colorScheme).tint(DuckColors.action).task { await model.open() }
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

import SwiftUI

@main struct BackupDuckApp: App {
  init() {
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
        IOSLibraryPage(library: library, model: model).duckTabSurface().tabItem {
          Label("nav_library", systemImage: "photo.on.rectangle")
        }.tag(0)
        IOSBackupPage(model: model).duckTabSurface().tabItem {
          Label("nav_backup", systemImage: "arrow.triangle.2.circlepath")
        }.tag(1)
        IOSReceiverPage(model: model).duckTabSurface().tabItem {
          Label("nav_receiver", systemImage: "externaldrive.badge.wifi")
        }.tag(2)
        IOSSettingsPage(model: model).duckTabSurface().tabItem {
          Label("nav_settings", systemImage: "gearshape")
        }.tag(3)
      }.duckLibraryTabMinimization(selected: selectedTab == 0).background(DuckColors.canvas.ignoresSafeArea()).preferredColorScheme(colorScheme).tint(DuckColors.action).task { await model.open() }
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

extension View {
  @ViewBuilder func duckLibraryTabMinimization(selected: Bool) -> some View {
    if #available(iOS 26.0, *) { self.tabBarMinimizeBehavior(selected ? .onScrollUp : .never) }
    else { self }
  }
  @ViewBuilder func duckTabSurface() -> some View {
    if #available(iOS 26.0, *) { self }
    else {
      self.toolbarBackground(DuckColors.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
  }
  @ViewBuilder func duckLibraryViewport() -> some View {
    if #available(iOS 26.0, *) { self.ignoresSafeArea(.container, edges: .bottom) }
    else { self }
  }
}

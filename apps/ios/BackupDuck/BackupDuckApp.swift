import SwiftUI

@main struct BackupDuckApp: App {
  init() {
    LaunchTrace.mark("app init")
    // The redesigned pages are the app (design/redesign-roadmap.md, step 6).
    DesignPreview.proposedDesign = true
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
  @State private var activityReceiver: String?
  @State private var notification: BackupNotifier.Route?
  @StateObject private var model = BackupModel.shared
  @StateObject private var library = PhotoLibraryModel()
  @StateObject private var notifier = BackupNotifier.shared
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("keepScreenAwakeDuringBackup") private var keepScreenAwake = false
  @AppStorage("duckAppearance") private var appearance = "system"
  /// First run is shown once, to people who have not connected a Pixel yet.
  @AppStorage("firstRunDone") private var firstRunDone = false
  private var colorScheme: ColorScheme? {
    appearance == "dark" ? .dark : appearance == "light" ? .light : nil
  }
  private var shouldKeepScreenAwake: Bool {
    keepScreenAwake && scenePhase == .active && model.ready && !model.paused
      && model.pairing != nil && !model.waitingForNetwork && !model.receiverUnavailable
      && (model.importing || model.summary.running > 0 || model.summary.queued > 0
        || model.pendingImports > 0 || model.discoveryPending > 0)
  }
  /// Undecided until the engine has opened, so people who already connected a
  /// Pixel never see first run flash by.
  private var needsFirstRun: Bool? {
    if firstRunDone { return false }
    guard model.ready else { return nil }
    return model.pairing == nil
  }
  private var tabs: some View {
    TabView(selection: $selectedTab) {
      // Three positions (design/navigation.md): Photos, Backup, Settings.
      IOSLibraryPage(library: library, model: model).duckTabSurface()
        .tabItem { IOSAppTab.library.proposedLabel }.tag(IOSAppTab.library.rawValue)
      IOSHub(model: model, notification: $notification, showLibrary: { view in
        selectedTab = IOSAppTab.library.rawValue
        Task { await library.changeBackupView(view) }
      }).duckTabSurface().tabItem { IOSAppTab.backup.proposedLabel }.tag(IOSAppTab.backup.rawValue)
      IOSSettings(model: model).duckTabSurface()
        .tabItem { IOSAppTab.settings.proposedLabel }.tag(IOSAppTab.settings.rawValue)
    }
    .onChange(of: model.pairing?.receiverID, initial: true) { _, receiver in library.backupReceiver = receiver }
  }
  var body: some Scene {
    WindowGroup {
      Group {
        // First run stands alone until it ends; nothing behind it reads the
        // photo library before the user has heard why (design/flows.md).
        switch needsFirstRun {
        case .some(true): IOSOnboarding(model: model) { firstRunDone = true }
        case .some(false): tabs
        case .none:
          if let message = model.message {
            ContentUnavailableView {
              Label("settings_open_failed", systemImage: "exclamationmark.triangle")
            } description: {
              Text(message)
            } actions: {
              Button("retry_task") { Task { await model.open() } }.duckPrimaryButton()
            }
          } else { DuckLoadingState("hub_opening") }
        }
      }
        .onChange(of: model.ready) { _, ready in
          if ready && model.pairing != nil { firstRunDone = true }
          consumeNotification()
          consumeActivityLink()
        }
        .onChange(of: notifier.route, initial: true) { _, _ in consumeNotification() }
        .onOpenURL { url in
          guard url.scheme == "backupduck", url.host == "backup",
            let receiver = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "receiver" })?.value else { return }
          activityReceiver = receiver
          consumeActivityLink()
        }
        .duckLibraryTabMinimization(selected: selectedTab == IOSAppTab.library.rawValue).background(DuckRole.background.ignoresSafeArea()).preferredColorScheme(colorScheme).tint(DuckColors.action).task {
          await model.open()
          BackupNotifier.shared.start(model)
          BackupLiveActivity.shared.start(model)
        }
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
            Task { await BackupLiveActivity.shared.synchronize(model) }
          }
          if phase == .background {
            UIApplication.shared.isIdleTimerDisabled = false
            BackgroundTransfer.shared.enteredBackground()
            model.scheduleBackgroundWork()
          }
        }
    }
  }

  private func consumeNotification() {
    guard model.ready, let route = notifier.route else { return }
    guard notifier.takeRoute(receiver: model.pairing?.receiverID) != nil else { return }
    selectedTab = IOSAppTab.backup.rawValue
    notification = route
  }

  private func consumeActivityLink() {
    guard model.ready, let receiver = activityReceiver else { return }
    activityReceiver = nil
    if model.pairing?.receiverID == receiver { selectedTab = IOSAppTab.backup.rawValue }
  }
}

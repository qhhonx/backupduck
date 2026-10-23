import AppKit
import SwiftUI

@main struct BackupDuckMacApp: App {
  @Environment(\.openWindow) private var openWindow
  @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
  @StateObject private var model = BackupModel.shared
  @StateObject private var notifier = BackupNotifier.shared
  @StateObject private var library = PhotoLibraryModel()
  @AppStorage("duckAppearance") private var appearance = "system"
  private var colorScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
  /// Starts the photo list fetch before the first window, as on iPhone. The
  /// redesigned pages are the app (design/redesign-roadmap.md, step 6).
  init() {
    BackupNotifier.shared.configure()
    PhotoLibraryModel.prewarm()
  }
  var body: some Scene {
    Window("brand_name", id: "main") {
      MacWorkspace(model: model, library: library)
        .preferredColorScheme(colorScheme)
        .frame(minWidth: 900, minHeight: 620)
        .task { await model.open(); BackupNotifier.shared.start(model); await AppUpdater.shared.start() }
        .task { await library.open() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
          Task { await library.open() }
        }
    }.defaultSize(width: 1180, height: 800)
      .commands {
        MacFolderCommands()
        CommandGroup(replacing: .appInfo) {
          Button("about_title") { MacAboutNavigation.open { openWindow(id: "main") } }
        }
        MacSettingsCommands()
      }
    MenuBarExtra {
      MacStatusMenu(model: model)
    } label: {
      Image(nsImage: MacMenuStatus(model: model).isBackingUp ? MacMenuBarIcon.activeImage : MacMenuBarIcon.image).renderingMode(.template).accessibilityLabel(Text("brand_name"))
        // The menu-bar label stays mounted after the workspace window closes.
        // Reveal that same scene before its receiver-scoped consumer takes a tap.
        .onChange(of: notifier.route, initial: true) { _, route in
          guard route != nil else { return }
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        }
    }.menuBarExtraStyle(.menu)
  }
}
final class MacAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag {
      sender.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil)
    }
    return true
  }
}

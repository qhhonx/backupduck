import AppKit
import SwiftUI

@main struct BackupDuckMacApp: App {
  @Environment(\.openWindow) private var openWindow
  @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
  @StateObject private var model = BackupModel.shared
  @StateObject private var library = PhotoLibraryModel()
  @AppStorage("duckAppearance") private var appearance = "system"
  private var colorScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
  /// Starts the photo list fetch before the first window, as on iPhone. The
  /// redesigned pages are the app (design/redesign-roadmap.md, step 6).
  init() {
    DesignPreview.proposedDesign = true
    PhotoLibraryModel.prewarm()
  }
  var body: some Scene {
    Window("brand_name", id: "main") {
      MacWorkspace(model: model, library: library)
        .preferredColorScheme(colorScheme)
        .frame(minWidth: 900, minHeight: 620)
        .task { await model.open(); await AppUpdater.shared.start() }
        .task { await library.open() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
          Task { await library.open() }
        }
    }.defaultSize(width: 1180, height: 800)
      .commands {
        CommandGroup(replacing: .appInfo) {
          Button("about_title") { MacAboutNavigation.open { openWindow(id: "main") } }
        }
      }
    Settings {
      MacPreferences(model: model).preferredColorScheme(colorScheme).frame(width: 760, height: 700)
    }
    MenuBarExtra {
      MacStatusMenu(model: model)
    } label: {
      Image(nsImage: MacMenuBarIcon.image).renderingMode(.template).accessibilityLabel(Text("brand_name"))
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

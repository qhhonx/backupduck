import AppKit
import SwiftUI

enum MacMenuBarIcon {
  /// A static system symbol distinguishes work without a timer or animation loop.
  static let activeImage: NSImage = {
    let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) ?? NSImage()
    image.isTemplate = true
    return image
  }()

  static let image: NSImage = {
    guard let url = Bundle.main.url(forResource: "DuckMenuBar", withExtension: "pdf"),
      let image = NSImage(contentsOf: url) else { return NSImage() }
    image.size = NSSize(width: 20, height: 20)
    image.isTemplate = true
    return image
  }()
}

/// Reuses the main scene, including a minimized window, before routing content.
enum MacMainWindow {
  static func open(_ openWindow: () -> Void) {
    openWindow()
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
      if window.isMiniaturized { window.deminiaturize(nil) }
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
}

/// Shared by the app and Catalog so menu and shortcut routing stay identical.
struct MacSettingsCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("menu_settings") { MacSettingsNavigation.open { openWindow(id: "main") } }
        .keyboardShortcut(",", modifiers: .command)
    }
  }
}

/// Opens Settings in the main window (constitution § Information architecture:
/// no separate settings window).
enum MacSettingsNavigation {
  static func open(_ openWindow: () -> Void) {
    UserDefaults.standard.set("settings", forKey: "macRequestedSettingsRoute")
    MacMainWindow.open(openWindow)
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowSettings"), object: nil)
  }
}

enum MacAboutNavigation {
  static func open(_ openWindow: () -> Void) {
    UserDefaults.standard.set("about", forKey: "macRequestedSettingsRoute")
    MacMainWindow.open(openWindow)
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowAbout"), object: nil)
  }
}

/// A projection of the hub's model facts, not another queue or connection check.
@MainActor struct MacMenuStatus {
  let status: BackupHubStatus
  let receiver: String
  let preparing: Bool
  let earlierPhotosStarted: Bool
  let autoBackup: Bool

  init(model: BackupModel) {
    receiver = model.peerDevice?.name ?? "Pixel"
    preparing = model.importing
    earlierPhotosStarted = model.earlierPhotosStarted
    autoBackup = model.autoBackup
    let hub = model.hubStatus
    if case .backingUp(let remaining, _) = hub {
      let jobs = model.jobs.filter {
        ($0.receiverID == nil || $0.receiverID == model.pairing?.receiverID)
          && ["queued", "running", "waiting", "paused"].contains($0.state)
      }
      // The job list can be paged and preparations have no size yet. Only show
      // a batch size when every remaining photo has a recorded resource size.
      let complete = jobs.count == remaining && jobs.allSatisfy {
        !$0.asset.resources.isEmpty && $0.asset.resources.allSatisfy { $0.size > 0 }
      }
      let bytes = complete ? jobs.reduce(UInt64(0)) {
        $0 + ($1.totalBytes > $1.confirmedBytes ? $1.totalBytes - $1.confirmedBytes : 0)
      } : 0
      status = .backingUp(remaining: remaining, bytes: bytes)
    } else {
      status = hub
    }
  }

  var isBackingUp: Bool {
    switch status {
    case .backingUp: return true
    case .empty, .caughtUp: return preparing
    default: return false
    }
  }

  var sentence: String {
    switch status {
    case .backingUp:
      return String(format: NSLocalizedString("menu_backup_destination", comment: ""),
        status.sentence(receiver: receiver, earlierPhotosStarted: earlierPhotosStarted, autoBackup: autoBackup), receiver)
    case .problem(.receiverRejected):
      return NSLocalizedString("menu_problem_receiver_rejected", comment: "")
    case .empty, .caughtUp:
      // Original preparation is work, not proof that all photos are saved.
      if preparing { return NSLocalizedString("importing_originals", comment: "") }
      return status.sentence(receiver: receiver, earlierPhotosStarted: earlierPhotosStarted, autoBackup: autoBackup)
    default:
      return status.sentence(receiver: receiver, earlierPhotosStarted: earlierPhotosStarted, autoBackup: autoBackup)
    }
  }
}

/// Standard menu items shared with the catalog; AppKit owns all menu styling.
struct MacStatusMenuItems: View {
  let status: MacMenuStatus
  let paused: Bool
  let pauseEnabled: Bool
  var togglePause: () -> Void
  var openMain: () -> Void
  var openSettings: () -> Void
  var quit: () -> Void

  var body: some View {
    Button(action: {}) { Text(verbatim: status.sentence) }.disabled(true)
    Divider()
    Button(LocalizedStringKey(paused ? "hub_resume" : "menu_pause_backup"), action: togglePause)
      .disabled(!pauseEnabled)
    Button("menu_open", action: openMain)
    Button("menu_settings", action: openSettings).keyboardShortcut(",", modifiers: .command)
    Divider()
    Button("menu_quit", action: quit).keyboardShortcut("q", modifiers: .command)
  }
}

struct MacStatusMenu: View {
  @ObservedObject var model: BackupModel
  @Environment(\.openWindow) private var openWindow
  @State private var changingPause = false

  var body: some View {
    MacStatusMenuItems(status: MacMenuStatus(model: model), paused: model.paused,
      pauseEnabled: model.ready && model.pairing != nil && !changingPause && !model.changingPause,
      togglePause: {
        guard !changingPause, !model.changingPause else { return }
        let paused = !model.paused
        changingPause = true
        Task {
          await model.setPaused(paused)
          changingPause = false
        }
      }, openMain: {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
      }, openSettings: {
        MacSettingsNavigation.open { openWindow(id: "main") }
      }, quit: { NSApp.terminate(nil) })
  }
}

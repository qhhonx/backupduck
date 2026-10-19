import AppKit
import SwiftUI

enum MacMenuBarIcon {
  static let image: NSImage = {
    guard let url = Bundle.main.url(forResource: "DuckMenuBar", withExtension: "pdf"),
      let image = NSImage(contentsOf: url) else { return NSImage() }
    image.size = NSSize(width: 20, height: 20)
    image.isTemplate = true
    return image
  }()
}

/// Opens Settings in the main window (constitution § Information architecture:
/// no separate settings window).
enum MacSettingsNavigation {
  static func open(_ openWindow: () -> Void) {
    UserDefaults.standard.set("settings", forKey: "macRequestedSettingsRoute")
    openWindow()
    NSApp.activate(ignoringOtherApps: true)
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowSettings"), object: nil)
  }
}

enum MacAboutNavigation {
  static func open(_ openWindow: () -> Void) {
    UserDefaults.standard.set("about", forKey: "macRequestedSettingsRoute")
    openWindow()
    NSApp.activate(ignoringOtherApps: true)
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowAbout"), object: nil)
  }
}

/// A compact snapshot of the same persistent queue used by the main window.
/// Never start another worker when the menu opens.
@MainActor struct MacMenuStatus {
  let key: String
  let symbol: String

  init(model: BackupModel) {
    if !model.ready {
      key = model.message == nil ? "backup_initializing" : "state_failed"
      symbol = "photo.stack"
    } else if model.pairing == nil {
      key = "receiver_unpaired"
      symbol = "photo.stack"
    } else if model.paused {
      key = "backup_paused"
      symbol = "pause.circle"
    } else if let reason = model.waitingReason {
      key = "error_" + reason
      symbol = "clock"
    } else if model.importing {
      key = "importing_originals"
      symbol = "arrow.up.circle"
    } else if model.summary.running > 0 {
      key = "state_running"
      symbol = "arrow.up.circle"
    } else if model.summary.queued > 0 {
      key = "state_queued"
      symbol = "clock"
    } else if model.summary.waiting > 0 {
      key = "state_waiting"
      symbol = "clock"
    } else if model.summary.failed + model.summary.publication_failed > 0 {
      key = model.summary.publication_failed > 0 ? "state_publication_failed" : "state_failed"
      symbol = "exclamationmark.circle"
    } else {
      key = "menu_backup_ready"
      symbol = "photo.stack"
    }
  }
}

struct MacStatusMenu: View {
  @ObservedObject var model: BackupModel
  @Environment(\.openWindow) private var openWindow
  @State private var changingPause = false

  var body: some View {
    if DesignPreview.proposedDesign { redesigned } else { current }
  }

  /// The hub's line, the Pixel, and the actions people reach for from the menu
  /// bar (interaction.md I1, I3). Settings open in the main window.
  @ViewBuilder private var redesigned: some View {
    Text(model.hubStatus.sentence(receiver: model.peerDevice?.name ?? "Pixel"))
    if let peer = model.peerDevice, model.pairing != nil {
      Text(String(format: NSLocalizedString("device_sending_to", comment: ""), peer.name))
    }
    Divider()
    Button("menu_open") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }.keyboardShortcut("o", modifiers: .command)
    Button(LocalizedStringKey(model.paused ? "hub_resume" : "hub_pause")) {
      guard !changingPause else { return }
      changingPause = true
      Task {
        await model.setPaused(!model.paused)
        changingPause = false
      }
    }.disabled(!model.ready || model.pairing == nil || changingPause || model.changingPause)
    Divider()
    Button("menu_settings") { MacSettingsNavigation.open { openWindow(id: "main") } }
    Button("about_title") { MacAboutNavigation.open { openWindow(id: "main") } }
    Divider()
    Button("menu_quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
  }

  @ViewBuilder private var current: some View {
    Text(LocalizedStringKey(MacMenuStatus(model: model).key))
    if let peer = model.peerDevice, model.pairing != nil {
      Text(String(format: NSLocalizedString("device_sending_to", comment: ""), peer.name))
    }
    if model.ready, model.pairing != nil {
      Text(String(format: NSLocalizedString("transfer_summary", comment: ""),
        model.summary.received, model.summary.total))
    }
    Divider()
    Button("menu_open") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }.keyboardShortcut("o", modifiers: .command)
    Button(LocalizedStringKey(model.paused ? "resume_backup" : "pause_backup")) {
      guard !changingPause else { return }
      changingPause = true
      Task {
        await model.setPaused(!model.paused)
        changingPause = false
      }
    }.disabled(!model.ready || model.pairing == nil || changingPause || model.changingPause)
    if let error = model.pauseError { Text(error) }
    Divider()
    SettingsLink { Text("nav_settings") }
    Button("about_title") { MacAboutNavigation.open { openWindow(id: "main") } }
    Divider()
    Button("menu_quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
  }
}

import AppKit
import CoreImage.CIFilterBuiltins
import Darwin
import Photos
import SwiftUI

@main struct BackupDuckMacApp: App {
  @Environment(\.openWindow) private var openWindow
  @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
  @StateObject private var model = BackupModel.shared
  @StateObject private var library = PhotoLibraryModel()
  @AppStorage("duckAppearance") private var appearance = "system"
  private var colorScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
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

enum MacDestination: String, CaseIterable, Identifiable {
  case library, sources, backup, transfers, receiver, settings
  var id: String { rawValue }
  var title: String { ["library", "sources", "backup"].contains(rawValue) ? "mac_nav_" + rawValue : "nav_" + rawValue }
  var icon: String {
    switch self {
    case .library: "photo.on.rectangle"
    case .sources: "folder"
    case .backup: "checkmark.shield"
    case .transfers: "arrow.up.arrow.down"
    case .receiver: "externaldrive.badge.wifi"
    case .settings: "gearshape"
    }
  }
}
struct MacWorkspace: View {
  @ObservedObject var model: BackupModel
  @ObservedObject var library: PhotoLibraryModel
  @State private var destination: MacDestination? = .backup
  private var initialSettingsRoute: MacSettingsRoute?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var tileSize: Double = 140
  @State private var pairSheet = false
  @State private var selectedPhotoDetails: PHAsset?
  @State private var confirmSelectedBackup = false
  @State private var rebackupReceivedSelection = false
  @State private var transferFilter = "all"
  @State private var settingsTitle = "nav_settings"
  @State private var librarySelecting = false
  @State private var previewAsset: PHAsset?
  @StateObject private var activeTransfers = TaskBrowserModel()
  @StateObject private var folders: FolderSources
  init(model: BackupModel, library: PhotoLibraryModel, initialDestination: MacDestination = .backup, folderSources: FolderSources? = nil, initialSettingsRoute: MacSettingsRoute? = nil, initialTransferFilter: String = "all") {
    self.model = model
    self.library = library
    self.initialSettingsRoute = initialSettingsRoute
    _destination = State(initialValue: initialDestination)
    _transferFilter = State(initialValue: initialTransferFilter)
    _folders = StateObject(wrappedValue: folderSources ?? .shared)
  }
  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) { DuckBrandMark(size: 38); Text("brand_name").font(.system(size: 18, weight: .semibold)) }.padding(
          .horizontal, 20
        ).padding(.vertical, 28)
        List(selection: $destination) {
          Section("mac_sidebar_library") {
            ForEach([MacDestination.library, .sources]) { item in
              sidebarRow(item)
            }
          }
          Section("sidebar_tasks") {
            ForEach([MacDestination.backup, .transfers]) { item in
              sidebarRow(item)
            }
          }
          Section("sidebar_manage") {
            ForEach([MacDestination.receiver, .settings]) { item in
              sidebarRow(item)
            }
          }
        }.listStyle(.sidebar).font(.body.weight(.medium))
        VStack(alignment: .leading, spacing: 8) {
          ReceiverStatusIndicator(model: model)
          Text(model.peerDevice?.name ?? NSLocalizedString(model.pairing == nil ? "receiver_unpaired" : "receiver_paired", comment: "")).font(.caption)
            .foregroundStyle(.secondary)
        }.font(.callout).padding(20)
      }.navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 300)
    } detail: {
      VStack(spacing: 0) {
        // Keep the native collection alive when switching destinations. No loss
        // of its reuse pool, selection or scroll position on tab changes.
        ZStack(alignment: .topLeading) {
          libraryPage.opacity(destination == .library ? 1 : 0).allowsHitTesting(
            destination == .library
          ).accessibilityHidden(destination != .library)
          if destination == .sources {
            FolderSourcesPage(folders: folders, backup: model)
          }
          if destination == .backup {
            MacBackupPage(model: model, folders: folders, pair: { pairSheet = true },
              library: { destination = .library }, sources: { destination = .sources }, receiver: { destination = .receiver }, showTransfers: showTransfers)
          }
          if destination == .transfers {
            MacTransferPage(model: model, filter: transferFilter, sourceOptions: [("library", NSLocalizedString("source_system_library", comment: ""))] + folders.sources.map { ($0.id, folders.displayName($0)) }).id(transferFilter).padding(28)
          }
          if destination == .settings {
            MacPreferences(model: model, folders: folders, showFolders: { destination = .sources }, titleChanged: { settingsTitle = $0 }, initialRoute: initialSettingsRoute)
          }
          if destination == .receiver {
            ScrollView { ReceiverPage(model: model, pair: { pairSheet = true }).padding(28) }
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        if destination != .settings && destination != .receiver {
          Divider()
          footer.padding(.horizontal, 24).padding(.vertical, 12).background(DuckColors.surface)
            .task(id: "\(model.queueRevision)|\(model.pairing?.receiverID ?? "")") {
              if model.ready, let receiver = model.pairing?.receiverID {
                await activeTransfers.refresh(filter: "running", receiver: receiver)
              }
            }
        }
      }
      .navigationTitle(LocalizedStringKey(destination == .settings ? settingsTitle : (destination ?? .library).title))
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          if destination == .transfers {
            Button {
              Task { await model.setPaused(!model.paused) }
            } label: {
              Label(LocalizedStringKey(
                model.paused ? "resume_backup" : "pause_backup"),
                systemImage: model.paused ? "play.fill" : "pause.fill")
            }.disabled(!model.ready || model.pairing == nil || model.changingPause)
          }
        }
      }
    }
    .tint(DuckColors.action)
    .background(DuckColors.canvas)
    .background(MacSheetInitialFocus())
    .navigationSplitViewStyle(.balanced)
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowTransfers"))) { _ in showTransfers("all") }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowFolders"))) { _ in
      UserDefaults.standard.removeObject(forKey: "macRequestedDestination")
      folders.selectedSourceID = nil; destination = .sources; columnVisibility = .all
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowAbout"))) { _ in
      destination = .settings; settingsTitle = "about_title"
    }
    .onAppear {
      if UserDefaults.standard.string(forKey: "macRequestedSettingsRoute") == "about" { destination = .settings }
      if UserDefaults.standard.string(forKey: "macRequestedDestination") == "sources" {
        UserDefaults.standard.removeObject(forKey: "macRequestedDestination")
        destination = .sources
      }
    }
    .onChange(of: folders.selectedSourceID) { _, _ in columnVisibility = .all }
    .task { await model.open(); await folders.open() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in folders.wake() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in folders.wake() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in folders.wake() }
    .sheet(isPresented: $pairSheet) { MacPairingSheet(model: model) }
    .sheet(isPresented: $confirmSelectedBackup) { selectedBackupConfirmation }
    .sheet(isPresented: Binding(get: { previewAsset != nil }, set: { if !$0 { previewAsset = nil } })) {
      if let previewAsset { MacPhotoPreview(asset: previewAsset) }
    }
    .sheet(isPresented: Binding(get: { selectedPhotoDetails != nil }, set: { if !$0 { selectedPhotoDetails = nil } })) {
      if let selectedPhotoDetails { DuckPhotoDetail(asset: selectedPhotoDetails) }
    }
  }
  private func sidebarRow(_ item: MacDestination) -> some View {
    let selected = destination == item
    return HStack(spacing: 12) {
      Image(systemName: item.icon).font(.system(size: 16)).frame(width: 20).foregroundStyle(selected ? DuckColors.action : DuckColors.text)
      Text(LocalizedStringKey(item.title)).font(.system(size: 14, weight: selected ? .semibold : .regular))
    }.frame(minHeight: 36).tag(item)
  }
  private func showTransfers(_ filter: String) {
    transferFilter = filter
    destination = .transfers
  }
  private var libraryPage: some View {
    VStack(alignment: .leading, spacing: 0) {
      if library.authorized {
      MacLibraryToolbar(total: library.total, selected: library.selection.count,
        selecting: $librarySelecting, filter: Binding(get: { library.filter }, set: { value in Task { await library.changeFilter(value) } }),
        tileSize: $tileSize, canBackup: !library.selection.isEmpty && !model.importing && model.pairing != nil,
        finish: { library.selection.removeAll() }, backup: { rebackupReceivedSelection = false; confirmSelectedBackup = true })
        .padding(.horizontal, 28).padding(.vertical, 12)

      }
      if let placeholder = library.placeholder {
        MacLibraryPlaceholder(kind: placeholder,
          requestingAccess: library.requestingPermission,
          requestAccess: { Task { await library.open(requestPermission: true) } },
          clearFilter: { Task { await library.changeFilter(.all) } })
      } else {
        MacLibraryGrid(
          library: library, preparationRevision: "\(model.pendingImports)|\(model.importingSourceID ?? "")", queueRevision: model.queueRevision,
          receiverID: model.pairing?.receiverID, itemSize: tileSize, selecting: librarySelecting,
          preview: { previewAsset = $0 }, enterSelection: { librarySelecting = true })
      }
    }
  }
  private var selectedBackupConfirmation: some View {
    DuckSelectedBackup(count: library.selection.count, rebackup: $rebackupReceivedSelection,
      failureMessage: { model.message }) {
      await backupSelection(rebackupReceived: rebackupReceivedSelection)
    }
  }

  private func backupSelection(rebackupReceived: Bool) async -> Bool {
    let tokens = library.selection
    let ids = await library.selectedAssetIdentifiers(tokens)
    guard !ids.isEmpty else { return false }
    let accepted = await model.backupSelectedAssets(ids, rebackupReceived: rebackupReceived)
    // Clear selection only after shared durable submission succeeds. Original
    // preparation and its recoverable failures belong to persistent task views.
    if accepted { library.selection.subtract(tokens) }
    return accepted
  }

  private var footer: some View {
    MacBackupFooter(model: model, activeJob: activeTransfers.jobs.first,
      pair: { pairSheet = true }, showTransfers: { showTransfers("all") })
  }
}

struct MacBackupFooter: View {
  @ObservedObject var model: BackupModel
  var activeJob: BackupJob?
  var pair: () -> Void
  var showTransfers: () -> Void
  private var progress: Double? {
    if model.importing { return model.exportProgress }
    guard !model.paused, let job = activeJob, job.state == "running", job.totalBytes > 0 else { return nil }
    return model.transferProgress[job.id]?.activeFraction(confirmed: job.confirmedBytes, total: job.totalBytes)
  }
  private var summary: String {
    if let message = model.message { return message }
    if model.summary.failed + model.summary.publication_failed > 0 {
      return String(format: NSLocalizedString("backup_status_failed_count", comment: ""), model.summary.failed + model.summary.publication_failed)
    }
    return String(format: NSLocalizedString("design_saved_count", comment: ""), model.summary.published, model.summary.total)
  }
  private var title: String {
    if model.pairing == nil { return "receiver_unpaired" }
    if model.paused { return "backup_paused" }
    if model.importing { return "importing_originals" }
    if model.summary.failed + model.summary.publication_failed > 0 { return "state_attention" }
    if model.waitingForNetwork || model.receiverUnavailable { return "waiting_for_wifi" }
    if model.compactWaitingReason != nil { return "backup_waiting" }
    if model.summary.running + model.summary.queued > 0 { return "state_active" }
    if model.summary.received > model.summary.published { return "state_publication_pending" }
    if model.summary.published > 0 { return "state_published" }
    return "backup_status_ready"
  }
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: model.summary.failed + model.summary.publication_failed > 0 ? "exclamationmark.triangle" : model.summary.published > 0 ? "checkmark.shield" : "arrow.up.arrow.down")
        .font(.system(size: 20)).foregroundStyle(model.summary.failed + model.summary.publication_failed > 0 ? DuckColors.failure : DuckColors.action)
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 10) {
          Text(model.summary.publication_failed > 0 ? LocalizedStringKey(String(format: NSLocalizedString("mac_backup_album_failed_count", comment: ""), model.summary.publication_failed)) : LocalizedStringKey(title))
            .font(.system(size: 14, weight: .semibold)).lineLimit(1).layoutPriority(1)
          Spacer(minLength: 0)
        }
        Group {
          if let reason = model.compactWaitingReason {
            Label(LocalizedStringKey("error_" + reason), systemImage: "clock")
              .foregroundStyle(.orange).help(NSLocalizedString("error_" + reason, comment: ""))
          } else {
            Text(summary).foregroundStyle(.secondary).help(summary)
          }
        }.font(.system(size: 12)).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
      if model.pairing == nil { Button("pair_receiver_desktop", action: pair) }
      else { Button("nav_transfers", action: showTransfers).buttonStyle(.link) }
    }.frame(minHeight: 44).overlay(alignment: .bottom) {
      if let progress {
        GeometryReader { geometry in
          Rectangle().fill(DuckColors.action).frame(width: geometry.size.width * progress)
        }.frame(height: 2).accessibilityHidden(true)
      }
    }.accessibilityIdentifier("backup.footer")
  }
}

struct ReceiverPage: View {
  @ObservedObject var model: BackupModel
  let pair: () -> Void
  @State private var help = false
  private var status: (key: String, symbol: String, color: Color) { ReceiverStatusIndicator(model: model).status }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text(model.pairing == nil ? NSLocalizedString("receiver_heading", comment: "") : model.peerDevice?.name ?? NSLocalizedString("receiver_paired", comment: ""))
          .font(.system(size: 26, weight: .semibold))
        Text(LocalizedStringKey(model.pairing == nil ? "mac_receiver_connection_note" : "mac_receiver_paired_subtitle"))
          .font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
      }
      if model.pairing == nil {
        DuckPairingSteps(desktop: true)
        Button("pair_receiver_desktop", action: pair).duckPrimaryAction()
        DuckNotice(title: "help_start_title", message: "mac_receiver_connection_note", symbol: "wifi")
      } else {
        HStack(alignment: .top, spacing: 20) {
          DuckSurface {
            VStack(alignment: .leading, spacing: 12) {
              Text("mac_receiver_connection_title").font(.system(size: 16, weight: .semibold))
              DuckNotice(title: LocalizedStringKey(status.key), message: "mac_fidelity_connection_record_note", symbol: status.symbol)
              ReceiverStatusIndicator(model: model, actionTitle: "mac_receiver_view_status")
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.frame(maxWidth: .infinity)
          DuckSurface {
            VStack(alignment: .leading, spacing: 12) {
              Text("mac_receiver_other_device").font(.system(size: 16, weight: .semibold))
              Text("mac_receiver_history_retained").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
              Button("mac_fidelity_show_mac_code", action: pair).duckPrimaryAction()
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.frame(width: 240)
        }
        VStack(spacing: 0) {
          receiverFact("receiver_address", value: model.pairing?.endpoint ?? "—")
          receiverFact("mac_receiver_temperature", value: model.receiverReadings?.temperature_deci_celsius.map { String(format: "%.1f °C", Double($0) / 10) } ?? NSLocalizedString("mac_receiver_not_provided", comment: ""))
          receiverFact("mac_receiver_space", value: model.receiverReadings?.free_bytes.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) } ?? NSLocalizedString("mac_receiver_not_provided", comment: ""))
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .task(id: model.pairing?.receiverID.description.appending(model.pairing?.endpoint ?? "")) {
        model.receiverReadings = nil
        while !Task.isCancelled, model.pairing != nil {
          await model.refreshReceiverReadings()
          try? await Task.sleep(for: .seconds(20))
        }
      }
  }
  private func receiverFact(_ title: LocalizedStringKey, value: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(title).font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary).frame(width: 130, alignment: .leading)
      Text(value).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() }
  }
}
struct MacPairingSheet: View {
  @ObservedObject var model: BackupModel
  @Environment(\.dismiss) private var dismiss
  @StateObject private var exchange = DesktopPairingModel()
  var body: some View {
    MacPairingPresentation(model: model, image: exchange.image, error: exchange.error,
      cancel: { exchange.stop(); dismiss() },
      regenerate: { exchange.begin(model: model, finished: { dismiss() }) })
      .onAppear { exchange.begin(model: model, finished: { dismiss() }) }
      .onDisappear { exchange.stop() }
  }
}
/// Presentation is separable from the real pairing session for isolated UI
/// checks; the production owner above always starts the authenticated flow.
struct MacPairingPresentation: View {
  @ObservedObject var model: BackupModel
  var image: NSImage?
  var error: String?
  var cancel: () -> Void
  var regenerate: () -> Void
  var body: some View {
    DuckSheetLayout(title: "pair_receiver_desktop", busy: model.pairingInProgress, desktopMinHeight: 560, desktopIdealHeight: 600) {
      if let profile = model.deviceSnapshot?.device { Text(profile.name).font(.headline) }
      Text("mac_pair_scan_instruction").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
      if model.pairingInProgress { ProgressView("apple_pair_verifying").controlSize(.small) }
      if let image = image {
        VStack(spacing: 16) {
          Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
            .frame(width: 240, height: 240).padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(Text("desktop_pair_qr"))
          Text("desktop_pair_expiry").font(.caption).foregroundStyle(DuckColors.textSecondary)
        }.frame(maxWidth: .infinity)
      } else if let error = error {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "wifi.exclamationmark")
      } else if !model.pairingInProgress {
        ProgressView("mac_pair_creating").frame(maxWidth: .infinity).padding(.vertical, 48)
      }
    } actions: {
      Button("cancel", action: cancel)
        .duckSecondaryAction().keyboardShortcut(.cancelAction).disabled(model.pairingInProgress)
      if error != nil {
        Button("desktop_pair_regenerate", action: regenerate)
          .duckPrimaryAction().disabled(model.pairingInProgress)
      }
    }
  }
}
@MainActor final class DesktopPairingModel: ObservableObject {
  @Published var image: NSImage?
  @Published var error: String?
  private var worker: Task<Void, Never>?
  func begin(model: BackupModel, finished: @escaping () -> Void) {
    worker?.cancel()
    image = nil
    error = nil
    worker = Task {
      var sessionID: String?
      defer {
        if let sessionID {
          Task {
            _ = try? await Bridge.call(["op": "stop_desktop_pairing", "session_id": sessionID])
          }
        }
      }
      do {
        guard let ip = Self.localIPv4() else {
          error = "desktop_pair_no_network"
          return
        }
        let data = try await Bridge.call(["op": "start_desktop_pairing", "ip": ip])
        let invite = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        sessionID = (invite?["connection"] as? [String: Any])?["receiver_id"] as? String
        guard !Task.isCancelled else { return }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
          let cg = CIContext().createCGImage(output, from: output.extent)
        else {
          error = "desktop_pair_failed"
          return
        }
        image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        while !Task.isCancelled {
          try await Task.sleep(nanoseconds: 800_000_000)
          let status = try await Bridge.call(["op": "desktop_pairing_status"])
          guard let envelope = try JSONSerialization.jsonObject(with: status) as? [String: Any] else {
            throw Bridge.Failure(code: "invalid")
          }
          if let pairing = envelope["pairing"] as? [String: Any] {
            image = nil
            let encoded = try JSONSerialization.data(withJSONObject: pairing)
            let identity = pairing["receiver_id"] as? String
            let accepted = await model.pair(String(decoding: encoded, as: UTF8.self))
            guard !Task.isCancelled else { return }
            if accepted && Self.acceptedPairing(model, receiverID: identity, endpoint: pairing["endpoint"] as? String) {
              finished()
            } else {
              error = "desktop_pair_failed"
            }
            return
          }
          if envelope["expired"] as? Bool == true {
            image = nil
            error = "desktop_pair_expired"
            return
          }
        }
      } catch {
        if !Task.isCancelled {
          image = nil
          self.error = "desktop_pair_failed"
        }
      }
    }
  }
  static func acceptedPairing(_ model: BackupModel, receiverID: String?, endpoint: String?) -> Bool {
    guard !model.pairingInProgress, model.pairingError == nil,
      let receiverID, let endpoint else { return false }
    return model.pairing?.receiverID == receiverID && model.pairing?.endpoint == endpoint
  }
  func stop() {
    worker?.cancel()
    worker = nil
    image = nil
  }
  private static func localIPv4() -> String? {
    var pointer: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
    defer { freeifaddrs(pointer) }
    var candidates: [(String, String)] = []
    var next: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = next {
      defer { next = entry.pointee.ifa_next }
      guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
        (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
        (entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0
      else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(
        address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
        NI_NUMERICHOST) == 0
      {
        let name = String(cString: entry.pointee.ifa_name)
        if name.hasPrefix("en") { candidates.append((name, String(cString: host))) }
      }
    }
    return candidates.sorted { $0.0 < $1.0 }.first?.1
  }
}

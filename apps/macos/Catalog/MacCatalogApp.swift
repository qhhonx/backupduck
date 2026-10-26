import AppKit
import ScreenCaptureKit
import SwiftUI
import Photos
import AVFoundation
import UserNotifications

/// Mac design catalog: the production workspace window driven by scenario data
/// instead of the Rust core, the keychain and the network. It never ships; see
/// `apps/apple/Catalog/README.md`.
@main struct MacCatalogApp: App {
  @NSApplicationDelegateAdaptor(MacCatalogLifecycle.self) private var lifecycle
  static let core = ScenarioCore()
  static let credentials = ScenarioCredentials()

  init() {
    BackupEnvironment.core = Self.core
    BackupEnvironment.credentials = Self.credentials
    BackupEnvironment.discoversReceivers = false
    BackupEnvironment.usesNetwork = false
    BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.sampleThumbnail = SampleImages.image(for:)
    BackupEnvironment.sampleAsset = { InformationSampleAsset(job: $0) }
  }

  var body: some Scene {
    Window("Design catalog", id: "main") {
      MacCatalogRoot().frame(minWidth: min(900, max(640, Double(MacCatalogLaunch.value("-window-width") ?? "") ?? 900)), minHeight: 620)
    }.defaultSize(width: 1180, height: 800).commands {
      MacFolderCommands()
      MacSettingsCommands()
      CommandGroup(replacing: .appInfo) {
        Button("about_title") { MacAboutNavigation.open {} }
      }
    }
    MenuBarExtra(isInserted: .constant(ProcessInfo.processInfo.arguments.contains("-status-menu-bar"))) {
      MacCatalogStatusMenuItems(model: BackupEnvironment.activeModel())
    } label: {
      Image(nsImage: MacMenuBarIcon.image)
    }
  }
}

/// What one scenario run owns. Created once per run, so restarting replays the
/// scenario with a new model.
@MainActor private final class MacScenarioSession: ObservableObject {
  let model: BackupModel
  let library = PhotoLibraryModel()
  let folders: FolderSources
  let notifier: BackupNotifier
  let scope: ScopeCatalogFixture?
  init(_ scenario: Scenario) {
    let authorization: UNAuthorizationStatus = scenario.notificationAuthorization == "denied" ? .denied
      : scenario.notificationAuthorization == "authorized" ? .authorized : .notDetermined
    notifier = BackupNotifier(catalogAuthorization: authorization)
    let notifications = notifier
    BackupEnvironment.activeNotifier = { notifications }
    if MacCatalogLaunch.value("-route-timing") != "warm" { notifier.route = Self.route(scenario) }
    scope = scenario.id.hasPrefix("settings.scope.") ? ScopeCatalogFixture(id: scenario.id) : nil
    model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    if scenario.id == "library.synthetic" {
      let assets: [PHAsset] = (0..<90).map { index in
        let job = BackupJob(id: Int64(9000 + index),
          asset: .init(metadata: ["created_at_ms": String(1792495800000 - Int64(index) * 3_600_000)],
            kind: "photo", source_id: "catalog-library-\(index)", revision: "1",
            resources: [.init(filename: "IMG_\(9000 + index).JPG", size: 4800000)]),
          state: "waiting", confirmedBytes: 0, errorCode: nil)
        return InformationSampleAsset(job: job)
      }
      library.installSyntheticAssets(CatalogAssetCollection(assets))
    }
    if scenario.id == "records.running-grid" { MacHistoryMotionFixture.install(core: MacCatalogApp.core, tick: 0) }
    let made = model
    BackupEnvironment.activeModel = { made }
    folders = FolderSources(backup: model)
    // Catalog folders never open configuration files, bookmarks, watchers or native indexes.
    folders.previewRows = []
    FolderSources.catalog = folders
    if scenario.id.hasPrefix("folders.") || scenario.id.hasPrefix("settings.folder") || scenario.id.hasSuffix("folder-media") {
      FolderCatalog.install(scenario.id, folders: folders, sheet: MacCatalogLaunch.value("-sheet"))
    }
    if scenario.id == "records.running-grid" {
      Task { @MainActor [weak model] in
        try? await Task.sleep(for: .seconds(5))
        for tick in 1...60 {
          guard !Task.isCancelled, let model else { return }
          MacHistoryMotionFixture.install(core: MacCatalogApp.core, tick: tick)
          await model.refresh()
          try? await Task.sleep(for: .seconds(1))
        }
      }
    }
  }
  static func route(_ scenario: Scenario) -> BackupNotifier.Route? {
    let receiver = MacCatalogLaunch.value("-route-receiver") ?? "catalog-pixel"
    switch scenario.step {
    case "notificationNeedsYou": return .init(notice: .convert, receiver: receiver)
    case "notificationPhoto": return .init(notice: .earlier, receiver: receiver, source: "a8-synthetic-photo")
    case "notificationOverview": return .init(notice: .full, receiver: receiver)
    default: return nil
    }
  }
}

/// Command-line startup belongs to the app lifecycle, not a SwiftUI view task:
/// background launches can defer that task until the window is activated.
private enum MacCatalogLaunch {
  static func value(_ flag: String) -> String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
  }
}

@MainActor private final class MacCatalogLifecycle: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Direct CLI launches must participate in normal foreground activation.
    NSApp.setActivationPolicy(.regular)
    Task { @MainActor in
      for _ in 0..<40 {
        Self.sizeWindow()
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
    if MacCatalogLaunch.value("-snapshot-mode") != "manual" { Self.capture() }
    if #available(macOS 15.0, *), let path = MacCatalogLaunch.value("-record") {
      Task { @MainActor in
        do {
          for _ in 0..<20 {
            if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { break }
            try await Task.sleep(for: .milliseconds(100))
          }
          if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            let configuration = NSWorkspace.OpenConfiguration(); configuration.createsNewApplicationInstance = false
            _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
          }
          try await Task.sleep(for: .seconds(3))
          try await MacCatalogRecording.record(path: path,
            seconds: Double(MacCatalogLaunch.value("-record-seconds") ?? "") ?? 68)
          if ProcessInfo.processInfo.arguments.contains("-record-exit") { NSApp.terminate(nil) }
        } catch { fputs("Catalog recording failed: \(error)\n", stderr) }
      }
    }
  }
  @discardableResult private static func sizeWindow() -> Bool {
    guard let width = MacCatalogLaunch.value("-window-width").flatMap(Double.init),
      let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return false }
    let size = NSSize(width: max(640, width), height: 740)
    if window.contentView?.frame.size != size { window.setContentSize(size) }
    return true
  }
  static func capture() {
    guard let path = MacCatalogLaunch.value("-snapshot") else { return }
    Task { @MainActor in
      do {
        // Let the open-app event create this instance's window before trying
        // to reopen it. Multiple catalogs can share an identity in local builds.
        for _ in 0..<20 {
          if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
          let configuration = NSWorkspace.OpenConfiguration()
          configuration.createsNewApplicationInstance = false
          _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        }
        Self.sizeWindow()
        let delay = max(0, Double(MacCatalogLaunch.value("-snapshot-delay") ?? "") ?? 9)
        try await Task.sleep(for: .seconds(delay))
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
          throw NSError(domain: "CatalogSnapshot", code: 1)
        }
        for _ in 0..<30 {
          NSApp.activate(ignoringOtherApps: true)
          window.makeMain()
          (window.attachedSheet ?? window).makeKeyAndOrderFront(nil)
          try await Task.sleep(for: .milliseconds(100))
          if NSApp.isActive && (window.attachedSheet ?? window).isKeyWindow { break }
        }
        guard NSApp.isActive, (window.attachedSheet ?? window).isKeyWindow else {
          throw NSError(domain: "CatalogSnapshotInactiveWindow", code: 2)
        }
        // Give the selected native collection/list keyboard focus so AppKit
        // renders its emphasized selection rather than the unfocused gray style.
        if window.attachedSheet == nil, let root = window.contentView {
          func selectionView(_ view: NSView) -> NSView? {
            if let collection = view as? NSCollectionView, !collection.selectionIndexPaths.isEmpty { return collection }
            return view.subviews.lazy.compactMap { selectionView($0) }.first
          }
          func selectedTable(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.selectedRow >= 0 { return table }
            return view.subviews.lazy.compactMap { selectedTable($0) }.first
          }
          if let focus = selectionView(root) ?? selectedTable(root) { window.makeFirstResponder(focus) }
        }
        try await Task.sleep(for: .milliseconds(350))
        try await MacWindowSnapshot.write(to: URL(fileURLWithPath: path))
        print("Catalog snapshot written: \(path)")
        NSApp.terminate(nil)
        // AppKit can decline termination while a token field is editing in a
        // sheet. Snapshot runs contain synthetic state and must always finish.
        exit(EXIT_SUCCESS)
      } catch {
        fputs("Catalog snapshot failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
      }
    }
  }
}

private struct MacCatalogRoot: View {
  @State private var scenarios: [Scenario] = []
  @State private var failure: String?
  @State private var open: Scenario?
  @State private var run: UUID?
  @State private var scheme: ColorScheme?

  init() {
    do {
      let loaded = try Scenario.loadAll()
      _scenarios = State(initialValue: loaded)
      if let id = MacCatalogLaunch.value("-scenario"), let scenario = loaded.first(where: { $0.id == id }) {
        _open = State(initialValue: scenario)
        _run = State(initialValue: UUID())
      }
    } catch {
      _failure = State(initialValue: error.localizedDescription)
    }
    if let appearance = MacCatalogLaunch.value("-appearance") {
      _scheme = State(initialValue: appearance == "dark" ? .dark : .light)
    }
  }

  var body: some View {
    Group {
      if let open, let run {
        MacScenarioRun(scenario: open)
          .id(run)
          .overlay(alignment: .bottomTrailing) {
            if MacCatalogLaunch.value("-snapshot") == nil {
              MacScenarioControls(scenario: open, scheme: $scheme, restart: restart, close: { self.open = nil })
                .padding(16)
            }
          }
      } else {
        list
      }
    }
    .preferredColorScheme(scheme)
  }

  private var list: some View {
    List {
      if let failure { Text(failure).foregroundStyle(.red) }
      ForEach(["settings", "backup", "library", "sources", "connect"], id: \.self) { page in
        let items = scenarios.filter { $0.page == page }
        if !items.isEmpty {
          Section(page.capitalized) {
            ForEach(items) { scenario in
              Button { start(scenario) } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(scenario.title)
                  Text(scenario.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
              }.buttonStyle(.plain)
            }
          }
        }
      }
    }
  }

  private func start(_ scenario: Scenario) {
    open = scenario; run = UUID()
  }

  private func restart() {
    run = nil
    DispatchQueue.main.async { run = UUID() }
  }
}

private struct MacScenarioRun: View {
  let scenario: Scenario
  @StateObject private var session: MacScenarioSession
  @State private var automaticChecks = true
  @State private var renaming = false

  init(scenario: Scenario) {
    self.scenario = scenario
    _session = StateObject(wrappedValue: MacScenarioSession(scenario))
  }

  private var settingsPage: MacSettings.Page? {
    switch scenario.step {
    case "devices": .devices
    case "autoBackup": .autoBackup
    case "advanced": .advanced
    case "appearance": .appearance
    case "language": .language
    case "about", "updates", "licenses", "thirdPartyLicenses": .about
    case "help", "help.offline", "help.faster", "help.live", "help.space": .help
    default: nil
    }
  }

  private var updateSection: MacUpdateSection? {
    guard scenario.step == "updates" else { return nil }
    return MacUpdateSection(automaticChecks: $automaticChecks,
      liveDetail: AnyView(MacCatalogUpdateDetail(unavailable: scenario.id.hasSuffix("unavailable"), automaticChecks: $automaticChecks)))
  }

  private func openSettingsDetail(_ navigator: DuckSettingsNavigator) {
    if let step = scenario.step, step.hasPrefix("help."),
      let topic = (HelpCenter.tasks + HelpCenter.problems).first(where: { "help." + $0.id == step }) {
      navigator.open(DuckSettingsPage(title: Text(topic.title), content: AnyView(HelpArticle(topic: topic))))
    } else if scenario.id == "settings.scope.browser", let scope = session.scope,
      let album = scope.albums.albums.first(where: { $0.name == "Family" }) {
      navigator.open(DuckSettingsPage(title: Text(verbatim: album.name),
        content: AnyView(MacScopeAlbumBrowser(album: album, store: scope.store))))
    } else if scenario.step == "thirdPartyLicenses" {
      navigator.open(DuckSettingsPage(title: Text("settings_third_party_licenses"), content: AnyView(DuckThirdPartyLicensesPage())))
    } else if scenario.step == "licenses" || MacCatalogLaunch.value("-start-route") == "licenses" {
      navigator.open(DuckSettingsPage(title: Text("settings_source_licenses"), content: AnyView(DuckLicensesPage())))
    } else if scenario.step == "updates" {
      navigator.open(DuckSettingsPage(title: Text("updates_title"),
        content: AnyView(MacCatalogUpdateDetail(unavailable: scenario.id.hasSuffix("unavailable"), automaticChecks: $automaticChecks))))
    }
    if let count = MacCatalogLaunch.value("-settings-back").flatMap(Int.init), count > 0 {
      Task { @MainActor in
        // Exercise the same action as toolbar Back after the start route mounts.
        try? await Task.sleep(for: .milliseconds(700))
        for _ in 0..<min(count, 3) {
          navigator.back()
          try? await Task.sleep(for: .milliseconds(200))
        }
      }
    }
  }

  var body: some View {
    Group {
      if scenario.step == "filterEmpty" {
        NavigationStack {
          LibraryPlaceholder(kind: .filterEmpty)
            .background(DuckRole.background).navigationTitle("nav_photos")
        }
      } else if scenario.step == "selectedBackup" {
        SelectionBackupCatalog(mode: scenario.id.components(separatedBy: ".").last ?? "direct")
      } else if scenario.step == "statusMenu" || MacCatalogLaunch.value("-status-menu") == "items" {
        MacStatusMenuCatalog(model: session.model)
      } else if scenario.step == "macViewer" {
        MacViewerCatalog(model: session.model, library: session.library, scenario: scenario.id)
      } else if scenario.step == "photoInformation" {
        MacInformationCatalog(model: session.model, library: session.library)
      } else if scenario.page == "connect" {
        // The connect sheet on its own, for review (design/mac-connect.md).
        MacConnectSheet(model: session.model).task { await session.model.open() }
      } else {
      MacWorkspace(model: session.model, library: session.library,
        // Records belong to the hub; the Mac lists them as their own sidebar position.
        initialDestination: session.folders.initialSheet == "rules" ? .settings : scenario.records != nil ? .transfers : MacDestination(rawValue: scenario.page) ?? .settings,
        folderSources: session.folders, initialTransferFilter: scenario.records ?? "all",
        initialSettingsPage: scenario.id.hasPrefix("diagnostics.") ? .diagnostics : settingsPage,
        scopeStore: session.scope?.store ?? .shared, albumsModel: session.scope?.albums ?? .shared,
        initialScopeDestination: session.scope?.destination, initialScopeSearch: session.scope?.search ?? "",
        initialViewerInfo: scenario.id == "folders.viewer-received", initialDiagnosticsPage: scenario.id.hasPrefix("diagnostics.") ? scenario.step : nil,
        openInitialSettingsDetail: openSettingsDetail, settingsUpdateSection: updateSection)
        .background {
          if scenario.id.hasPrefix("folders.viewer"), MacCatalogLaunch.value("-folder-viewer-state") != "browse" {
            FolderViewerCatalogOpening(source: scenario.id == "folders.viewer-received" ? "fixture-photo-0-4" : nil)
          }
        }
      }
    }
      .environment(\.duckReservedSettingsContent, scenario.reservedSettingsContent)
      .environment(\.duckFeedbackPreview, ["settings.feedback", "settings.feedback-reserved"].contains(scenario.id))
      .sheet(isPresented: $renaming) {
        DeviceNameEditor(model: session.model, name: session.model.deviceSnapshot?.device.name ?? "")
      }
      .task {
        if scenario.step == "rename" { await session.model.open(); renaming = true }
        if MacCatalogLaunch.value("-cache-action") == "clear" {
          await session.model.open()
          await session.model.reclaimCache()
        }
      }
      .onDisappear { session.model.stop() }
  }
}

/// Owns synthetic update state after opening through the production pane navigator.
private struct MacCatalogUpdateDetail: View {
  let unavailable: Bool
  @Binding var automaticChecks: Bool
  @State private var checking = false
  var body: some View {
    MacUpdateDetail(status: checking ? .checking : .notChecked, canCheck: !unavailable && !checking,
      automaticChecks: $automaticChecks, check: { checking = true })
      .task { if MacCatalogLaunch.value("-updates-check") == "yes" { checking = true } }
  }
}

/// Opens through the mounted production grid after its browsing toolbar exists.
/// This synthetic scenario never sends pointer or keyboard input.
private struct FolderViewerCatalogOpening: NSViewRepresentable {
  var source: String?
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    Task { @MainActor [weak view] in
      for _ in 0..<30 {
        try? await Task.sleep(for: .milliseconds(50))
        guard let root = view?.window?.contentView else { continue }
        @MainActor func grid(in view: NSView) -> MacMediaGrid.Coordinator? {
          if let collection = view as? NSCollectionView,
            let coordinator = collection.delegate as? MacMediaGrid.Coordinator,
            coordinator.parent.source is MacFolderGridSource, !coordinator.ids.isEmpty { return coordinator }
          return view.subviews.lazy.compactMap { grid(in: $0) }.first
        }
        if let coordinator = grid(in: root) {
          try? await Task.sleep(for: .milliseconds(500))
          guard let adapter = coordinator.parent.source as? MacFolderGridSource,
            let id = source.flatMap({ token in adapter.identifiers.first { adapter.photos[$0]?.source_id == token } }) ?? adapter.identifiers.first else { return }
          coordinator.parent.preview(id); return
        }
      }
    }
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}

/// Lists the production items and opens them in a real system menu. Navigation
/// and Quit are inert here; Pause uses only the scenario's synthetic core.
private struct MacStatusMenuCatalog: View {
  @ObservedObject var model: BackupModel

  private var items: some View {
    MacStatusMenuItems(status: MacMenuStatus(model: model), paused: model.paused,
      pauseEnabled: model.ready && model.pairing != nil && !model.changingPause,
      togglePause: { Task { await model.setPaused(!model.paused) } },
      openMain: {}, openSettings: {}, quit: {})
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.medium) {
      Menu {
        items
      } label: {
        Image(nsImage: MacMenuStatus(model: model).isBackingUp ? MacMenuBarIcon.activeImage : MacMenuBarIcon.image)
          .renderingMode(.template)
        Text("brand_name")
      }.fixedSize()
      Form { items }.formStyle(.grouped)
    }
    .padding(DuckSpacing.large)
    .task { await model.open() }
  }
}

/// An opt-in system menu-bar host for the production items. Commands that
/// navigate or quit remain inert; Pause addresses only the scripted core.
private struct MacCatalogStatusMenuItems: View {
  @ObservedObject var model: BackupModel
  var body: some View {
    MacStatusMenuItems(status: MacMenuStatus(model: model), paused: model.paused,
      pauseEnabled: model.ready && model.pairing != nil && !model.changingPause,
      togglePause: { Task { await model.setPaused(!model.paused) } },
      openMain: {}, openSettings: {}, quit: {})
  }
}

/// Synthetic assets use the production workspace, pager, facts and toolbar.
private struct MacViewerCatalog: View {
  @ObservedObject var model: BackupModel
  let library: PhotoLibraryModel
  let scenario: String
  @State private var request: MacViewerRequest?
  var body: some View {
    Group {
      if let request {
        MacWorkspace(model: model, library: library,
          initialDestination: MacCatalogLaunch.value("-viewer-entry") == "history" ? .transfers : .library,
          initialViewer: request,
          initialViewerInfo: scenario == "mac.viewer-inspector" || scenario == "mac.viewer-failed")
      } else { ProgressView().task { await open() } }
    }
  }
  private func open() async {
    await model.open()
    let sample = model.jobs.first ?? BackupJob(id: 801,
      asset: .init(metadata: ["created_at_ms": "1792495800000"], kind: "photo", source_id: "a8-synthetic-photo", revision: "1",
        resources: [.init(filename: "IMG_0801.HEIC", size: 4800000)]),
      state: "waiting", confirmedBytes: 0, errorCode: nil)
    let current = InformationSampleAsset(job: sample)
    let collection: [PHAsset] = (0..<13).map { $0 == 6 ? current : InformationSampleAsset(job: sample, identifier: "mac-viewer-\($0)") }
    request = MacCatalogLaunch.value("-viewer-entry") == "history" ? .photo(nil, [], HistoryPhoto(job: sample)) : .photo(current, collection, nil)
  }
}

/// Observe the model itself: changes to a session's stored model do not publish
/// through the session, and jobs arrive after opening its queue.
private struct MacInformationCatalog: View {
  @ObservedObject var model: BackupModel
  let library: PhotoLibraryModel
  @State private var opened = false

  var body: some View {
    ProgressView()
      .task { await model.open() }
      .onChange(of: model.jobs.first?.id, initial: true) { _, _ in
        guard !opened, let job = model.jobs.first else { return }
        opened = true
        if MacCatalogLaunch.value("-photo-info") == "fallback" {
          MacPhotoViewerWindow.openUnavailable(HistoryPhoto(job: job), model: model)
        } else {
          let asset = InformationSampleAsset(job: job)
          MacPhotoViewerWindow.open(asset: asset, library: library, collection: [asset])
        }
      }
  }
}

private struct MacScenarioControls: View {
  let scenario: Scenario
  @Binding var scheme: ColorScheme?
  let restart: () -> Void
  let close: () -> Void
  @State private var info = false

  var body: some View {
    HStack(spacing: 8) {
      Text(scenario.id).font(.caption.monospaced()).foregroundStyle(.secondary)
      if scenario.step?.hasPrefix("notification") == true {
        Button("Simulate notification") { BackupEnvironment.activeNotifier().route = MacScenarioSession.route(scenario) }
          .accessibilityIdentifier("catalog.notification")
      }
      Button("Scenario…") { info = true }
        .popover(isPresented: $info, arrowEdge: .top) {
          MacScenarioInfo(scenario: scenario, scheme: $scheme, restart: restart).frame(width: 420, height: 520)
        }
      Button("Restart", action: restart)
      Button("Scenarios", action: close)
      if MacCatalogLaunch.value("-snapshot-mode") == "manual" {
        Button("Snapshot") { MacCatalogLifecycle.capture() }
          .accessibilityIdentifier("catalog.snapshot")
      }
    }
    .controlSize(.small)
    .padding(8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct MacScenarioInfo: View {
  let scenario: Scenario
  @Binding var scheme: ColorScheme?
  let restart: () -> Void
  @State private var unscripted: [String] = []

  var body: some View {
    Form {
      Section {
        Text(scenario.title).font(.headline)
        Text(scenario.id).font(.caption.monospaced()).foregroundStyle(.secondary)
      }
      if !scenario.expect.isEmpty {
        Section("Expected") { ForEach(scenario.expect, id: \.self) { Text($0) } }
      }
      if !scenario.actions.isEmpty {
        Section("Actions") {
          ForEach(scenario.actions) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.action)
              Text(item.result).foregroundStyle(.secondary)
            }
          }
        }
      }
      Section("Unscripted core commands") {
        if unscripted.isEmpty { Text("None").foregroundStyle(.secondary) }
        ForEach(unscripted, id: \.self) { Text($0).font(.body.monospaced()).foregroundStyle(.red) }
      }
      Section("Review") {
        Picker("Appearance", selection: $scheme) {
          Text("System").tag(ColorScheme?.none)
          Text("Light").tag(ColorScheme?.some(.light))
          Text("Dark").tag(ColorScheme?.some(.dark))
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { unscripted = MacCatalogApp.core.unscripted }
  }
}

/// Captures the catalog's composited window, including title bar and materials.
/// macOS 14.0–14.3 uses the older view-cache fallback; its sidebar materials
/// are incomplete and must be judged in the live window.
enum MacWindowSnapshot {
  @MainActor static func write(to url: URL) async throws {
    let viewer = MacCatalogLaunch.value("-photo-info") == nil ? nil : NSApp.windows.first {
      $0.isVisible && $0.identifier == NSUserInterfaceItemIdentifier("photo.viewer")
    }
    if MacCatalogLaunch.value("-photo-info") != nil, viewer == nil {
      throw SnapshotError("The photo viewer is not visible.")
    }
    guard let candidate = viewer ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.contentView != nil }) else {
      throw SnapshotError("The catalog window is not visible (\(NSApp.windows.count) windows).")
    }
    let window = candidate.sheetParent ?? candidate
    guard NSApp.isActive, (window.attachedSheet ?? window).isKeyWindow else {
      throw SnapshotError("Refusing to capture an inactive catalog window.")
    }
    let activation: [String: Any] = ["active": NSApp.isActive, "key": (window.attachedSheet ?? window).isKeyWindow,
      "main": window.isMainWindow, "pid": ProcessInfo.processInfo.processIdentifier,
      "bundle": Bundle.main.bundleIdentifier ?? "", "windowNumber": window.windowNumber]
    try JSONSerialization.data(withJSONObject: activation, options: [.prettyPrinted, .sortedKeys])
      .write(to: url.deletingPathExtension().appendingPathExtension("activation.json"))
    let bitmap: NSBitmapImageRep
    if #available(macOS 14.4, *) {
      // Restrict capture to this process; no screen-recording consent is needed.
      let content = try await SCShareableContent.currentProcess
      guard let capturedWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
        throw SnapshotError("The catalog window is not available for capture.")
      }
      let filter = SCContentFilter(desktopIndependentWindow: capturedWindow)
      let configuration = SCStreamConfiguration()
      configuration.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
      configuration.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
      configuration.ignoreShadowsSingleWindow = true
      configuration.showsCursor = false
      let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
      bitmap = NSBitmapImageRep(cgImage: image)
    } else {
      fputs("Catalog snapshot: macOS before 14.4 cannot capture sidebar materials.\n", stderr)
      guard let view = window.contentView?.superview ?? window.contentView,
        let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw SnapshotError("The catalog window could not be rendered.")
      }
      view.cacheDisplay(in: view.bounds, to: cached)
      bitmap = cached
    }
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw SnapshotError("The catalog image could not be encoded as PNG.")
    }
    try png.write(to: url, options: .atomic)
    // The unscripted list goes next to the image for the same run.
    let notifier = BackupEnvironment.activeNotifier()
    let notificationEvidence: [String: Any] = ["authorization": notifier.authorization.rawValue,
      "enabled": notifier.enabled, "permissionRequests": notifier.permissionRequests,
      "settingsRequests": notifier.settingsRequests, "usesSystem": notifier.usesSystem,
      "routePending": notifier.route != nil, "settingsURL": notifier.settingsURL?.absoluteString ?? ""]
    try JSONSerialization.data(withJSONObject: notificationEvidence, options: [.prettyPrinted, .sortedKeys])
      .write(to: url.deletingPathExtension().appendingPathExtension("notifications.json"))
    try MacCatalogApp.core.commands.joined(separator: "\n")
      .write(to: url.deletingPathExtension().appendingPathExtension("commands.jsonl"), atomically: true, encoding: .utf8)
    try MacCatalogApp.core.unscripted.joined(separator: "\n")
      .write(to: url.deletingPathExtension().appendingPathExtension("unscripted.txt"), atomically: true, encoding: .utf8)
  }

  private struct SnapshotError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }
}


/// Repeatable state observations for the production history grid, never a queue.
@MainActor private enum MacHistoryMotionFixture {
  static func install(core: ScenarioCore, tick: Int) {
    var jobs: [[String: Any]] = (0..<96).map { index in
      let phase = (tick + index) % 4
      let changing = index < 3
      return ["id": 20_000 + index,
        "asset": ["source_id": "grid-motion-\(index)", "revision": "1", "kind": index % 6 == 0 ? "video" : "photo",
          "resources": [["filename": "CATALOG_\(index).JPG", "size": 4_800_000]],
          "metadata": ["source_type": "library", "created_at_ms": "1792495800000"]],
        "receiver_id": "catalog-pixel", "state": changing && phase < 2 ? "running" : "received",
        "confirmed_bytes": changing && phase < 2 ? (phase + 1) * 1_000_000 : 4_800_000,
        "processing": changing && phase == 2 ? "pending" : "complete",
        "state_changed_at_ms": 1_792_495_800_000 - index * 1000,
        "sort_value": 1_792_495_800_000 - index * 1000]
    }
    // One insertion, removal and move exercise diffing independently of marks.
    if tick >= 20 && tick < 40 {
      var inserted = jobs[0]; inserted["id"] = 30_000
      var asset = inserted["asset"] as! [String: Any]; asset["source_id"] = "grid-motion-inserted"; inserted["asset"] = asset
      jobs.insert(inserted, at: 4)
    }
    if tick >= 40 { let moved = jobs.remove(at: 8); jobs.insert(moved, at: 4) }
    let summary: [String: Any] = ["total": jobs.count, "received": jobs.count - 3, "published": jobs.count - 3,
      "publication_failed": 0, "waiting": 0, "failed": 0, "queued": 0, "running": 3, "paused": 0,
      "confirmed_bytes": 0, "active": 3, "attention": 0]
    core.setValue(jobs, for: "jobs")
    core.setValue(summary, for: "sender_summary")
    let items: [[String: Any]] = jobs.map { ["id": "job-\($0["id"]!)", "cursor": $0["id"]!,
      "sort_value": $0["sort_value"]!, "job": $0] }
    core.setValue(["items": items, "summary": summary], for: "backup_tasks")
    core.setValue(["items": [], "summary": summary], for: "backup_tasks", when: ["state": "attention"])
    if let log = MacCatalogLaunch.value("-motion-log"),
      let data = try? JSONSerialization.data(withJSONObject: ["tick": tick, "uptime": ProcessInfo.processInfo.systemUptime,
        "changing": ["job-20000", "job-20001", "job-20002"], "count": jobs.count], options: [.sortedKeys]) {
      let url = URL(fileURLWithPath: log)
      if !FileManager.default.fileExists(atPath: log) { FileManager.default.createFile(atPath: log, contents: nil) }
      if let handle = try? FileHandle(forWritingTo: url) { try? handle.seekToEnd(); try? handle.write(contentsOf: data + Data([10])); try? handle.close() }
    }
  }
}

/// Captures only this Catalog window. The stream requests every 60 Hz frame;
/// media timestamps are retained for cadence and pixel-change verification.
@available(macOS 15.0, *)
@MainActor private final class MacCatalogRecording: NSObject, SCRecordingOutputDelegate {
  private var completion: CheckedContinuation<Void, Error>?
  private static var active: MacCatalogRecording?
  static func record(path: String, seconds: Double) async throws {
    let recorder = MacCatalogRecording(); active = recorder
    defer { active = nil }
    guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
    let content = try await SCShareableContent.currentProcess
    guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { return }
    let filter = SCContentFilter(desktopIndependentWindow: target)
    let config = SCStreamConfiguration()
    config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
    config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.showsCursor = false; config.ignoreShadowsSingleWindow = true
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    let outputConfig = SCRecordingOutputConfiguration()
    outputConfig.outputURL = URL(fileURLWithPath: path)
    outputConfig.videoCodecType = .h264; outputConfig.outputFileType = .mp4
    let output = SCRecordingOutput(configuration: outputConfig, delegate: recorder)
    try stream.addRecordingOutput(output)
    try await stream.startCapture()
    try await Task.sleep(for: .seconds(seconds))
    try await withCheckedThrowingContinuation { continuation in
      recorder.completion = continuation
      Task { do { try await stream.stopCapture() } catch { recorder.finish(error) } }
    }
  }
  nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
    Task { @MainActor in self.finish(nil) }
  }
  nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
    Task { @MainActor in self.finish(error) }
  }
  private func finish(_ error: Error?) {
    if let error { completion?.resume(throwing: error) } else { completion?.resume() }
    completion = nil
  }
}

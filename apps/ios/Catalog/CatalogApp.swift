import Photos
import Combine
import SwiftUI
import UserNotifications

/// Design catalog: production pages driven by scenario data instead of the
/// Rust core, the keychain and the network. It never ships; see README.md.
@main struct CatalogApp: App {
  static let core = ScenarioCore()
  static let credentials = ScenarioCredentials()

  init() {
    BackupEnvironment.core = Self.core
    BackupEnvironment.credentials = Self.credentials
    BackupEnvironment.discoversReceivers = false
    BackupEnvironment.usesNetwork = false
    BackupEnvironment.usesCamera = false
    BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.sampleThumbnail = SampleImages.image(for:)
    // The catalog never asks for photo access; scenarios behave as if it was granted.
    BackupEnvironment.requestPhotoAccess = { true }
    BackupEnvironment.libraryCount = { 12_384 }
  }

  var body: some Scene {
    WindowGroup { CatalogHome() }
  }
}

private func catalogViewerStyle(_ scenario: Scenario) -> UIUserInterfaceStyle {
  let arguments = ProcessInfo.processInfo.arguments
  if let flag = arguments.firstIndex(of: "-appearance"), arguments.indices.contains(flag + 1) {
    return arguments[flag + 1] == "light" ? .light : .dark
  }
  return scenario.id.hasSuffix("-light") ? .light : .dark
}

private struct CatalogHome: View {
  @State private var scenarios: [Scenario] = []
  @State private var failure: String?
  @State private var open: Scenario?

  private var directLaunch: Bool { ProcessInfo.processInfo.arguments.contains("-scenario") }

  var body: some View {
    Group {
      if directLaunch, let open { ScenarioStage(scenario: open) }
      else { home }
    }
    .onAppear(perform: load)
    .task { await CatalogNotificationProbe.runIfRequested() }
  }

  private var home: some View {
    NavigationStack {
      List {
        if let failure { Text(failure).foregroundStyle(.red) }
        let firstRun = scenarios.filter { $0.page == "onboarding" }
        if !firstRun.isEmpty {
          Section("First run") { ForEach(firstRun) { scenario in row(scenario) } }
        }
        let connect = scenarios.filter { $0.page == "connect" }
        if !connect.isEmpty {
          Section("Connect") { ForEach(connect) { scenario in row(scenario) } }
        }
        ForEach(IOSAppTab.allCases) { tab in
          let items = scenarios.filter { $0.page == "\(tab)" }
          if !items.isEmpty {
            Section { ForEach(items) { scenario in row(scenario) } } header: { tab.label }
          }
        }
      }
      .navigationTitle("Design catalog")
    }
    .fullScreenCover(item: Binding(get: { directLaunch ? nil : open }, set: { open = $0 })) { scenario in
      ScenarioStage(scenario: scenario)
    }
  }

  private func row(_ scenario: Scenario) -> some View {
    Button { open = scenario } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(scenario.title).foregroundStyle(.primary)
        Text(scenario.id).font(.caption.monospaced()).foregroundStyle(.secondary)
      }
    }
    .accessibilityIdentifier("catalog.\(scenario.id)")
  }

  private func load() {
    do {
      scenarios = try Scenario.loadAll()
      // `-scenario <id>` opens one scenario directly, for screenshot runs.
      let arguments = ProcessInfo.processInfo.arguments
      if open == nil, let flag = arguments.firstIndex(of: "-scenario"), arguments.indices.contains(flag + 1) {
        open = scenarios.first { $0.id == arguments[flag + 1] }
      }
    } catch { failure = error.localizedDescription }
  }
}

/// Reads existing authorization only. An authorized Catalog can show the exact
/// production notification payload in a system banner without changing grants.
@MainActor private final class CatalogNotificationProbe: NSObject, UNUserNotificationCenterDelegate {
  static let shared = CatalogNotificationProbe()
  static func runIfRequested() async {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-notification-probe"),
      arguments.indices.contains(index + 1),
      let notice = BackupNotifier.Notice(rawValue: arguments[index + 1]) else { return }
    let center = UNUserNotificationCenter.current()
    let status = await center.notificationSettings().authorizationStatus
    var evidence: [String: Any] = ["authorization": status.rawValue, "requestedPermission": false, "notice": notice.rawValue]
    if status == .authorized || status == .provisional {
      center.delegate = shared
      let request = BackupNotifier(catalogAuthorization: status).request(notice,
        receiver: "catalog-pixel", name: "Pixel 8 Pro", conversions: 3)
      do { try await center.add(request); evidence["submitted"] = true }
      catch { evidence["error"] = error.localizedDescription }
    } else { evidence["submitted"] = false }
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("catalog-notification-probe.json"))
  }
  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }
}

/// One scenario in the production tab chrome. Restarting removes the run, which
/// stops its model, then starts a new model that replays the scenario.
private struct ScenarioStage: View {
  let scenario: Scenario
  @State private var run: UUID? = UUID()
  @State private var info = false
  @State private var scheme: ColorScheme?
  @State private var textSize: DynamicTypeSize?
  init(scenario: Scenario) {
    self.scenario = scenario
    if ProcessInfo.processInfo.arguments.contains("-large-text") {
      _textSize = State(initialValue: .xxxLarge)
    }
    if ProcessInfo.processInfo.arguments.contains("-appearance") || ["photoInformation", "photoViewer"].contains(scenario.step ?? "") || scenario.page == "onboarding" || scenario.id.hasPrefix("diagnostics.") {
      _scheme = State(initialValue: catalogViewerStyle(scenario) == .light ? .light : .dark)
    }
  }
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Group { if let run { ScenarioRun(scenario: scenario).id(run) } else { DuckRole.background.ignoresSafeArea() } }
      .preferredColorScheme(scheme)
      .environment(\.duckStepMarkReducedTransparency, ProcessInfo.processInfo.arguments.contains("-reduce-transparency"))
      .environment(\.duckFirstPhotoReducedMotion, ProcessInfo.processInfo.arguments.contains("-reduce-motion"))
      .transformEnvironment(\.dynamicTypeSize) { if let textSize { $0 = textSize } }
      .task {
        guard ProcessInfo.processInfo.arguments.contains("-measure-rows") else { return }
        try? await Task.sleep(for: .seconds(2))
        CatalogRowMeasurements.write()
      }
      .overlay(alignment: .bottomTrailing) {
        if !ProcessInfo.processInfo.arguments.contains("-capture") && !["photoInformation", "photoViewer"].contains(scenario.step ?? "") && scenario.page != "onboarding" && !scenario.id.hasPrefix("diagnostics.") {
        // Above the tab bar, clear of navigation bar items.
        Button { info = true } label: {
          Image(systemName: "info.circle.fill").font(.title2)
            .padding(10).background(.thinMaterial, in: Circle())
        }
        .padding(.trailing, 12).padding(.bottom, 96)
        .accessibilityLabel("Scenario")
        .accessibilityIdentifier("catalog.info")
        }
      }
      .sheet(isPresented: $info) {
        ScenarioInfo(scenario: scenario, scheme: $scheme, textSize: $textSize,
          restart: {
            info = false; run = nil
            DispatchQueue.main.async { run = UUID() }
          },
          close: { info = false; dismiss() })
      }
  }
}

/// Native cell frames supplement screenshot measurements without changing
/// device settings. Only explicit catalog measurement runs write this file.
@MainActor private enum CatalogRowMeasurements {
  static func write() {
    var rows: [[String: Any]] = []
    func visit(_ view: UIView, window: UIWindow) {
      if let cell = view as? UICollectionViewCell, !cell.isHidden {
        let frame = cell.convert(cell.bounds, to: window)
        rows.append(["x": frame.minX, "y": frame.minY, "width": frame.width,
          "height": frame.height, "scale": window.screen.scale])
      }
      for child in view.subviews { visit(child, window: window) }
    }
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      for window in scene.windows where !window.isHidden { visit(window, window: window) }
    }
    let notifier = BackupEnvironment.activeNotifier()
    let result: [String: Any] = ["rows": rows, "authorization": notifier.authorization.rawValue,
      "permissionRequests": notifier.permissionRequests, "settingsRequests": notifier.settingsRequests,
      "usesSystem": notifier.usesSystem,
      "networkingStarted": BackupEnvironment.activeModel().networkingStarted,
      "backgroundSessionStarted": BackgroundTransfer.shared.sessionStarted,
      "diagnosticsMonitoring": TransferDiagnostics.shared.monitoring,
      "coreCommands": CatalogApp.core.commands]
    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
      let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      try? data.write(to: directory.appendingPathComponent("catalog-row-measurements.json"), options: .atomic)
    }
  }
}

private struct ScenarioRun: View {
  let scenario: Scenario
  @StateObject private var model: BackupModel
  @StateObject private var library: PhotoLibraryModel
  @State private var tab: IOSAppTab
  @State private var scopeFixture: ScopeCatalogFixture?
  @State private var hubNotification: BackupNotifier.Route?
  @State private var showingLiveHelp = false

  init(scenario: Scenario) {
    self.scenario = scenario
    _scopeFixture = State(initialValue: scenario.id.hasPrefix("settings.scope.") ? ScopeCatalogFixture(id: scenario.id) : nil)
    let authorization: UNAuthorizationStatus = scenario.notificationAuthorization == "denied" ? .denied
      : scenario.notificationAuthorization == "authorized" ? .authorized : .notDetermined
    let notifier = BackupNotifier(catalogAuthorization: authorization)
    BackupEnvironment.activeNotifier = { notifier }
    _library = StateObject(wrappedValue: PhotoLibraryModel())
    let made = scenario.makeModel(core: CatalogApp.core, credentials: CatalogApp.credentials)
    BackupEnvironment.activeModel = { made }
    _model = StateObject(wrappedValue: made)
    let start = IOSAppTab.allCases.first { "\($0)" == scenario.page } ?? .settings
    _tab = State(initialValue: start)
  }

  var body: some View {
    if scenario.step == "photoAccessDenied" || scenario.step == "photoAccessRestricted" {
      NavigationStack {
        LibraryPlaceholder(kind: .permission(scenario.step == "photoAccessDenied" ? .denied : .restricted))
          .background(DuckRole.background).navigationTitle("nav_photos")
      }
    } else if scenario.step == "selectionReview" {
      SelectionReviewCatalog(mode: scenario.id.components(separatedBy: ".").last ?? "open", model: model,
        appearance: catalogViewerStyle(scenario))
        .ignoresSafeArea()
        .task { await model.open() }.onDisappear { model.stop() }
    } else if scenario.step == "contextSheetInventory" {
      ContextSheetInventoryCatalog(model: model, history: scenario.id.hasSuffix("history"))
        .onDisappear { model.stop() }
    } else if scenario.step == "selectedBackup" {
      SelectionBackupCatalog(mode: scenario.id.components(separatedBy: ".").last ?? "direct")
    } else if ["photoInformation", "photoViewer"].contains(scenario.step ?? "") {
      IOSInformationCatalog(model: model, panelStyle: catalogViewerStyle(scenario), showInformation: scenario.step == "photoInformation" || scenario.id == "photo.viewer-info", unregistered: ["photo.viewer-not-backed-up", "photo.viewer-state-change"].contains(scenario.id), immersive: scenario.id.hasSuffix("-immersive"), stateChange: scenario.id == "photo.viewer-state-change")
        .task { await model.open() }.onDisappear { model.stop() }
    } else if scenario.step == "liveActivity" {
      LiveActivityCatalogPage(model: model, stale: scenario.id.hasSuffix(".stale"))
        .task { await model.open() }.onDisappear { model.stop() }
    } else if scenario.page == "connect" {
      IOSConnectSheet(model: model, reconnect: scenario.step == "reconnect", scanner: scenario.scannerState()).task { await model.open() }.onDisappear { model.stop() }
    } else if scenario.page == "onboarding" {
      OnboardingCatalog(scenario: scenario, model: model)
        .task { await model.open() }
        .onDisappear { model.stop() }
    } else {
      tabs
    }
  }

  private var tabs: some View {
    TabView(selection: $tab) {
      ForEach(IOSAppTab.allCases) { item in
        page(item).duckTabSurface().tabItem { item.label }.tag(item)
      }
    }
    .environment(\.duckReservedSettingsContent, scenario.reservedSettingsContent)
    .background(DuckRole.background.ignoresSafeArea())
    .tint(DuckRole.accent)
    .task {
      await model.open()
      if ProcessInfo.processInfo.arguments.contains("-cache-action") { await model.reclaimCache() }
    }
    .onDisappear { model.stop() }
  }

  @ViewBuilder private func page(_ item: IOSAppTab) -> some View {
    switch item {
    case .library where scenario.library != nil:
      IOSLibraryPage(library: library, model: model)
        .task {
          await library.open()
          if let view = scenario.libraryView { await library.changeBackupView(view) }
        }
        .onChange(of: model.pairing?.receiverID, initial: true) { _, receiver in library.backupReceiver = receiver }
    case .backup where "\(item)" == scenario.page:
      // With a library scenario the hub opens the library's backup views (design/library.md).
      IOSHub(model: model, records: scenario.records, notification: $hubNotification, showLibrary: scenario.library == nil ? nil : { view in
        tab = .library
        Task { await library.changeBackupView(view) }
      })
      .sheet(isPresented: $showingLiveHelp) { LivePhotoHelpSheet() }
      .task(id: model.pairing?.receiverID) {
        if scenario.step == "liveHelp" { showingLiveHelp = true }
        if scenario.step == "offlineHelp", let receiver = model.pairing?.receiverID {
          hubNotification = BackupNotifier.Route(notice: .unreachable, receiver: receiver)
        }
      }
    case .settings where "\(item)" == scenario.page:
      if scenario.id.hasPrefix("diagnostics.") {
        IOSDiagnosticsCatalog(model: model, page: scenario.step)
      } else if let scopeFixture {
        IOSScopeCatalog(fixture: scopeFixture)
      } else if let detail = scenario.step {
        // A settings sub-page opened directly, as if pushed from Settings.
        NavigationStack { IOSSettingsDetail(name: detail, model: model) }
      } else { IOSSettings(model: model, showBottom: ["settings.bottom", "settings.feedback", "settings.feedback-reserved"].contains(scenario.id))
          .environment(\.duckFeedbackPreview, ["settings.feedback", "settings.feedback-reserved"].contains(scenario.id)) }
    default:
      ContentUnavailableView("Not in this scenario", systemImage: item.symbol,
        description: Text(scenario.id))
    }
  }
}

private struct IOSInformationCatalog: View {
  @ObservedObject var model: BackupModel
  var panelStyle: UIUserInterfaceStyle
  var showInformation = true
  var unregistered = false
  var immersive = false
  var stateChange = false
  var body: some View {
    if let job = model.jobs.first ?? (unregistered ? Self.unregisteredAsset : nil) {
      if ProcessInfo.processInfo.arguments.contains("fallback") {
        PhotoBackupDetail(photo: HistoryPhoto(job: job), model: model)
      } else { InformationViewerSample(job: job, model: model, panelStyle: panelStyle, showInformation: showInformation, immersive: immersive, stateChange: stateChange).ignoresSafeArea() }
    } else { ProgressView() }
  }
  // Media metadata only: this does not add a job to the model or core.
  private static var unregisteredAsset: BackupJob {
    BackupJob(id: 801, asset: BackupJob.Asset(metadata: ["created_at_ms": "1792495800000"],
      kind: "photo", source_id: "a8-synthetic-photo", revision: "1",
      resources: [.init(filename: "IMG_0801.HEIC", size: 4800000)]),
      state: "queued", confirmedBytes: 0, errorCode: nil)
  }
}

/// Opens the production viewer and its actual drawer; no replacement gestures.
private struct InformationViewerSample: UIViewControllerRepresentable {
  let job: BackupJob
  let model: BackupModel
  let panelStyle: UIUserInterfaceStyle
  let showInformation: Bool
  let immersive: Bool
  let stateChange: Bool
  func makeUIViewController(context: Context) -> UINavigationController {
    let arguments = ProcessInfo.processInfo.arguments
    let asset: PHAsset
    let neighbors: [PHAsset]
    // Read-only simulator comparison of a specified fixture already in Photos.
    // Never request permission or alter the library as part of a capture.
    if let flag = arguments.firstIndex(of: "-viewer-asset"), arguments.indices.contains(flag + 1),
      PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized,
      let reference = PHAsset.fetchAssets(withLocalIdentifiers: [arguments[flag + 1]], options: nil).firstObject {
      asset = reference
      let options = PHFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      let assets = PHAsset.fetchAssets(with: options)
      var collection: [PHAsset] = []
      assets.enumerateObjects { asset, _, _ in collection.append(asset) }
      neighbors = collection
    } else {
      let sample = InformationSampleAsset(job: job)
      asset = sample
      neighbors = (0..<13).map {
        $0 == 6 ? sample : InformationSampleAsset(job: job, identifier: "viewer-neighbor-\($0)")
      }
    }
    let session = MediaPreviewSession(asset: asset, library: PhotoLibraryModel(), reviewAssets: neighbors)
    let item = IOSPreviewItem(asset: asset, frame: .zero, poster: (asset as? any PreviewSample)?.previewImage)
    let viewer = NativeMediaViewer(item: item, session: session, close: {})
    viewer.backupModel = model
    let recordQueued: @MainActor (String) -> Void = { source in
      let queued: [String: Any] = ["id": 801, "receiver_id": "catalog-pixel", "state": "queued", "confirmed_bytes": 0,
        "asset": ["kind": "photo", "source_id": source, "revision": "1",
          "resources": [["filename": "IMG_0801.HEIC", "size": 4800000]],
          "metadata": ["created_at_ms": "1792495800000"]]]
      CatalogApp.core.setValue(queued, for: "source_job")
      CatalogApp.core.setValue([source: ["revision": "1", "preparing": false, "tile_state": "sending"]], for: "library_source_states")
      CatalogApp.core.setValue([queued], for: "jobs")
      Self.recordHistory(queued)
      model.queueRevision += 1
    }
    viewer.backupRequest = { [weak viewer] in
      guard let viewer else { return }
      await viewer.backupAction.perform({
        recordQueued(viewer.session.current.asset.localIdentifier); return true
      }, failure: { nil })
    }
    viewer.retryRequest = { job in
      recordQueued(job.asset.source_id)
      return await model.retry(job.id)
    }
    let nav = MediaViewerNavigationController(rootViewController: viewer)
    nav.overrideUserInterfaceStyle = panelStyle
    viewer.loadViewIfNeeded()
    context.coordinator.open(viewer, information: showInformation, immersive: immersive,
      stateChange: stateChange, model: model, source: asset.localIdentifier)
    return nav
  }
  func updateUIViewController(_ controller: UINavigationController, context: Context) {}
  func makeCoordinator() -> Coordinator { Coordinator() }
  private static func recordHistory(_ job: [String: Any]) {
    // Keep the history endpoint consistent with each synthetic source observation.
    let id = job["id"] as? Int ?? 801
    let failed = job["state"] as? String == "failed" || job["processing"] as? String == "failed"
    var summary = Dictionary(uniqueKeysWithValues: ["total", "received", "published", "publication_failed",
      "waiting", "failed", "queued", "running", "paused", "confirmed_bytes", "active", "attention"].map { ($0, 0) })
    summary["total"] = 1; summary["attention"] = failed ? 1 : 0
    if let state = job["state"] as? String, summary[state] != nil { summary[state] = 1 }
    summary["published"] = job["processing"] as? String == "complete" ? 1 : 0
    summary["publication_failed"] = job["processing"] as? String == "failed" ? 1 : 0
    summary["active"] = failed || summary["published"] == 1 ? 0 : 1
    summary["confirmed_bytes"] = job["confirmed_bytes"] as? Int ?? 0
    let items: [[String: Any]] = [["id": "job-\(id)", "cursor": id,
      "sort_value": job["state_changed_at_ms"] ?? 1792534500000, "job": job]]
    CatalogApp.core.setValue(["items": items, "summary": summary], for: "backup_tasks")
    CatalogApp.core.setValue(["items": failed ? items : [], "summary": summary],
      for: "backup_tasks", when: ["state": "attention"])
  }
  final class Coordinator {
    var task: Task<Void, Never>?
    func open(_ viewer: NativeMediaViewer, information: Bool, immersive: Bool, stateChange: Bool, model: BackupModel, source: String) {
      task = Task { @MainActor [weak viewer] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(100))
          guard let viewer else { return }
          if viewer.viewIfLoaded?.window != nil, !viewer.flying {
            if information { viewer.titleButton.sendActions(for: .touchUpInside) }
            if immersive { viewer.setChrome(false, animated: false) }
            if ProcessInfo.processInfo.arguments.contains("-viewer-info") { viewer.titleButton.sendActions(for: .touchUpInside) }
            if stateChange {
              // Let the enclosing system presentation settle before advancing facts.
              try? await Task.sleep(for: .seconds(1))
              await self.changeState(model: model, source: source)
            }
            if information, ProcessInfo.processInfo.arguments.contains("-viewer-info-bottom") {
              try? await Task.sleep(for: .seconds(1))
              viewer.informationHost?.view.layoutIfNeeded()
              if let host = viewer.informationHost?.view, let scroll = self.informationScroll(in: host) {
                scroll.setContentOffset(CGPoint(x: 0,y: max(-scroll.adjustedContentInset.top,
                  scroll.contentSize.height-scroll.bounds.height+scroll.adjustedContentInset.bottom)), animated: false)
              }
            }
            return
          }
        }
      }
    }
    @MainActor private func changeState(model: BackupModel, source: String) async {
      try? await Task.sleep(for: .seconds(1))
      for step in 0...10 {
        guard !Task.isCancelled else { return }
        let saved = step == 10
        var value: [String: Any] = ["id": 801, "receiver_id": "catalog-pixel",
          "state": saved ? "received" : "running", "confirmed_bytes": step * 480000,
          "asset": ["kind": "photo", "source_id": source, "revision": "1",
            "resources": [["filename": "IMG_0801.HEIC", "size": 4800000]],
            "metadata": ["created_at_ms": "1792495800000"]]]
        if saved {
          value["processing"] = "complete"
          value["received_at_ms"] = 1792534500000
          value["published_at_ms"] = 1792534560000
        }
        CatalogApp.core.setValue(value, for: "source_job")
        CatalogApp.core.setValue([source: ["revision": "1", "preparing": false,
          "tile_state": saved ? "saved" : "sending"]], for: "library_source_states")
        CatalogApp.core.setValue([value], for: "jobs")
        InformationViewerSample.recordHistory(value)
        model.queueRevision += 1
        try? await Task.sleep(for: .milliseconds(300))
      }
    }
    private func informationScroll(in view: UIView) -> UIScrollView? {
      if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height { return scroll }
      return view.subviews.lazy.compactMap { self.informationScroll(in: $0) }.first
    }
    deinit { task?.cancel() }
  }
}

private struct ScenarioInfo: View {
  let scenario: Scenario
  @Binding var scheme: ColorScheme?
  @Binding var textSize: DynamicTypeSize?
  let restart: () -> Void
  let close: () -> Void
  @State private var unscripted: [String] = []

  var body: some View {
    NavigationStack {
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
                Text(item.result).font(.callout).foregroundStyle(.secondary)
              }
            }
          }
        }
        Section {
          if unscripted.isEmpty { Text("None").foregroundStyle(.secondary) }
          ForEach(unscripted, id: \.self) { Text($0).font(.body.monospaced()).foregroundStyle(.red) }
        } header: { Text("Unscripted core commands") } footer: {
          Text("These commands failed with catalog_unscripted. Script them before reviewing the page.")
        }
        Section("Review") {
          Picker("Appearance", selection: $scheme) {
            Text("System").tag(ColorScheme?.none)
            Text("Light").tag(ColorScheme?.some(.light))
            Text("Dark").tag(ColorScheme?.some(.dark))
          }
          Picker("Text size", selection: $textSize) {
            Text("System").tag(DynamicTypeSize?.none)
            Text("Large").tag(DynamicTypeSize?.some(.large))
            Text("XXX Large").tag(DynamicTypeSize?.some(.xxxLarge))
            Text("Accessibility 3").tag(DynamicTypeSize?.some(.accessibility3))
          }
        }
        Section {
          Button("Restart scenario", action: restart).accessibilityIdentifier("catalog.restart")
          Button("Close scenario", role: .destructive, action: close).accessibilityIdentifier("catalog.close")
        }
      }
      .navigationTitle("Scenario")
      .navigationBarTitleDisplayMode(.inline)
    }
    .onAppear { unscripted = CatalogApp.core.unscripted }
    .presentationDetents([.medium, .large])
  }
}

/// A real push into the production editor, so system Back and search restoration
/// can be reviewed as part of the scenario rather than at a root-only endpoint.
private struct IOSScopeCatalog: View {
  let fixture: ScopeCatalogFixture
  @State private var path: [BackupScopeDestination]
  init(fixture: ScopeCatalogFixture) {
    self.fixture = fixture
    _path = State(initialValue: [fixture.destination])
  }
  var body: some View {
    NavigationStack(path: $path) {
      List {
        NavigationLink("scope_media_types", value: BackupScopeDestination.types)
        NavigationLink("scope_albums_title", value: BackupScopeDestination.albums)
      }.navigationTitle("settings_auto_backup")
        .navigationDestination(for: BackupScopeDestination.self) { destination in
          BackupScopeEditor(destination: destination, store: fixture.store, model: fixture.albums,
            search: destination == .albums ? fixture.search : "")
        }
    }
  }
}

/// The same durable state/root transition as production, with isolated defaults.
/// Resume and deferred-notification fixtures retain intent across launches.
private struct OnboardingCatalog: View {
  let scenario: Scenario
  @ObservedObject var model: BackupModel
  @StateObject private var progress: IOSFirstRunProgress
  @StateObject private var scanner: IOSPixelScannerState
  init(scenario: Scenario, model: BackupModel) {
    self.scenario = scenario; self.model = model
    _scanner = StateObject(wrappedValue: scenario.scannerState())
    let arguments = ProcessInfo.processInfo.arguments
    let session = arguments.firstIndex(of: "-onboarding-session").flatMap { index in
      arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
    } ?? "default"
    let suite = "catalog.firstRun." + scenario.id + "." + session
    let defaults = UserDefaults(suiteName: suite)!
    let progress = IOSFirstRunProgress(defaults: defaults)
    if !["onboarding.resume-mid-flow", "onboarding.background-landing"].contains(scenario.id) || progress.record == nil {
      progress.update {
        $0 = IOSFirstRunProgress.Record()
        $0.step = scenario.step ?? "welcome"
        $0.receiver = "catalog-pixel"
        if $0.step == "notificationInvitation" { $0.completed = true }
        if $0.step == "first" {
          let slow = scenario.id.contains("slow") || scenario.id.hasSuffix("none")
          $0.firstPhotoStarted = Date().addingTimeInterval(slow ? -21 : 0)
        }
      }
    }
    _progress = StateObject(wrappedValue: progress)
  }
  var body: some View {
    Group {
      if progress.record?.completed == true {
        IOSHub(model: model).modifier(IOSFirstRunNotificationInvitation(progress: progress, model: model))
      } else {
        IOSOnboarding(model: model, progress: progress, scanner: scanner)
      }
    }
  }
}

extension Scenario {
  @MainActor func scannerState() -> IOSPixelScannerState {
    let state = IOSPixelScannerState()
    if let cameraFailure { state.cameraFailure = cameraFailure == "permission" ? .permission : .unavailable }
    if let connectionFailure, let failure = ConnectAccessFailure(rawValue: connectionFailure) {
      state.scanError = failure.localizedDescription
      state.connectionNeedsSettings = true
      // Retains a synthetic code for an explicit retry; never contacts a peer.
      state.payload = #"{"version":2,"receiver_id":"catalog-pixel","endpoint":"https://127.0.0.1:1","certificate":"fixture","token":"fixture"}"#
    }
    return state
  }
}

/// Opens the production diagnostics as a pushed Settings destination.
private struct IOSDiagnosticsCatalog: View {
  @ObservedObject var model: BackupModel
  var page: String?
  @State private var opened = false
  @State private var show = false
  var body: some View {
    NavigationStack {
      Form {
        NavigationLink(isActive: $show) { DiagnosticsView(model: model, initialPage: page) } label: {
          Text("settings_diagnostics")
        }
      }.navigationTitle("nav_settings")
        .task { if !opened { opened = true; show = true } }
    }
  }
}

/// Frozen sample membership; both selection entry points invoke the same action.
private struct SelectionReviewCatalog: UIViewControllerRepresentable {
  let mode: String
  let model: BackupModel
  let appearance: UIUserInterfaceStyle
  func makeUIViewController(context: Context) -> UINavigationController {
    let nav = CalendarNavigationController(rootViewController: SelectionReviewSample(mode: mode, model: model, appearance: appearance))
    nav.overrideUserInterfaceStyle = appearance
    return nav
  }
  func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

private final class SelectionReviewAsset: PHAsset, PreviewSample, @unchecked Sendable {
  let number: Int
  init(_ number: Int) { self.number = number; super.init() }
  override var localIdentifier: String { "selection-review-\(number)" }
  override var creationDate: Date? { Calendar.current.date(byAdding: .month, value: number / 4 - 12, to: Date(timeIntervalSince1970: 1792495800)) }
  override var modificationDate: Date? { creationDate }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var location: CLLocation? { nil }
  override var pixelWidth: Int { Int(previewImage?.size.width ?? 480) }
  override var pixelHeight: Int { Int(previewImage?.size.height ?? 480) }
  var previewFilename: String { "Selection-\(number).jpg" }
  var previewMetadata: [(String, String)] { [] }
  var previewImage: LibraryImage? {
    SampleImages.cgImage(for: localIdentifier).map { UIImage(cgImage: $0) }
  }
}

final class SelectionReviewSample: UIViewController {
  let mode: String, model: BackupModel
  let appearance: UIUserInterfaceStyle
  let library = PhotoLibraryModel(), action = SelectionBackupAction()
  private let photos = (0..<48).map(SelectionReviewAsset.init)
  let calendar = CalendarGridController()
  override var navigationItem: UINavigationItem { calendar.navigationItem }
  override var childForStatusBarStyle: UIViewController? { calendar }
  private var observation: AnyCancellable?
  private var opened = false
  init(mode: String, model: BackupModel, appearance: UIUserInterfaceStyle) {
    self.mode = mode; self.model = model; self.appearance = appearance
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(calendar); view.addSubview(calendar.view); calendar.didMove(toParent: self)
    calendar.requestImage = { [weak self] item, pixels, done in
      guard let self, let asset = self.photos.first(where: { $0.localIdentifier == item.id }) else { return {} }
      let request = self.library.thumbnails.request(asset, pixels: pixels, completion: done)
      return { [weak self] in self?.library.thumbnails.cancel(request) }
    }
    calendar.requestUncroppedImage = calendar.requestImage
    calendar.photoPreview = { [weak self] item, poster in
      guard let self, let asset = self.photos.first(where: { $0.localIdentifier == item.id }) else { return nil }
      return LibraryPhotoPreview(asset: asset, pipeline: self.library.thumbnails, poster: poster)
    }
    calendar.onSelection = { [weak self] ids in
      guard let self else { return }
      self.library.selection = ids; self.action.selectionChanged(); self.refresh()
    }
    calendar.onBackup = { [weak self] in
      guard let self else { return }
      if self.mode == "repeat" { self.action.confirmingRepeat = true; self.refresh() }
      else { self.submit() }
    }
    calendar.configureReview = { [weak self] review in
      guard let self else { return }
      review.photoMenu = { [weak self, weak review] item in
        guard let self, let review, let asset = self.photos.first(where: { $0.localIdentifier == item.id }) else { return nil }
        return LibraryPhotoActions.menu(asset: asset, library: self.library, model: self.model, presenter: review)
      }
      review.photoAccessibilityActions = { [weak self, weak review] item in
        guard let self, let review, let asset = self.photos.first(where: { $0.localIdentifier == item.id }) else { return [] }
        return LibraryPhotoActions.accessibilityActions(asset: asset, library: self.library, model: self.model, presenter: review)
      }
      review.onPreview = { [weak self] review in
        guard let self else { return }
        let photos = review.assets.compactMap { item in self.photos.first { $0.localIdentifier == item.id } }
        presentSelectedMediaReview(from: review, assets: photos, library: self.library)
      }
    }
    calendar.columns = 3
    calendar.replaceAssets(photos.map {
      CalendarGridAsset(id: $0.localIdentifier, date: $0.creationDate,
        aspect: CGFloat($0.pixelWidth) / CGFloat(max(1, $0.pixelHeight)))
    })
    let arguments = ProcessInfo.processInfo.arguments
    let startZoom = arguments.firstIndex(of: "-start-zoom").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    calendar.selecting = startZoom == nil
    let ids = Set(stride(from: 1, to: 48, by: 4).map { photos[$0].localIdentifier })
    calendar.selected = startZoom == nil ? ids : []; library.selection = calendar.selected
    refresh()
    observation = action.objectWillChange.sink { [weak self] in
      DispatchQueue.main.async { self?.refresh() }
    }
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); calendar.view.frame = view.bounds }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // A fixture starts at its settled chrome state. The navigation host installs
    // status-bar containment next; interrupting this reveal there preserves a
    // nearly transparent presentation value in the standalone Catalog host.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.calendar.selectionReview == nil else { return }
      // Re-enter the fixture's production chrome after containment has completed;
      // a cancelled reveal already retained its target enum with partial opacity.
      self.calendar.chrome = .navigation
      self.calendar.refreshSelection()
      self.settleInitialChrome()
    }
    guard !opened else { return }; opened = true
    // Include system-owned sheet chrome in the Catalog's app-only appearance.
    view.window?.overrideUserInterfaceStyle = appearance
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("-measure-selection") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.measureSelection() }
    }
    if let flag = arguments.firstIndex(of: "-start-zoom"), arguments.indices.contains(flag + 1) {
      calendar.changeLevel(arguments[flag + 1] == "years" ? .years : .months, asset: photos.count - 1, from: nil)
      settleInitialChrome()
    } else if mode != "selected" {
      calendar.reviewSelection()
      calendar.selectionReview?.navigationController?.overrideUserInterfaceStyle = appearance
      if mode == "deselected", let review = calendar.selectionReview, let first = review.assets.first {
        var ids = review.selected; ids.remove(first.id); review.setSelection(ids)
      }
      if mode == "feedback" { submit() }
    }
  }
  private func settleInitialChrome() {
    guard let motion = calendar.chromeMotion else { return }
    motion.stopAnimation(false)
    motion.finishAnimation(at: .end)
  }
  private func measureSelection() {
    let button = calendar.selectedButton
    func traits(_ view: UIView) -> [String: Any] {
      ["class": String(describing: type(of: view)), "style": view.traitCollection.userInterfaceStyle.rawValue,
       "tintAdjustment": view.tintAdjustmentMode.rawValue, "alpha": view.alpha,
       "tint": String(describing: view.tintColor), "frame": String(describing: view.frame)]
    }
    var parents: [[String: Any]] = []; var node: UIView? = button
    while let view = node { parents.append(traits(view)); node = view.superview }
    let result: [String: Any] = ["enabled": button.isEnabled, "selected": calendar.selected.count,
      "title": button.titleLabel?.text ?? "", "color": String(describing: button.titleLabel?.textColor),
      "configurationColor": String(describing: button.configuration?.baseForegroundColor),
      "chrome": String(describing: calendar.chrome), "active": calendar.active,
      "motion": String(describing: calendar.chromeMotion?.state), "parents": parents]
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("selection-measurement.json"), options: .atomic)
  }
  private func submit() {
    Task { @MainActor in
      await action.perform({
        try? await Task.sleep(for: .milliseconds(400))
        if self.mode == "failure" { return false }
        self.library.selection = []; return true
      }, failure: { NSLocalizedString("apple_selected_backup_failed", comment: "") })
      refresh()
    }
  }
  private func refresh() {
    calendar.canBackup = !action.busy
    calendar.selected = library.selection
    calendar.setBackupFeedback(title: action.title, added: action.added)
    if action.added && library.selection.isEmpty { calendar.completeSelectedBackup() }
    calendar.refreshSelection()
    guard let review = calendar.selectionReview else { return }
    review.setSelection(library.selection, notify: false)
    review.setBackupFeedback(title: action.title, enabled: !action.busy, added: action.added)
    if action.confirmingRepeat, review.presentedViewController == nil {
      let dialog = UIAlertController(title: NSLocalizedString("selection_backup_repeat_title", comment: ""),
        message: NSLocalizedString("selection_backup_repeat_note", comment: ""), preferredStyle: .actionSheet)
      dialog.addAction(UIAlertAction(title: NSLocalizedString("selection_backup_repeat_action", comment: ""), style: .default) { [weak self] _ in
        self?.action.confirmingRepeat = false; self?.submit()
      })
      dialog.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel) { [weak self] _ in self?.action.cancel() })
      dialog.popoverPresentationController?.barButtonItem = review.backupItem
      review.present(dialog, animated: true)
    } else if let error = action.error, review.presentedViewController == nil {
      let alert = UIAlertController(title: NSLocalizedString("selection_backup_failed_title", comment: ""), message: error, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: NSLocalizedString("settings_done", comment: ""), style: .default) { [weak self] _ in self?.action.error = nil })
      review.present(alert, animated: true)
    }
  }
}

/// Inventory of the unchanged close-only production sheets on synthetic assets.
private struct ContextSheetInventoryCatalog: UIViewControllerRepresentable {
  let model: BackupModel
  let history: Bool
  func makeUIViewController(context: Context) -> UIViewController { Host(model: model, history: history) }
  func updateUIViewController(_ controller: UIViewController, context: Context) {}
  private final class Host: UIViewController {
    let model: BackupModel
    let history: Bool
    var opened = false
    init(model: BackupModel, history: Bool) { self.model = model; self.history = history; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .systemBackground }
    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      guard !opened else { return }; opened = true
      Task { @MainActor in
        await model.open()
        for _ in 0..<20 where model.jobs.isEmpty {
          await model.refresh(includeStorage: false)
          try? await Task.sleep(for: .milliseconds(50))
        }
        guard let job = model.jobs.first else { return }
        LibraryPhotoActions.perform(history ? "library_context_history" : "library_context_backup",
          asset: InformationSampleAsset(job: job), library: PhotoLibraryModel(), model: model, presenter: self)
      }
    }
  }
}

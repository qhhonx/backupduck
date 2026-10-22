import Photos
import SwiftUI

/// Design catalog: production pages driven by scenario data instead of the
/// Rust core, the keychain and the network. It never ships; see README.md.
@main struct CatalogApp: App {
  static let core = ScenarioCore()
  static let credentials = ScenarioCredentials()

  init() {
    BackupEnvironment.core = Self.core
    BackupEnvironment.credentials = Self.credentials
    BackupEnvironment.discoversReceivers = false
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

  var body: some View {
    NavigationStack {
      List {
        if let failure { Text(failure).foregroundStyle(.red) }
        let firstRun = scenarios.filter { $0.page == "onboarding" }
        if !firstRun.isEmpty {
          Section("First run") { ForEach(firstRun) { scenario in row(scenario) } }
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
    .onAppear(perform: load)
    .fullScreenCover(item: $open) { scenario in ScenarioStage(scenario: scenario) }
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

/// One scenario in the production tab chrome. Restarting removes the run, which
/// stops its model, then starts a new model that replays the scenario.
private struct ScenarioStage: View {
  let scenario: Scenario
  @State private var run: UUID? = UUID()
  @State private var info = false
  @State private var scheme: ColorScheme?
  @State private var textSize: DynamicTypeSize?
  /// Current production page or the proposed redesign, for side-by-side review.
  @State private var proposed: Bool
  init(scenario: Scenario) {
    self.scenario = scenario
    if ["photoInformation", "photoViewer"].contains(scenario.step ?? "") {
      _scheme = State(initialValue: catalogViewerStyle(scenario) == .light ? .light : .dark)
    }
    _proposed = State(initialValue: ProcessInfo.processInfo.arguments.contains("-proposed") || scenario.id.hasPrefix("settings.scope.") || ["settings.bottom", "settings.about", "settings.feedback", "settings.about-reserved", "settings.feedback-reserved"].contains(scenario.id))
  }
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Group { if let run { ScenarioRun(scenario: scenario, proposed: proposed).id(run) } else { DuckRole.background.ignoresSafeArea() } }
      .preferredColorScheme(scheme)
      .transformEnvironment(\.dynamicTypeSize) { if let textSize { $0 = textSize } }
      .overlay(alignment: .bottomTrailing) {
        if !["photoInformation", "photoViewer"].contains(scenario.step ?? "") {
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
        ScenarioInfo(scenario: scenario, scheme: $scheme, textSize: $textSize, proposed: $proposed,
          restart: {
            info = false; run = nil
            DispatchQueue.main.async { run = UUID() }
          },
          close: { info = false; dismiss() })
      }
  }
}

private struct ScenarioRun: View {
  let scenario: Scenario
  let proposed: Bool
  @StateObject private var model: BackupModel
  @StateObject private var library: PhotoLibraryModel
  @State private var tab: IOSAppTab
  @State private var scopeFixture: ScopeCatalogFixture?

  init(scenario: Scenario, proposed: Bool) {
    self.scenario = scenario
    self.proposed = proposed
    _scopeFixture = State(initialValue: scenario.id.hasPrefix("settings.scope.") ? ScopeCatalogFixture(id: scenario.id) : nil)
    // Shared code (library menu, tile marks) reads the same switch as the Mac catalog.
    DesignPreview.proposedDesign = proposed
    _library = StateObject(wrappedValue: PhotoLibraryModel())
    let made = scenario.makeModel(core: CatalogApp.core, credentials: CatalogApp.credentials)
    BackupEnvironment.activeModel = { made }
    _model = StateObject(wrappedValue: made)
    let start = IOSAppTab.allCases.first { "\($0)" == scenario.page } ?? .settings
    // The proposed skeleton has no Receiver tab; its page opens from Settings.
    _tab = State(initialValue: proposed && !IOSAppTab.proposedCases.contains(start) ? .settings : start)
  }

  var body: some View {
    if scenario.step == "selectedBackup" {
      SelectionBackupCatalog(mode: scenario.id.components(separatedBy: ".").last ?? "direct")
    } else if ["photoInformation", "photoViewer"].contains(scenario.step ?? "") {
      IOSInformationCatalog(model: model, panelStyle: catalogViewerStyle(scenario), showInformation: scenario.step == "photoInformation" || scenario.id == "photo.viewer-info", unregistered: ["photo.viewer-not-backed-up", "photo.viewer-state-change"].contains(scenario.id), immersive: scenario.id.hasSuffix("-immersive"), stateChange: scenario.id == "photo.viewer-state-change")
        .task { await model.open() }.onDisappear { model.stop() }
    } else if scenario.step == "liveActivity" {
      LiveActivityCatalogPage(model: model, stale: scenario.id.hasSuffix(".stale"))
        .task { await model.open() }.onDisappear { model.stop() }
    } else if scenario.page == "connect" {
      IOSConnectSheet(model: model).task { await model.open() }.onDisappear { model.stop() }
    } else if scenario.page == "onboarding" {
      IOSOnboarding(model: model, start: IOSOnboarding.Step(rawValue: scenario.step ?? "") ?? .welcome)
        .task { await model.open() }
        .onDisappear { model.stop() }
    } else {
      tabs
    }
  }

  private var tabs: some View {
    TabView(selection: $tab) {
      if proposed {
        ForEach(IOSAppTab.proposedCases) { item in
          page(item).duckTabSurface().tabItem { item.proposedLabel }.tag(item)
        }
      } else {
        ForEach(IOSAppTab.allCases) { item in
          page(item).duckTabSurface().tabItem { item.label }.tag(item)
        }
      }
    }
    .environment(\.duckReservedSettingsContent, scenario.reservedSettingsContent)
    .background(DuckRole.background.ignoresSafeArea())
    .tint(DuckColors.action)
    .task { await model.open() }
    .onDisappear { model.stop() }
  }

  @ViewBuilder private func page(_ item: IOSAppTab) -> some View {
    switch item {
    case .receiver where "\(item)" == scenario.page: IOSReceiverPage(model: model)
    case .library where scenario.library != nil:
      IOSLibraryPage(library: library, model: model)
        .task {
          await library.open()
          if let view = scenario.libraryView { await library.changeBackupView(view) }
        }
        .onChange(of: model.pairing?.receiverID, initial: true) { _, receiver in library.backupReceiver = receiver }
    case .backup where "\(item)" == scenario.page:
      if proposed {
        // With a library scenario the hub opens the library's backup views (design/library.md).
        IOSHub(model: model, records: scenario.records, showLibrary: scenario.library == nil ? nil : { view in
          tab = .library
          Task { await library.changeBackupView(view) }
        })
      } else { IOSBackupPage(model: model) }
    case .settings where "\(item)" == scenario.page:
      if let scopeFixture {
        IOSScopeCatalog(fixture: scopeFixture)
      } else if proposed, let detail = scenario.step {
        // A settings sub-page opened directly, as if pushed from Settings.
        NavigationStack { IOSSettingsDetail(name: detail, model: model) }
      } else if proposed { IOSSettings(model: model, showBottom: ["settings.bottom", "settings.feedback", "settings.feedback-reserved"].contains(scenario.id))
          .environment(\.duckFeedbackPreview, ["settings.feedback", "settings.feedback-reserved"].contains(scenario.id)) } else { IOSSettingsPage(model: model) }
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
  @Binding var proposed: Bool
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
          Picker("Design", selection: $proposed) {
            Text("Current").tag(false)
            Text("Proposed").tag(true)
          }.pickerStyle(.segmented)
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

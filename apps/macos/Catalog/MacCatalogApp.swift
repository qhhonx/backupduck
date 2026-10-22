import AppKit
import ScreenCaptureKit
import SwiftUI

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
    BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.sampleThumbnail = SampleImages.image(for:)
    let scenario = MacCatalogLaunch.value("-scenario") ?? ""
    DesignPreview.proposedDesign = ProcessInfo.processInfo.arguments.contains("-proposed") || scenario.hasPrefix("folders.") || scenario.hasPrefix("settings.folder") || scenario.hasPrefix("settings.scope.") || scenario.hasPrefix("settings.updates") || scenario.hasPrefix("settings.about") || ["settings.bottom", "settings.feedback", "settings.feedback-reserved"].contains(scenario)
  }

  var body: some Scene {
    Window("Design catalog", id: "catalog") {
      MacCatalogRoot().frame(minWidth: 900, minHeight: 620)
    }.defaultSize(width: 1180, height: 800).commands {
      MacFolderCommands()
      CommandGroup(replacing: .appInfo) {
        Button("about_title") { MacAboutNavigation.open {} }
      }
    }
  }
}

/// What one scenario run owns. Created once per run, so restarting replays the
/// scenario with a new model.
@MainActor private final class MacScenarioSession: ObservableObject {
  let model: BackupModel
  let library = PhotoLibraryModel()
  let folders: FolderSources
  let scope: ScopeCatalogFixture?
  init(_ scenario: Scenario) {
    scope = scenario.id.hasPrefix("settings.scope.") ? ScopeCatalogFixture(id: scenario.id) : nil
    model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    let made = model
    BackupEnvironment.activeModel = { made }
    folders = FolderSources(backup: model)
    // Catalog folders never open configuration files, bookmarks, watchers or native indexes.
    folders.previewRows = []
    if scenario.id.hasPrefix("folders.") || scenario.id.hasPrefix("settings.folder") {
      FolderCatalog.install(scenario.id, folders: folders, sheet: MacCatalogLaunch.value("-sheet"))
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
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let path = MacCatalogLaunch.value("-snapshot") else { return }
    Task { @MainActor in
      do {
        // Direct executable launches can enter the run loop without an open-app
        // event, leaving SwiftUI with no window or root view task. Reopen this
        // running app through Launch Services; do not create another instance.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        let delay = max(0, Double(MacCatalogLaunch.value("-snapshot-delay") ?? "") ?? 9)
        try await Task.sleep(for: .seconds(delay))
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
            MacScenarioControls(scenario: open, scheme: $scheme, restart: restart, close: { self.open = nil })
              .padding(16)
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
      ForEach(["receiver", "settings", "backup", "library", "sources"], id: \.self) { page in
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
    if ["settings.bottom", "settings.about", "settings.feedback", "settings.about-reserved", "settings.feedback-reserved"].contains(scenario.id) || scenario.id.hasPrefix("settings.updates.") {
      DesignPreview.proposedDesign = true
    }
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
  @State private var checkingUpdates = false

  init(scenario: Scenario) {
    self.scenario = scenario
    _session = StateObject(wrappedValue: MacScenarioSession(scenario))
  }

  var body: some View {
    Group {
      if scenario.step == "updates" {
        NavigationStack { MacAboutSettings(updateSection: MacUpdateSection(status: checkingUpdates ? .checking : .notChecked, canCheck: !checkingUpdates && !scenario.id.hasSuffix("unavailable"),
          automaticChecks: $automaticChecks, check: { checkingUpdates = true })) }
          .labeledContentStyle(DuckPreferenceRowStyle())
          .navigationTitle("about_title")
      } else if scenario.step == "statusMenu" || MacCatalogLaunch.value("-status-menu") == "items" {
        MacStatusMenuCatalog(model: session.model)
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
        initialSettingsPage: scenario.step == "about" ? .about : nil,
        scopeStore: session.scope?.store ?? .shared, albumsModel: session.scope?.albums ?? .shared,
        initialScopeDestination: session.scope?.destination, initialScopeSearch: session.scope?.search ?? "")
      }
    }
      .environment(\.duckReservedSettingsContent, scenario.reservedSettingsContent)
      .environment(\.duckFeedbackPreview, ["settings.feedback", "settings.feedback-reserved"].contains(scenario.id))
      .onDisappear { session.model.stop() }
  }
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
          UserDefaults.standard.set(true, forKey: "macPhotoViewerInfo")
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
      Button("Scenario…") { info = true }
        .popover(isPresented: $info, arrowEdge: .top) {
          MacScenarioInfo(scenario: scenario, scheme: $scheme, restart: restart).frame(width: 420, height: 520)
        }
      Button("Restart", action: restart)
      Button("Scenarios", action: close)
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
        Picker("Design", selection: Binding(get: { DesignPreview.proposedDesign }, set: { DesignPreview.proposedDesign = $0; restart() })) {
          Text("Current").tag(false)
          Text("Proposed").tag(true)
        }.pickerStyle(.segmented)
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
    guard let window = viewer ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.contentView != nil }) else {
      throw SnapshotError("The catalog window is not visible (\(NSApp.windows.count) windows).")
    }
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
    try MacCatalogApp.core.unscripted.joined(separator: "\n")
      .write(to: url.deletingPathExtension().appendingPathExtension("unscripted.txt"), atomically: true, encoding: .utf8)
  }

  private struct SnapshotError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }
}

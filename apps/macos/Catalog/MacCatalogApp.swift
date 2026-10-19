import AppKit
import SwiftUI

/// Mac design catalog: the production workspace window driven by scenario data
/// instead of the Rust core, the keychain and the network. It never ships; see
/// `apps/apple/Catalog/README.md`.
@main struct MacCatalogApp: App {
  static let core = ScenarioCore()
  static let credentials = ScenarioCredentials()

  init() {
    BackupEnvironment.core = Self.core
    BackupEnvironment.credentials = Self.credentials
    BackupEnvironment.discoversReceivers = false
    BackupEnvironment.usesPhotoLibrary = false
    BackupEnvironment.sampleThumbnail = SampleImages.image(for:)
    DesignPreview.proposedDesign = ProcessInfo.processInfo.arguments.contains("-proposed")
  }

  var body: some Scene {
    Window("Design catalog", id: "catalog") {
      MacCatalogRoot().frame(minWidth: 900, minHeight: 620)
    }.defaultSize(width: 1180, height: 800)
  }
}

/// What one scenario run owns. Created once per run, so restarting replays the
/// scenario with a new model.
@MainActor private final class MacScenarioSession: ObservableObject {
  let model: BackupModel
  let library = PhotoLibraryModel()
  let folders: FolderSources
  init(_ scenario: Scenario) {
    model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    let made = model
    BackupEnvironment.activeModel = { made }
    folders = FolderSources(backup: model)
  }
}

private struct MacCatalogRoot: View {
  @State private var scenarios: [Scenario] = []
  @State private var failure: String?
  @State private var open: Scenario?
  @State private var run: UUID?
  @State private var scheme: ColorScheme?

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
    .task { load() }
  }

  private var list: some View {
    List {
      if let failure { Text(failure).foregroundStyle(.red) }
      ForEach(["receiver", "settings", "backup", "library"], id: \.self) { page in
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

  private func start(_ scenario: Scenario) { open = scenario; run = UUID() }

  private func restart() {
    run = nil
    DispatchQueue.main.async { run = UUID() }
  }

  private func load() {
    do { scenarios = try Scenario.loadAll() } catch { failure = error.localizedDescription }
    // `-scenario <id>` opens one scenario; `-appearance dark|light` sets the
    // appearance; `-snapshot <path>` writes the window as PNG after it settles
    // and quits. These serve screenshot runs that need no screen recording.
    let arguments = ProcessInfo.processInfo.arguments
    func value(_ flag: String) -> String? {
      guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
      return arguments[index + 1]
    }
    if let id = value("-scenario"), let scenario = scenarios.first(where: { $0.id == id }) { start(scenario) }
    if let appearance = value("-appearance") { scheme = appearance == "dark" ? .dark : .light }
    if let path = value("-snapshot") {
      let delay = Double(value("-snapshot-delay") ?? "") ?? 9
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        MacWindowSnapshot.write(to: URL(fileURLWithPath: path))
        NSApp.terminate(nil)
      }
    }
  }
}

private struct MacScenarioRun: View {
  let scenario: Scenario
  @StateObject private var session: MacScenarioSession

  init(scenario: Scenario) {
    self.scenario = scenario
    _session = StateObject(wrappedValue: MacScenarioSession(scenario))
  }

  var body: some View {
    Group {
      if scenario.page == "connect" {
        // The connect sheet on its own, for review (design/mac-connect.md).
        MacConnectSheet(model: session.model).task { await session.model.open() }
      } else {
      MacWorkspace(model: session.model, library: session.library,
        // Records belong to the hub; the Mac lists them as their own sidebar position.
        initialDestination: scenario.records != nil ? .transfers : MacDestination(rawValue: scenario.page) ?? .settings,
        folderSources: session.folders, initialTransferFilter: scenario.records ?? "all")
      }
    }
      .onDisappear { session.model.stop() }
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

/// Renders the catalog window, title bar included, into a PNG.
enum MacWindowSnapshot {
  @MainActor static func write(to url: URL) {
    guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
      let view = window.contentView?.superview ?? window.contentView,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    // The unscripted list goes next to the image for the same run.
    try? MacCatalogApp.core.unscripted.joined(separator: "\n")
      .write(to: url.deletingPathExtension().appendingPathExtension("unscripted.txt"), atomically: true, encoding: .utf8)
  }
}

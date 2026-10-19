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
    DesignPreview.proposedLook = ProcessInfo.processInfo.arguments.contains("-look")
    BackupEnvironment.sampleThumbnail = SampleImages.image(for:)
    // The catalog never asks for photo access; scenarios behave as if it was granted.
    BackupEnvironment.requestPhotoAccess = { true }
    BackupEnvironment.libraryCount = { 12_384 }
  }

  var body: some Scene {
    WindowGroup { CatalogHome() }
  }
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
  @State private var proposed = ProcessInfo.processInfo.arguments.contains("-proposed")
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Group { if let run { ScenarioRun(scenario: scenario, proposed: proposed).id(run) } else { DuckColors.canvas.ignoresSafeArea() } }
      .preferredColorScheme(scheme)
      .transformEnvironment(\.dynamicTypeSize) { if let textSize { $0 = textSize } }
      .overlay(alignment: .bottomTrailing) {
        // Above the tab bar, clear of navigation bar items.
        Button { info = true } label: {
          Image(systemName: "info.circle.fill").font(.title2)
            .padding(10).background(.thinMaterial, in: Circle())
        }
        .padding(.trailing, 12).padding(.bottom, 96)
        .accessibilityLabel("Scenario")
        .accessibilityIdentifier("catalog.info")
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
  @StateObject private var library = PhotoLibraryModel()
  @State private var tab: IOSAppTab

  init(scenario: Scenario, proposed: Bool) {
    self.scenario = scenario
    self.proposed = proposed
    // Shared code (library menu, tile marks) reads the same switch as the Mac catalog.
    DesignPreview.proposedDesign = proposed
    _model = StateObject(wrappedValue: scenario.makeModel(core: CatalogApp.core, credentials: CatalogApp.credentials))
    let start = IOSAppTab.allCases.first { "\($0)" == scenario.page } ?? .settings
    // The proposed skeleton has no Receiver tab; its page opens from Settings.
    _tab = State(initialValue: proposed && !IOSAppTab.proposedCases.contains(start) ? .settings : start)
  }

  var body: some View {
    if scenario.page == "connect" {
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
    .background(DuckColors.canvas.ignoresSafeArea())
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
      if proposed { IOSSettings(model: model) } else { IOSSettingsPage(model: model) }
    default:
      ContentUnavailableView("Not in this scenario", systemImage: item.symbol,
        description: Text(scenario.id))
    }
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

import AppKit
import CoreImage.CIFilterBuiltins
import Darwin
import Photos
import SwiftUI

enum MacDestination: String, CaseIterable, Identifiable {
  case library, sources, backup, transfers, settings
  var id: String { rawValue }
  var title: String { ["library", "sources", "backup"].contains(rawValue) ? "mac_nav_" + rawValue : "nav_" + rawValue }
  var icon: String {
    switch self {
    case .library: "photo.on.rectangle"
    case .sources: "folder"
    case .backup: "arrow.triangle.2.circlepath"
    case .transfers: "arrow.up.arrow.down"
    case .settings: "gearshape"
    }
  }
}
private enum MacSidebarLocation: Hashable {
  case page(MacDestination), folder(String)
}

/// Each sidebar position owns its open detail independently of the active position.
@MainActor private final class MacRetainedViewer: Identifiable {
  let id = UUID()
  let location: MacSidebarLocation
  let request: MacViewerRequest
  let navigation = MacLibraryNavigation()
  init(location: MacSidebarLocation, request: MacViewerRequest) {
    self.location = location; self.request = request
  }
}

struct MacWorkspace: View {
  @ObservedObject var model: BackupModel
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject private var notifier = BackupEnvironment.activeNotifier()
  @StateObject private var notificationPhotos = BackupPhotoRouter()
  @State private var destination: MacDestination = .backup
  @AppStorage("macFoldersSidebarExpanded") private var foldersExpanded = true
  @State private var sidebarHovered = false
  private var initialSettingsPage: MacSettings.Page?
  private var initialDiagnosticsPage: String?
  private var openInitialSettingsDetail: ((DuckSettingsNavigator) -> Void)?
  private var settingsUpdateSection: MacUpdateSection?
  private var scopeStore: BackupScopeStore
  private var albumsModel: ScopeAlbumsModel
  private var initialScopeDestination: BackupScopeDestination?
  private var initialScopeSearch: String
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var toolbarWidth: CGFloat = 1180
  @ObservedObject private var gridSize = MacGridSize.shared
  @State private var pairSheet = false
  @StateObject private var backupAction = SelectionBackupAction()
  @StateObject private var gridToolbar = MacGridToolbarState()
  @StateObject private var folderToolbarActions = MacFolderToolbarActions()
  @State private var transferFilter = "all"
  @StateObject private var historyVisibleRange = MacVisibleRange()
  @StateObject private var folderVisibleRange = MacVisibleRange()
  @State private var historySelectionCount = 0
  @State private var historyCount = 0
  @State private var historyLoaded = false
  @State private var historyType: LibraryFilter = .all
  @State private var historySearch = ""
  @State private var historySearchExpanded = false
  @State private var historyFocus: HistoryPhoto?
  @State private var historyFocusRevision = 0
  @State private var librarySelecting = false
  @State private var previewAsset: PHAsset?
  @State private var reviewAssets: [PHAsset]?
  @State private var retainedViewers: [MacSidebarLocation: MacRetainedViewer] = [:]
  @State private var gridFrame = CGRect.zero
  /// A reference, so recording a pending flight never re-renders the page.
  @State private var flightMemo = MacFlightMemo()
  @StateObject private var libraryNavigation = MacLibraryNavigation()
  @StateObject private var folders: FolderSources
  @ObservedObject private var folderBrowser: FolderBrowser
  @MainActor init(model: BackupModel, library: PhotoLibraryModel, initialDestination: MacDestination = .backup, folderSources: FolderSources? = nil, initialTransferFilter: String = "all",
    initialSettingsPage: MacSettings.Page? = nil, scopeStore: BackupScopeStore? = nil,
    albumsModel: ScopeAlbumsModel? = nil, initialScopeDestination: BackupScopeDestination? = nil, initialScopeSearch: String = "", initialViewer: MacViewerRequest? = nil, initialViewerInfo: Bool = false, initialDiagnosticsPage: String? = nil, openInitialSettingsDetail: ((DuckSettingsNavigator) -> Void)? = nil, settingsUpdateSection: MacUpdateSection? = nil) {
    self.openInitialSettingsDetail = openInitialSettingsDetail; self.settingsUpdateSection = settingsUpdateSection
    self.initialDiagnosticsPage = initialDiagnosticsPage
    self.model = model
    if let initialViewer {
      let session = MacRetainedViewer(location: .page(initialDestination), request: initialViewer)
      if initialViewerInfo { session.navigation.setInformationPresented(true) }
      _retainedViewers = State(initialValue: [.page(initialDestination): session])
    }
    let navigation = MacLibraryNavigation()
    if initialViewerInfo { navigation.setInformationPresented(true) }
    _libraryNavigation = StateObject(wrappedValue: navigation)
    self.library = library
    self.initialSettingsPage = initialSettingsPage; self.scopeStore = scopeStore ?? .shared
    self.albumsModel = albumsModel ?? .shared; self.initialScopeDestination = initialScopeDestination
    self.initialScopeSearch = initialScopeSearch
    _destination = State(initialValue: initialDestination)
    _transferFilter = State(initialValue: initialTransferFilter)
    let resolvedFolders = folderSources ?? .shared
    _folders = StateObject(wrappedValue: resolvedFolders)
    _folderBrowser = ObservedObject(wrappedValue: resolvedFolders.browser)
  }
  // The body is split into parts so each type-checks on its own: as one
  // expression it exceeded the compiler's time limit on slower release builders.
  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      sidebar
    } detail: {
      detailContent
        // The visible capture range (or the selection count) lives in the window
        // subtitle, as in Photos, instead of a strip above the media.
        .modifier(MacLibraryWindowChrome(title: windowTitle, range: chromeRange, fixed: subtitleOverride, dateFormat: destination == .transfers ? "grid_updated_date" : nil, ownsWindow: destination != .settings))
        .background(MacToolbarWidth(width: $toolbarWidth))
        .toolbar { workspaceToolbar }
        .environment(\.macGridToolbarState, gridToolbar)
    }
    .background(MacInfoWindowAnchor(navigation: libraryNavigation))
    .focusedSceneValue(\.windowInfoCommands, MacGridInfoCommands(toggle: { libraryNavigation.toggleInformation() }))
    .environment(\.macViewerPresentation, presentExternal)
    .onChange(of: library.selection) { _, ids in if !ids.isEmpty { backupAction.selectionChanged() } }
    .confirmationDialog("selection_backup_repeat_title", isPresented: $backupAction.confirmingRepeat, titleVisibility: .visible) {
      Button("selection_backup_repeat_action") { Task { await backupAction.confirm(library: library, model: model) } }
      Button("cancel", role: .cancel) { backupAction.cancel() }
    } message: { Text("selection_backup_repeat_note") }
    .alert("selection_backup_failed_title", isPresented: Binding(get: { backupAction.error != nil }, set: { if !$0 { backupAction.error = nil } })) {
      Button("settings_done") { backupAction.error = nil }
    } message: { Text(backupAction.error ?? "") }
    .environment(\.macViewerHistory, { photo in
      // This changes sidebar location, not the source viewer's session.
      activeViewerNavigation.viewerFlight.suspendPresentation()
      retainedViewers.removeValue(forKey: .page(.transfers))
      transferFilter = "all"; historyType = .all; historySearch = ""
      historyFocus = photo; historyFocusRevision &+= 1; destination = .transfers
    })
    .focusedSceneValue(\.historyZoom, destination == .transfers && !hasViewer ? MacHistoryZoomActions(
      smaller: { gridSize.ordinaryColumns = min(9, MacLibraryDensity.step(gridSize.ordinaryColumns, by: 1)) },
      larger: { gridSize.ordinaryColumns = MacLibraryDensity.step(gridSize.ordinaryColumns, by: -1) },
      canShrink: gridSize.ordinaryColumns < 9, canGrow: gridSize.ordinaryColumns > 3) : nil)
    .focusedSceneValue(\.photoViewerCommands, hasViewer ? MacViewerCommands(back: closeViewer,
      info: { activeViewerNavigation.toggleInformation() }, share: { activeViewerNavigation.viewerShare?() }) : nil)
    // The accent reaches the system as its accent color: selection, switches and
    // the default button use it, while push buttons stay neutral as in System
    // Settings. A tint here would color every bordered button (platform-expression A1).
    .accentColor(DuckRole.accentFill)
    .background(DuckRole.background)
    .background(MacSheetInitialFocus())
    .navigationSplitViewStyle(.balanced)
    .toolbarBackground(.hidden, for: .windowToolbar)
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowTransfers"))) { _ in showTransfers("all") }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowFolders"))) { _ in
      UserDefaults.standard.removeObject(forKey: "macRequestedDestination")
      folders.selectedSourceID = nil; folderBrowser.scope = .all; destination = .sources; columnVisibility = .all
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowAbout"))) { _ in
      destination = .settings
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowSettings"))) { _ in
      UserDefaults.standard.removeObject(forKey: "macRequestedSettingsRoute")
      destination = .settings
    }
    .onAppear {
      if let route = UserDefaults.standard.string(forKey: "macRequestedSettingsRoute"), ["about", "settings"].contains(route) {
        destination = .settings
        // About is consumed by its detail; Settings has no further route.
        if route == "settings" { UserDefaults.standard.removeObject(forKey: "macRequestedSettingsRoute") }
      }
      if UserDefaults.standard.string(forKey: "macRequestedDestination") == "sources" {
        UserDefaults.standard.removeObject(forKey: "macRequestedDestination")
        destination = .sources
      }
    }
    .onChange(of: notifier.route, initial: true) { _, _ in consumeNotification() }
    .onChange(of: model.ready) { _, _ in consumeNotification() }
    .onChange(of: model.pairing?.receiverID) { _, _ in consumeNotification() }
    .onChange(of: model.autoBackup) { _, enabled in folders.followAutoBackup(enabled) }
    .onChange(of: sidebarLocation) { old, _ in
      retainedViewers[old]?.navigation.viewerFlight.suspendPresentation()
      if old == .page(.library) { libraryNavigation.viewerFlight.suspendPresentation() }
    }
    .onChange(of: folders.selectedSourceID) { _, _ in columnVisibility = .all }
    .onChange(of: folders.sources.map(\.id)) { _, ids in
      if folders.loaded || folders.isPreview, case .folder(let id) = folderBrowser.scope, !ids.contains(id) {
        folderBrowser.scope = .all
      }
    }
    .task { await model.open() }
    // FolderSources waits for model.ready itself; it need not wait for the
    // remaining background initialization after the model becomes usable.
    .task { await folders.open() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in folders.wake() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in folders.wake() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in folders.wake() }
    .sheet(isPresented: $pairSheet) {
      MacConnectSheet(model: model)
    }
    // Backup views of the library ask the core about the paired receiver.
    .onChange(of: model.pairing?.receiverID, initial: true) { _, receiver in library.backupReceiver = receiver }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(selection: sidebarSelection) {
        // design/navigation.md: photos, backup, settings. Devices open from Settings.
        Section("mac_section_photos") {
          sidebarRow(.library, title: "mac_nav_photo_library")
          DisclosureGroup(isExpanded: $foldersExpanded) {
            ForEach(folders.sources) { source in
              Label(folders.displayName(source), systemImage: "folder")
                .tag(MacSidebarLocation.folder(source.id))
                .accessibilityIdentifier("folders.sidebar." + source.id)
            }
          } label: {
            HStack {
              Label("mac_nav_sources", systemImage: "folder")
              Spacer(minLength: DuckSpacing.xSmall)
              if sidebarHovered {
                Button {
                  destination = .sources
                  folderToolbarActions.requestAdd()
                } label: { Label("folders_add", systemImage: "plus") }
                  .buttonStyle(.borderless).labelStyle(.iconOnly).help("folders_add")
                  .disabled(!model.ready || folders.loadFailed)
                  .accessibilityIdentifier("folders.sidebar.add")
              }
            }.accessibilityElement(children: .contain)
              .accessibilityIdentifier("folders.sidebar.root")
          }.tag(MacSidebarLocation.page(.sources))
        }
        Section("mac_section_backup") {
          sidebarRow(.backup, title: "mac_nav_overview")
          sidebarRow(.transfers, title: "records_title")
        }
        Section { sidebarRow(.settings) }
      }.listStyle(.sidebar)

    }.background(MacSidebarHover { sidebarHovered = $0 })
      .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 300)
  }
  private var sidebarSelection: Binding<MacSidebarLocation?> {
    Binding(get: {
      guard destination == .sources else { return .page(destination) }
      switch folderBrowser.scope {
      case .all: return .page(.sources)
      case .folder(let id): return .folder(id)
      }
    }, set: { selection in
      guard let selection, selection != sidebarLocation else { return }
      activeExternalViewer?.navigation.viewerFlight.suspendPresentation()
      if destination == .library { libraryNavigation.viewerFlight.suspendPresentation() }
      switch selection {
      case .page(let page):
        if page == .sources { folderBrowser.scope = .all }
        destination = page
      case .folder(let id):
        folderBrowser.scope = .folder(id); destination = .sources; foldersExpanded = true
      }
    })
  }
  private var detailContent: some View {
    VStack(spacing: 0) {
      // Keep the native collection alive when switching destinations. No loss
      // of its reuse pool, selection or scroll position on tab changes.
      ZStack(alignment: .topLeading) {
        libraryPage.opacity(destination == .library ? 1 : 0).allowsHitTesting(
          destination == .library
        ).accessibilityHidden(destination != .library)
        FolderSourcesPage(folders: folders, backup: model, active: destination == .sources, viewerOpen: hasViewer, visibleRange: folderVisibleRange, toolbarActions: folderToolbarActions, settings: { id in
            folders.initialSettingsFolder = id; destination = .settings
            NotificationCenter.default.post(name: Notification.Name("BackupDuckFolderSettings"), object: id)
          })
          .opacity(destination == .sources ? 1 : 0).allowsHitTesting(destination == .sources)
          .accessibilityHidden(destination != .sources)
        MacHub(model: model, folders: folders, pair: { pairSheet = true }, sources: { destination = .sources }, showTransfers: showTransfers)
          .opacity(destination == .backup ? 1 : 0).allowsHitTesting(destination == .backup)
          .accessibilityHidden(destination != .backup)
          .environment(\.macWorkspaceActive, destination == .backup)
        Group {
          BackupHistoryView(model: model, filter: transferFilter, initialFocus: historyFocus, initialFocusRevision: historyFocusRevision, columns: gridSize.ordinaryColumns, resize: { gridSize.ordinaryColumns = $0 }, mediaFilter: historyType, search: historySearch, clearFilters: { transferFilter = "all"; historyType = .all; historySearch = "" },
              active: destination == .transfers, visibleRange: historyVisibleRange, selectionChanged: { historySelectionCount = $0 }, scopeChanged: { _, count in historyCount = count; historyLoaded = true })
            .opacity(destination == .transfers ? 1 : 0).allowsHitTesting(destination == .transfers)
            .accessibilityHidden(destination != .transfers)
        }
        MacSettings(model: model, folders: folders, showFolders: { destination = .sources },
            initialPage: initialSettingsPage, scopeStore: scopeStore, albumsModel: albumsModel,
            initialScopeDestination: initialScopeDestination, initialScopeSearch: initialScopeSearch, initialDiagnosticsPage: initialDiagnosticsPage, openInitialDetail: openInitialSettingsDetail, updateSection: settingsUpdateSection)
          .opacity(destination == .settings ? 1 : 0).allowsHitTesting(destination == .settings)
          .accessibilityHidden(destination != .settings)
          .environment(\.macWorkspaceActive, destination == .settings)
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background {
        // Toolbar search belongs to the workspace, independently of the
        // retained history grid's visibility and compositing state.
        if destination == .transfers && !hasViewer &&
          (historyCount > 0 || transferFilter != "all" || historyType != .all || !historySearch.isEmpty) {
          MacToolbarSearch(text: $historySearch, presented: $historySearchExpanded)
        }
      }
    }
    .environment(\.macGridInformationEnabled, activeExternalViewer == nil)
    .allowsHitTesting(activeExternalViewer == nil)
    .accessibilityHidden(activeExternalViewer != nil)
    .overlay {
      ForEach(retainedViewers.values.sorted { $0.id.uuidString < $1.id.uuidString }) { session in
        externalViewerContent(session)
          .opacity(session.location == sidebarLocation ? 1 : 0)
          .allowsHitTesting(session.location == sidebarLocation)
          .accessibilityHidden(session.location != sidebarLocation)
          .environment(\.macWorkspaceActive, session.location == sidebarLocation)
      }
    }
  }
  private var sidebarLocation: MacSidebarLocation {
    if destination == .sources, case let .folder(id) = folderBrowser.scope { return .folder(id) }
    return .page(destination)
  }
  private var activeExternalViewer: MacRetainedViewer? { retainedViewers[sidebarLocation] }
  private var activeViewerNavigation: MacLibraryNavigation { activeExternalViewer?.navigation ?? libraryNavigation }
  private func externalViewerContent(_ session: MacRetainedViewer) -> some View {
    MacViewerFlightSurface(flight: session.navigation.viewerFlight) {
      switch session.request {
      case let .photo(asset, collection, recorded):
        if let asset {
          MacPhotoPreview(asset: asset, library: library, navigation: session.navigation, reviewAssets: collection, recorded: recorded) { _ in closeExternal(session, to: { nil }) }
            .id(asset.localIdentifier)
        } else if let recorded {
          MacRecordedPhotoPreview(photo: recorded, model: model, navigation: session.navigation, close: { closeExternal(session, to: { nil }) })
        }
      case let .history(photo, collection, media, returnTo):
        MacHistoryPreview(photo: photo, collection: collection, library: library, navigation: session.navigation,
          media: media, close: { id in
            media.selection = [id]
            returnTo(id)
            closeExternal(session, to: { media.navigation.coverFlight[.all]?(id) })
          })
      case let .folder(photo, context, sources, returnTo, navigation):
        FolderViewer(photo: photo, context: context, folders: sources, navigation: session.navigation, close: { current in
          sources.browser.selection = [current.id]
          returnTo?(current)
          closeExternal(session, to: { navigation?.coverFlight[.all]?(current.id) })
        })
      }
    }
  }
  private func presentExternal(_ request: MacViewerRequest) {
    let session = MacRetainedViewer(location: sidebarLocation, request: request)
    var source: MacCoverFlightSource?
    switch request {
    case let .history(photo, _, media, _):
      source = media.navigation.coverFlight[.all]?(photo.id)
      if let asset = media.assets[photo.source], let poster = MacDetailPosterCache.shared.memoryPoster(asset: asset) {
        source?.image = poster
      }
    case let .folder(photo, _, _, _, navigation): source = navigation?.coverFlight[.all]?(photo.id)
    case .photo: source = nil
    }
    session.navigation.viewerFlight.begin(source)
    retainedViewers[session.location] = session
  }
  private func closeExternal(_ session: MacRetainedViewer, to landing: @escaping () -> MacCoverFlightSource?) {
    session.navigation.viewerFlight.close(to: landing) {
      if retainedViewers[session.location]?.id == session.id { retainedViewers.removeValue(forKey: session.location) }
    }
  }
  private var hasViewer: Bool { activeExternalViewer != nil || (destination == .library && previewAsset != nil && libraryNavigation.viewerOpen) }
  private func closeViewer() {
    let navigation = activeViewerNavigation
    if let back = navigation.viewerBack { back() }
    else if let session = activeExternalViewer { retainedViewers.removeValue(forKey: session.location) }
    else if destination == .library, let asset = navigation.viewerCurrent?() { closeMedia(asset) }
  }
  private var windowTitle: String {
    if hasViewer { return "" }
    if destination == .transfers { return NSLocalizedString("records_title", comment: "") }
    if destination == .library { return NSLocalizedString("mac_nav_photo_library", comment: "") }
    if destination == .sources {
      switch folderBrowser.scope {
      case .all: return NSLocalizedString("mac_nav_sources", comment: "")
      case .folder(let id): return folders.sources.first(where: { $0.id == id }).map(folders.displayName) ?? NSLocalizedString("mac_nav_sources", comment: "")
      }
    }
    return NSLocalizedString(destination.title, comment: "")
  }
  private var chromeRange: MacVisibleRange {
    if destination == .sources { return folderBrowser.visibleRange }
    if destination == .transfers { return historyVisibleRange }
    return libraryNavigation.visibleRange
  }
  /// Selection replaces location; calendar covers own their period labels.
  private var subtitleOverride: String? {
    if hasViewer { return "" }
    switch destination {
    case .library:
      guard library.authorized, library.placeholder == nil else { return "" }
      if let selected = librarySubtitle { return selected }
      return libraryNavigation.level == .all && !MacLibraryDensity.isDense(gridSize.columns) ? nil : ""
    case .sources:
      if !folderBrowser.selection.isEmpty {
        return String(format: NSLocalizedString("library_selected_count", comment: ""), folderBrowser.selection.count)
      }
      return folders.loadFailed || folders.sources.isEmpty ? "" : nil
    case .transfers:
      if historySelectionCount > 0 {
        return String(format: NSLocalizedString("library_selected_count", comment: ""), historySelectionCount)
      }
      return historyCount > 0 || !historyLoaded ? nil : ""
    default: return ""
    }
  }
  private var historyHasBrowsing: Bool {
    historyCount > 0 || transferFilter != "all" || historyType != .all || !historySearch.isEmpty
  }
  @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
  if !hasViewer && (destination == .library && library.authorized || destination == .sources && !folders.loadFailed && !folders.sources.isEmpty || destination == .transfers && historyHasBrowsing) {
    MacLibraryScale(columns: Binding(get: { destination != .library ? gridSize.ordinaryColumns : gridSize.columns },
      set: { if destination != .library { gridSize.ordinaryColumns = $0 } else { gridSize.columns = $0 } }),
      enabled: destination != .library || libraryNavigation.level == .all,
      stops: destination != .library ? MacLibraryDensity.grid : MacLibraryDensity.columns)
    MacBrowsingToolbarGap()
  }
  if !hasViewer, destination == .library, library.authorized {
    ToolbarItem(id: "browser.viewMode", placement: .primaryAction) {
      if toolbarWidth < MacBrowsingToolbarMetrics.compactWidth {
        MacBrowserLevelMenu(selection: MacLibraryLevel.allCases.firstIndex(of: libraryNavigation.level) ?? 0,
          choose: { index in
            if MacLibraryLevel.allCases.indices.contains(index) { changeLibraryLevel(MacLibraryLevel.allCases[index]) }
          })
      } else {
        MacBrowserLevelControl(labels: MacLibraryLevel.allCases.map(\.title),
          selection: MacLibraryLevel.allCases.firstIndex(of: libraryNavigation.level) ?? 0,
          identifier: "library.view_mode", choose: { index in
            if MacLibraryLevel.allCases.indices.contains(index) { changeLibraryLevel(MacLibraryLevel.allCases[index]) }
          }).frame(width: MacBrowsingToolbarMetrics.periodWidth)
      }
    }
    MacBrowsingToolbarGap()
  }
  if hasViewer {
    MacViewerToolbar(navigation: activeViewerNavigation, back: closeViewer)
  } else if destination == .library, previewAsset == nil || !libraryNavigation.viewerOpen {
    ToolbarItemGroup(placement: .primaryAction) {
      Toggle(isOn: $libraryNavigation.originalAspect) { Image(systemName: "rectangle.arrowtriangle.2.inward") }
        .toggleStyle(.button).help("calendar_original_aspect")
        .accessibilityIdentifier("library.original_aspect")
        .disabled(!MacLibraryDensity.canChangeAspect(level: libraryNavigation.level, columns: gridSize.columns,
          hasPhotos: library.placeholder == nil && library.loaded > 0))
      if library.authorized {
      MacGridFilterMenu(shows: MacGridFilterMenu.backupViews, selected: library.backupView.rawValue,
        choose: { raw in if let view = LibraryBackupView(rawValue: raw) { Task { await library.changeBackupView(view) } } },
        type: Binding(get: { library.filter }, set: { value in Task { await library.changeFilter(value) } }), identifier: "library.filter")
      }
      MacGridInfoButton(state: gridToolbar)
      MacSelectionBackupControl(action: backupAction, count: library.selection.count,
        identifier: "library.backup_selected",
        submit: { Task { await backupAction.request(library: library, model: model) } })
    }
  }
  if !hasViewer && destination == .sources && !folders.loadFailed && !folders.sources.isEmpty {
    MacFolderToolbar(folders: folders, backup: model, browser: folderBrowser, actions: folderToolbarActions, information: gridToolbar)
  }
  if !hasViewer, destination == .transfers, historyHasBrowsing {
    ToolbarItemGroup(placement: .primaryAction) {
      MacGridFilterMenu(shows: [("all", "grid_filter_all", "photo.on.rectangle"),
        ("attention", "records_needs_you", "exclamationmark.circle")], selected: transferFilter,
        choose: { transferFilter = $0 }, type: $historyType, identifier: "history.filter")
      MacGridInfoButton(state: gridToolbar)
    }
  }
  if !hasViewer, destination == .backup, gridToolbar.hasSource {
    ToolbarItemGroup(placement: .primaryAction) { MacGridInfoButton(state: gridToolbar) }
  }
  }
  private func sidebarRow(_ item: MacDestination, title: String? = nil) -> some View {
    Label(LocalizedStringKey(title ?? item.title), systemImage: item.icon).tag(MacSidebarLocation.page(item))
  }
  private func consumeNotification() {
    guard model.ready, let route = notifier.route,
      notifier.takeRoute(receiver: model.pairing?.receiverID) != nil else { return }
    closeViewer()
    columnVisibility = .all
    switch route.destination {
    case .overview: destination = .backup
    case .needsYou: showTransfers("attention")
    case .photo:
      destination = .backup
      guard let source = route.source else { destination = .backup; return }
      Task {
        let data = try? await Bridge.call(["op": "source_job", "receiver_id": route.receiver, "source_id": source])
        guard model.pairing?.receiverID == route.receiver else { return }
        let job = data.flatMap { try? JSONDecoder().decode(BackupJob.self, from: $0) }
          ?? model.jobs.first(where: { $0.asset.source_id == source && $0.receiverID == route.receiver })
        guard let job, job.asset.source_id == source,
          job.receiverID == nil || job.receiverID == route.receiver else { destination = .backup; return }
        notificationPhotos.macPresent = presentExternal
        notificationPhotos.open(HistoryPhoto(job: job), collection: [HistoryPhoto(job: job)], frame: .zero)
      }
    }
  }
  private func showTransfers(_ filter: String) {
    historyFocus = nil
    transferFilter = filter
    destination = .transfers
  }
  private var libraryPage: some View {
    ZStack {
      VStack(alignment: .leading, spacing: 0) {
        if let placeholder = library.placeholder {
          MacLibraryPlaceholder(kind: placeholder,
            requestingAccess: library.requestingPermission,
            requestAccess: { Task { await library.open(requestPermission: true) } },
            clearFilter: { Task { await library.resetFilters() } })
        } else {
          ZStack {
            MacLibraryGrid(
              library: library, navigation: libraryNavigation,
              preparationRevision: "\(model.pendingImports)|\(model.importingSourceID ?? "")", queueRevision: model.queueRevision,
              receiverID: model.pairing?.receiverID, columns: gridSize.columns, selecting: true,
              active: destination == .library, sharesSize: true,
              preview: openMedia, enterSelection: { librarySelecting = true }, resize: { gridSize.columns = $0 })
              .environment(\.macGridInformationEnabled, previewAsset == nil && activeExternalViewer == nil)
              .onChange(of: gridSize.columns, initial: false) { _, value in MacLibraryDensity.remember(value) }
              .allowsHitTesting(libraryNavigation.level == .all && previewAsset == nil)
              .accessibilityHidden(libraryNavigation.level != .all || previewAsset != nil)
            ForEach([MacLibraryLevel.months, .years]) { level in
              do {
                Group {
                  if libraryNavigation.indexing && libraryNavigation.years.isEmpty {
                    DuckLoadingState("library_loading")
                  } else {
                    MacCalendarGrid(library: library, navigation: libraryNavigation, kind: level)
                  }
                }
                .allowsHitTesting(libraryNavigation.level == level && previewAsset == nil)
                .accessibilityHidden(libraryNavigation.level != level)
              }
            }
          }
          .background(GeometryReader { proxy in
            Color.clear.onAppear { gridFrame = proxy.frame(in: .named("libraryPage")) }
              .onChange(of: proxy.frame(in: .named("libraryPage"))) { _, frame in gridFrame = frame }
          })
        }
      }.allowsHitTesting(previewAsset == nil).accessibilityHidden(previewAsset != nil)
      if let previewAsset {
        MacViewerFlightSurface(flight: libraryNavigation.viewerFlight) {
          MacPhotoPreview(asset: previewAsset, library: library, navigation: libraryNavigation,
            reviewAssets: reviewAssets, close: closeMedia)
            .id(previewAsset.localIdentifier)
        }
        .zIndex(1)
      }
    }
    .environment(\.macWorkspaceActive, destination == .library)
    .coordinateSpace(name: "libraryPage")
    .onChange(of: library.generation, initial: true) { _, _ in libraryNavigation.rebuild(library.fetch) }
    .onChange(of: libraryNavigation.level) { old, next in
      startFlight(from: old, to: next)
    }
  }
  /// The selection count, or nil for the visible range.
  private var librarySubtitle: String? {
    guard !library.selection.isEmpty else { return nil }
    return String(format: NSLocalizedString("library_selected_count", comment: ""), library.selection.count)
  }
  /// Every level change keeps one focus photo. It flies from where it was to
  /// where it lands; when the destination shows another photo for that period,
  /// the two cross-fade on the way.
  private func startFlight(from old: MacLibraryLevel, to next: MacLibraryLevel) {
    if flightMemo.suppressNextLevelFlight {
      flightMemo.suppressNextLevelFlight = false; flightMemo.pending = nil; return
    }
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, destination == .library,
      let token = libraryNavigation.focusToken,
      let source = flightMemo.pending.flatMap({ $0.level == old && $0.token == token ? $0.source : nil })
        ?? libraryNavigation.coverFlight[old]?(token) else { flightMemo.pending = nil; return }
    flightMemo.pending = nil
    libraryNavigation.presentFocus[next]?(source.assetID, source.image)
    func land(_ attempt: Int) {
      guard libraryNavigation.level == next else { return }
      let landing = { [libraryNavigation] in libraryNavigation.coverLanding[next]?(token, source.assetID) }
      guard landing() != nil else {
        // All Photos places its focus cell after a reload; give it a few frames.
        if attempt < 8 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { land(attempt + 1) } }
        return
      }
      MacCoverFlight.fly(from: source, to: landing)
    }
    land(0)
  }
  private func changeLibraryLevel(_ next: MacLibraryLevel) {
    flightMemo.pending = nil
    flightMemo.suppressNextLevelFlight = libraryNavigation.level != next
    libraryNavigation.selectLevel(next)
  }
  /// The viewer opens as Photos does: the photo grows from its cell to its
  /// fitted rectangle while the background fades in, then the live media takes
  /// over underneath at the same pixels.
  private func present(_ asset: PHAsset) {
    let token = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
    var source = libraryNavigation.coverLanding[.all]?(token, asset.localIdentifier)
    if let poster = MacDetailPosterCache.shared.memoryPoster(asset: asset) { source?.image = poster }
    libraryNavigation.viewerFlight.begin(source)
    previewAsset = asset; libraryNavigation.viewerOpen = true
  }
  private func openMedia(_ asset: PHAsset) { present(asset) }
  private func closeMedia(_ asset: PHAsset) {
    let token = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
    libraryNavigation.viewerOpen = false
    Task {
      if library.index(of: token) == nil { _ = await library.preparePreviewWindow(containing: token) }
      library.selection = [token]
      libraryNavigation.focus(token)
      libraryNavigation.viewerFlight.close(to: {
        libraryNavigation.coverLanding[.all]?(token, asset.localIdentifier)
      }) {
        previewAsset = nil; reviewAssets = nil
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

/// The viewer grows from its grid cell and returns to it, as Photos does. A
/// cell that is not visible (or Reduce Motion) falls back to a plain fade.

@MainActor final class MacFlightMemo {
  var suppressNextLevelFlight = false
  var pending: (level: MacLibraryLevel, token: String, source: MacCoverFlightSource)?
}

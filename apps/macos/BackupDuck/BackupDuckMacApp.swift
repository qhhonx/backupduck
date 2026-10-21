import AppKit
import CoreImage.CIFilterBuiltins
import Darwin
import Photos
import SwiftUI

enum MacDestination: String, CaseIterable, Identifiable {
  case library, sources, backup, transfers, receiver, settings
  var id: String { rawValue }
  var title: String { ["library", "sources", "backup"].contains(rawValue) ? "mac_nav_" + rawValue : "nav_" + rawValue }
  var icon: String {
    switch self {
    case .library: "photo.on.rectangle"
    case .sources: "folder"
    case .backup: "arrow.triangle.2.circlepath"
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
  @State private var density = MacLibraryDensity.remembered
  @State private var pairSheet = false
  @State private var selectedPhotoDetails: PHAsset?
  @State private var confirmSelectedBackup = false
  @State private var rebackupReceivedSelection = false
  @State private var transferFilter = "all"
  @State private var settingsTitle = "nav_settings"
  @State private var librarySelecting = false
  @State private var previewAsset: PHAsset?
  @State private var reviewAssets: [PHAsset]?
  @State private var previewExpanded = false
  @State private var gridFrame = CGRect.zero
  @State private var previewMediaVisible = false
  /// A reference, so recording a pending flight never re-renders the page.
  @State private var flightMemo = MacFlightMemo()
  @StateObject private var libraryNavigation = MacLibraryNavigation()
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
  // The body is split into parts so each type-checks on its own: as one
  // expression it exceeded the compiler's time limit on slower release builders.
  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      sidebar
    } detail: {
      detailContent
        .navigationTitle(windowTitle)
        // The visible capture range (or the selection count) lives in the window
        // subtitle, as in Photos, instead of a strip above the media.
        .background(MacLibrarySubtitle(range: libraryNavigation.visibleRange, fixed: subtitleOverride))
        .toolbar { workspaceToolbar }
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
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckShowSettings"))) { _ in
      UserDefaults.standard.removeObject(forKey: "macRequestedSettingsRoute")
      destination = .settings
    }
    .onAppear {
      if ["about", "settings"].contains(UserDefaults.standard.string(forKey: "macRequestedSettingsRoute")) { destination = .settings }
      if UserDefaults.standard.string(forKey: "macRequestedDestination") == "sources" {
        UserDefaults.standard.removeObject(forKey: "macRequestedDestination")
        destination = .sources
      }
    }
    .onChange(of: model.autoBackup) { _, enabled in folders.followAutoBackup(enabled) }
    .onChange(of: folders.selectedSourceID) { _, _ in columnVisibility = .all }
    .task { await model.open(); await folders.open() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in folders.wake() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in folders.wake() }
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in folders.wake() }
    .sheet(isPresented: $pairSheet) {
      if DesignPreview.proposedDesign { MacConnectSheet(model: model) } else { MacPairingSheet(model: model) }
    }
    // Backup views of the library ask the core about the paired receiver.
    .onChange(of: model.pairing?.receiverID, initial: true) { _, receiver in library.backupReceiver = receiver }
    .sheet(isPresented: $confirmSelectedBackup) { selectedBackupConfirmation }
    .sheet(isPresented: Binding(get: { selectedPhotoDetails != nil }, set: { if !$0 { selectedPhotoDetails = nil } })) {
      if let selectedPhotoDetails { DuckPhotoDetail(asset: selectedPhotoDetails) }
    }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(selection: $destination) {
        if DesignPreview.proposedDesign {
          // design/navigation.md: photos, backup, settings. Devices open from Settings.
          Section("mac_section_photos") {
            sidebarRow(.library, title: "mac_nav_photo_library")
            sidebarRow(.sources)
          }
          Section("mac_section_backup") {
            sidebarRow(.backup, title: "mac_nav_overview")
            sidebarRow(.transfers, title: "records_title")
          }
          Section { sidebarRow(.settings) }
        } else {
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
        }
      }.listStyle(.sidebar)

    }.navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 300)
  }
  private var detailContent: some View {
    VStack(spacing: 0) {
      // Keep the native collection alive when switching destinations. No loss
      // of its reuse pool, selection or scroll position on tab changes.
      ZStack(alignment: .topLeading) {
        libraryPage.opacity(destination == .library ? 1 : 0).allowsHitTesting(
          destination == .library
        ).accessibilityHidden(destination != .library)
        if destination == .sources {
          FolderSourcesPage(folders: folders, backup: model, settings: { id in
            folders.initialSettingsFolder = id; destination = .settings
            NotificationCenter.default.post(name: Notification.Name("BackupDuckFolderSettings"), object: id)
          })
        }
        if destination == .backup && DesignPreview.proposedDesign {
          MacHub(model: model, folders: folders, pair: { pairSheet = true }, sources: { destination = .sources }, showTransfers: showTransfers)
        } else if destination == .backup {
          MacBackupPage(model: model, folders: folders, pair: { pairSheet = true },
            library: { destination = .library }, sources: { destination = .sources }, receiver: { destination = .receiver }, showTransfers: showTransfers)
        }
        if destination == .transfers && DesignPreview.proposedDesign {
          BackupHistoryView(model: model)
        } else if destination == .transfers {
          MacTransferPage(model: model, filter: transferFilter, sourceOptions: [("library", NSLocalizedString("source_system_library", comment: ""))] + folders.sources.map { ($0.id, folders.displayName($0)) }).id(transferFilter).padding(28)
        }
        if destination == .settings {
          if DesignPreview.proposedDesign {
            MacSettings(model: model, folders: folders, showFolders: { destination = .sources })
          } else {
            MacPreferences(model: model, folders: folders, showFolders: { destination = .sources }, titleChanged: { settingsTitle = $0 }, initialRoute: initialSettingsRoute)
          }
        }
        if destination == .receiver {
          ScrollView { ReceiverPage(model: model, pair: { pairSheet = true }).padding(28) }
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      // The proposed hub states the backup once; the status footer would repeat it.
      if destination != .settings && destination != .receiver && destination != .library && destination != .sources
        && !([.backup, .transfers].contains(destination) && DesignPreview.proposedDesign) {
        Divider()
        footer.padding(.horizontal, 24).padding(.vertical, 12).background(DuckColors.surface)
          .task(id: "\(model.queueRevision)|\(model.pairing?.receiverID ?? "")") {
            if model.ready, let receiver = model.pairing?.receiverID {
              await activeTransfers.refresh(filter: "running", receiver: receiver)
            }
          }
      }
    }
  }
  private var windowTitle: Text {
    if destination == .library && previewAsset != nil && libraryNavigation.viewerOpen { return Text(verbatim: "") }
    if destination == .transfers && DesignPreview.proposedDesign { return Text("records_title") }
    if destination == .library && DesignPreview.proposedDesign { return Text("mac_nav_photo_library") }
    return Text(LocalizedStringKey(destination == .settings ? settingsTitle : (destination ?? .library).title))
  }
  /// A subtitle replacing the visible range: empty outside the library and in
  /// the viewer, the selection count while photos are selected.
  private var subtitleOverride: String? {
    guard destination == .library && library.authorized else { return "" }
    if previewAsset != nil && libraryNavigation.viewerOpen { return "" }
    return librarySubtitle
  }
  @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
  // The open viewer uses the window toolbar instead of a second bar in
  // the content: back, then information and Live playback.
  if destination == .library, previewAsset != nil, libraryNavigation.viewerOpen {
    ToolbarItem(placement: .navigation) {
      Button { if let asset = libraryNavigation.viewerCurrent?() { closeMedia(asset) } } label: {
        Label("mac_library_back", systemImage: "chevron.backward")
      }.keyboardShortcut(.cancelAction).help(Text("mac_library_back"))
        .accessibilityIdentifier("library.preview.close")
    }
    // The title is centred, as in Photos: the date, then time and position.
    // Plain text, not a control: no shared glass background behind it.
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
      ToolbarItem(placement: .principal) { viewerTitle }.sharedBackgroundVisibility(.hidden)
    } else {
      ToolbarItem(placement: .principal) { viewerTitle }
    }
    #else
    // Xcode 16's SDK cannot resolve this modifier, even behind #available.
    ToolbarItem(placement: .principal) { viewerTitle }
    #endif
    // Live playback lives on the photo's own badge; no second control here.
    ToolbarItemGroup(placement: .primaryAction) {
      Toggle(isOn: Binding(get: { libraryNavigation.viewerInfo }, set: { value in
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { libraryNavigation.viewerInfo = value }
      })) { Label("apple_photo_detail", systemImage: "info.circle") }
        .toggleStyle(.button).keyboardShortcut("i", modifiers: .command)
        .help(Text("apple_photo_detail")).accessibilityIdentifier("library.preview.info")
    }
  }
  if destination == .library, previewAsset == nil || !libraryNavigation.viewerOpen, library.authorized {
    ToolbarItem(placement: .principal) {
      Picker("library_view_mode", selection: Binding(get: { libraryNavigation.level },set: changeLibraryLevel)) {
        ForEach(MacLibraryLevel.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
      }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
        .accessibilityIdentifier("library.view_mode")
        // Choosing All again returns to the newest photo, as in Photos.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
          if libraryNavigation.level == .all { libraryNavigation.scrollToNewest() }
        })
    }
    ToolbarItemGroup(placement: .primaryAction) {
      if !library.selection.isEmpty {
        // Always reachable while photos are selected: without a receiver it
        // opens pairing first and the selection stays as it is.
        Button {
          if model.pairing == nil { pairSheet = true; return }
          rebackupReceivedSelection = false; confirmSelectedBackup = true
        } label: {
          Label("apple_library_backup_selected", systemImage: "arrow.up.doc")
        }.disabled(model.importing)
          .help(Text(LocalizedStringKey(model.pairing == nil ? "pair_receiver_desktop" : "apple_library_backup_selected")))
          .accessibilityIdentifier("library.backup_selected")
      }
      // Kept in place and disabled outside All Photos: inserting and
      // removing toolbar items relaid the toolbar during each level change.
      Group {
        MacLibraryScale(columns: $density)
        Toggle(isOn: $libraryNavigation.originalAspect) { Image(systemName: "rectangle.arrowtriangle.2.inward") }
          .toggleStyle(.button).help("calendar_original_aspect")
          .accessibilityIdentifier("library.original_aspect")
      }.disabled(libraryNavigation.level != .all)
      // One flat menu, as in Photos: everything, then each media type, with
      // a check on the current one. No nested submenu, no menu chevron.
      Menu {
        // design/library.md: backup views of the same grid (proposed design only).
        if DesignPreview.proposedDesign {
          Picker("library_view_section", selection: Binding(get: { library.backupView }, set: { value in
            Task { await library.changeBackupView(value) }
          })) {
            ForEach(LibraryBackupView.allCases) { view in
              Label(LocalizedStringKey(view.title), systemImage: view.symbol).tag(view)
            }
          }.pickerStyle(.inline)
          Divider()
        }
        // An inline picker keeps each item's icon next to the check mark.
        Picker("media_type", selection: Binding(get: { library.filter }, set: { value in
          Task { await library.changeFilter(value) }
        })) {
          ForEach(LibraryFilter.allCases) { filter in
            Label(LocalizedStringKey(filter.title), systemImage: filter.symbol).tag(filter)
            if filter == .all { Divider() }
          }
        }.pickerStyle(.inline).labelsHidden()
      } label: { Label("library_filter", systemImage: library.filter == .all && library.backupView == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") }
        .menuIndicator(.hidden)
        .help(Text(LocalizedStringKey(library.filter.title))).accessibilityIdentifier("library.filter")
    }
  }
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
  private func sidebarRow(_ item: MacDestination, title: String? = nil) -> some View {
    Label(LocalizedStringKey(title ?? item.title), systemImage: item.icon).tag(item)
  }
  private func showTransfers(_ filter: String) {
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
            clearFilter: { Task { await library.changeFilter(.all) } })
        } else {
          ZStack {
            MacLibraryGrid(
              library: library, navigation: libraryNavigation,
              preparationRevision: "\(model.pendingImports)|\(model.importingSourceID ?? "")", queueRevision: model.queueRevision,
              receiverID: model.pairing?.receiverID, columns: density, selecting: true,
              active: destination == .library,
              preview: openMedia, enterSelection: { librarySelecting = true }, resize: { density = $0 })
              .onChange(of: density, initial: false) { _, value in MacLibraryDensity.remember(value) }
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
        GeometryReader { proxy in
          ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(previewExpanded ? 1 : 0)
            // The media appears once the opening flight has landed on it, and
            // vanishes before the closing flight leaves it.
            MacPhotoPreview(asset: previewAsset, library: library, navigation: libraryNavigation,
              reviewAssets: reviewAssets, close: closeMedia)
              .id(previewAsset.localIdentifier)
              .opacity(previewMediaVisible ? 1 : 0)
          }
          .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil
            : .easeOut(duration: 0.28), value: previewExpanded)
        }
        .zIndex(1)
      }
    }
    .coordinateSpace(name: "libraryPage")
    .onChange(of: library.generation, initial: true) { _, _ in libraryNavigation.rebuild(library.fetch) }
    .onChange(of: libraryNavigation.level) { old, next in
      startFlight(from: old, to: next)
    }
    .onChange(of: destination) { _, next in
      if next != .library { previewAsset = nil; reviewAssets = nil }
    }
  }
  private var viewerTitle: some View {
    VStack(spacing: 1) {
      Text(libraryNavigation.viewerTitle).font(.headline).lineLimit(1)
      Text(libraryNavigation.viewerSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }.fixedSize().accessibilityElement(children: .combine).accessibilityIdentifier("library.preview.title")
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
    guard next != libraryNavigation.level else { return }
    // The focus is decided before the switch: the selection, or the photo
    // nearest the centre of what is on screen now.
    if let focus = libraryNavigation.focusCandidate[libraryNavigation.level]?() { libraryNavigation.focusToken = focus }
    // Capture where the focus is now: All Photos may load before switching,
    // and a year card can rotate to another photo in the meantime.
    if let token = libraryNavigation.focusToken, let source = libraryNavigation.coverFlight[libraryNavigation.level]?(token) {
      flightMemo.pending = (libraryNavigation.level, token, source)
    }
    if next != .all { libraryNavigation.level = next; return }
    guard let token = libraryNavigation.focusToken else { libraryNavigation.level = next; return }
    let previous = libraryNavigation.level
    Task {
      guard await library.preparePreviewWindow(containing: token) != nil,
        libraryNavigation.level == previous, libraryNavigation.focusToken == token else { return }
      libraryNavigation.focus(token); libraryNavigation.level = next
    }
  }
  /// The viewer opens as Photos does: the photo grows from its cell to its
  /// fitted rectangle while the background fades in, then the live media takes
  /// over underneath at the same pixels.
  private func present(_ asset: PHAsset) {
    let token = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
    let source = libraryNavigation.coverLanding[.all]?(token, asset.localIdentifier)
    let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      previewExpanded = false; previewAsset = asset; libraryNavigation.viewerOpen = true
      previewMediaVisible = reduce || source == nil
    }
    DispatchQueue.main.async {
      previewExpanded = true
      guard !reduce, let source else { previewMediaVisible = true; return }
      MacCoverFlight.fly(from: source, to: { viewerTarget(asset, image: source.image, clip: source.clip) })
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { previewMediaVisible = true }
    }
  }
  /// The fitted rectangle of `asset` inside the viewer's media area.
  private func viewerTarget(_ asset: PHAsset, image: NSImage?, clip: CGRect) -> MacCoverFlightSource? {
    guard let area = libraryNavigation.viewerArea?(), asset.pixelWidth > 0, asset.pixelHeight > 0 else { return nil }
    let aspect = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    var size = CGSize(width: area.width, height: area.width / aspect)
    if size.height > area.height { size = CGSize(width: area.height * aspect, height: area.height) }
    let rect = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    return MacCoverFlightSource(rect: rect, image: image, radius: 0, assetID: asset.localIdentifier,
      clip: area, window: NSApp.keyWindow)
  }
  private func openMedia(_ asset: PHAsset) {
    MacPhotoViewerWindow.open(asset: asset, library: library)
  }
  private func closeMedia(_ asset: PHAsset) {
    let token = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
    let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let start = reduce ? nil : viewerTarget(asset, image: library.thumbnails.poster(for: asset), clip: .zero)
    libraryNavigation.viewerImmersive = false
    libraryNavigation.viewerOpen = false
    previewMediaVisible = false
    previewExpanded = false
    // Paging can reach photos far beyond the rows the grid has loaded: load the
    // window around the photo, then bring its cell on screen and land on it.
    Task {
      if library.index(of: token) == nil { _ = await library.preparePreviewWindow(containing: token) }
      libraryNavigation.focus(token)
      guard var start else { return }
      DispatchQueue.main.async {
        if let cell = libraryNavigation.coverLanding[.all]?(token, asset.localIdentifier) {
          start.clip = cell.clip
          MacCoverFlight.fly(from: start, to: { libraryNavigation.coverLanding[.all]?(token, asset.localIdentifier) })
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0 : 0.3)) {
      guard !previewExpanded else { return }
      previewAsset = nil; reviewAssets = nil
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
  private var aggregate: (key: String, symbol: String, color: Color) { backupAggregateStatus(model) }
  private var title: String { aggregate.key }
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: aggregate.symbol)
        .font(.system(size: 20)).foregroundStyle(aggregate.color)
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

/// The viewer grows from its grid cell and returns to it, as Photos does. A
/// cell that is not visible (or Reduce Motion) falls back to a plain fade.

@MainActor final class MacFlightMemo {
  var pending: (level: MacLibraryLevel, token: String, source: MacCoverFlightSource)?
}

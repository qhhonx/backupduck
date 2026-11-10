import AppKit
import Photos
import SwiftUI

/// One album's photos in the Mac library grid, read-only, inside the backup
/// settings sheet. Its own scoped model keeps the main library's fetch,
/// selection and scroll untouched; browsing registers no work.
struct MacScopeAlbumBrowser: View {
  let album: ScopeAlbum
  @StateObject private var library: PhotoLibraryModel
  @StateObject private var navigation = MacLibraryNavigation()
  @StateObject private var gridToolbar = MacGridToolbarState()
  @ObservedObject private var store: BackupScopeStore
  @ObservedObject private var model = BackupModel.shared
  @Environment(\.macWorkspaceActive) private var active
  @ObservedObject private var gridSize = MacGridSize.shared
  @State private var previewAsset: PHAsset?
  @MainActor init(album: ScopeAlbum, store: BackupScopeStore? = nil, library: PhotoLibraryModel? = nil) {
    self.album = album
    self.store = store ?? .shared
    _library = StateObject(wrappedValue: library ?? PhotoLibraryModel(collection: album.id))
  }
  var body: some View {
    content.environment(\.macGridInformationEnabled, previewAsset == nil)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .allowsHitTesting(previewAsset == nil).accessibilityHidden(previewAsset != nil)
      .overlay {
        if let previewAsset {
          MacViewerFlightSurface(flight: navigation.viewerFlight) {
            MacPhotoPreview(asset: previewAsset, library: library, navigation: navigation, close: close)
              .id(previewAsset.localIdentifier)
          }
        }
      }
      .navigationTitle(previewAsset == nil ? album.name : "")
      .preference(key: MacSettingsMediaViewerKey.self, value: previewAsset != nil)
      .focusedSceneValue(\.photoViewerCommands, active && previewAsset != nil ? MacViewerCommands(
        back: { navigation.viewerBack?() }, info: { navigation.toggleInformation() },
        share: { navigation.viewerShare?() }) : nil)
      .toolbar {
        if active, previewAsset != nil {
          MacViewerToolbar(navigation: navigation, back: { navigation.viewerBack?() })
        } else if active {
        MacLibraryScale(columns: $gridSize.ordinaryColumns, stops: MacLibraryDensity.grid)
        MacBrowsingToolbarGap()
        ToolbarItemGroup(placement: .primaryAction) { MacGridInfoButton(state: gridToolbar) }
        MacBrowsingToolbarGap()
        ToolbarItem(id: "settings.album.selection", placement: .primaryAction) {
          Toggle(isOn: Binding(get: { store.rule.choosesAlbum(album.id) }, set: { included in
            guard included != store.rule.choosesAlbum(album.id) else { return }
            store.save(store.rule.toggling(album: album.id, name: album.name))
          })) {
            Text(store.rule.choosesAlbum(album.id) ? "scope_album_deselect" : "scope_album_choose")
          }
          .toggleStyle(.button)
          .accessibilityIdentifier("backup.scope.album_browser.choose")
        }
        }
      }
      .environment(\.macGridToolbarState, gridToolbar)
      .task {
        if BackupEnvironment.usesPhotoLibrary { await library.open() }
        else if library.loaded == 0 { library.applyAuthorization(.denied) }
      }
      .onChange(of: active) { _, active in
        if !active { navigation.viewerFlight.suspendPresentation() }
      }
      .onDisappear { library.thumbnails.clear() }
  }
  private func open(_ asset: PHAsset) {
    let token = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
    var source = navigation.coverLanding[.all]?(token, asset.localIdentifier)
    if let poster = MacDetailPosterCache.shared.memoryPoster(asset: asset) { source?.image = poster }
    navigation.viewerFlight.begin(source)
    previewAsset = asset; navigation.viewerOpen = true
  }
  private func close(_ asset: PHAsset) {
    navigation.viewerOpen = false
    let token = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
    library.selection = [token]
    navigation.focus(token)
    navigation.viewerFlight.close(to: { navigation.coverLanding[.all]?(token, asset.localIdentifier) }) {
      previewAsset = nil
    }
  }
  @ViewBuilder private var content: some View {
    switch library.placeholder {
    case .loading?: DuckLoadingState("library_loading")
    case .empty?:
      Text("scope_album_no_photos").foregroundStyle(DuckRole.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("backup.scope.album_browser.empty")
    case let placeholder?:
      MacLibraryPlaceholder(kind: placeholder, requestingAccess: library.requestingPermission,
        requestAccess: {
          guard BackupEnvironment.usesPhotoLibrary else { return }
          Task { await library.open(requestPermission: true) }
        }, clearFilter: {})
    case nil:
      // The sheet's first pass proposes a near-zero width; a grid laid out then
      // showed one frame of 1 pt cells. Mount it once the page has its width.
      GeometryReader { proxy in
        if proxy.size.width > 120 {
          MacLibraryGrid(library: library, navigation: navigation,
            preparationRevision: "\(model.pendingImports)|\(model.importingSourceID ?? "")",
            queueRevision: model.queueRevision, receiverID: model.pairing?.receiverID,
            columns: gridSize.ordinaryColumns, selecting: true, readOnly: false, active: active, sharesSize: true, ordinaryOnly: true, prefillsTables: false, preview: open, resize: { gridSize.ordinaryColumns = $0 })
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityIdentifier("backup.scope.album_browser")
        }
      }
    }
  }
}

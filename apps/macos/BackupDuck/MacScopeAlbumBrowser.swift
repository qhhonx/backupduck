import Photos
import SwiftUI

/// One album's photos in the Mac library grid, read-only, inside the backup
/// settings sheet. Its own scoped model keeps the main library's fetch,
/// selection and scroll untouched; browsing registers no work.
struct MacScopeAlbumBrowser: View {
  let album: ScopeAlbum
  @StateObject private var library: PhotoLibraryModel
  @StateObject private var navigation = MacLibraryNavigation()
  @ObservedObject private var store: BackupScopeStore
  @ObservedObject private var model = BackupModel.shared
  @State private var columns = MacLibraryDensity.standard
  @MainActor init(album: ScopeAlbum, store: BackupScopeStore? = nil) {
    self.album = album
    self.store = store ?? .shared
    _library = StateObject(wrappedValue: PhotoLibraryModel(collection: album.id))
  }
  var body: some View {
    content.frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(album.name)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          let chosen = store.rule.choosesAlbum(album.id)
          Button(chosen ? "scope_album_deselect" : "scope_album_choose") {
            store.save(store.rule.toggling(album: album.id, name: album.name))
          }.accessibilityIdentifier("backup.scope.album_browser.choose")
        }
      }
      .task {
        if BackupEnvironment.usesPhotoLibrary { await library.open() }
        else { library.applyAuthorization(.denied) }
      }
      .onDisappear { library.thumbnails.clear() }
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
            columns: columns, selecting: false, prefillsTables: false, resize: { columns = $0 })
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityIdentifier("backup.scope.album_browser")
        }
      }
    }
  }
}

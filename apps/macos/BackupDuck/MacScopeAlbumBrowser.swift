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
  @ObservedObject private var store: BackupScopeStore
  @ObservedObject private var model = BackupModel.shared
  @State private var columns = MacLibraryDensity.standard
  @State private var previewAsset: PHAsset?
  @State private var mediaVisible = false
  @State private var expanded = false
  @MainActor init(album: ScopeAlbum, store: BackupScopeStore? = nil, library: PhotoLibraryModel? = nil) {
    self.album = album
    self.store = store ?? .shared
    _library = StateObject(wrappedValue: library ?? PhotoLibraryModel(collection: album.id))
  }
  var body: some View {
    content.frame(maxWidth: .infinity, maxHeight: .infinity)
      .allowsHitTesting(previewAsset == nil).accessibilityHidden(previewAsset != nil)
      .overlay {
        if let previewAsset {
          ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(expanded ? 1 : 0)
            MacPhotoPreview(asset: previewAsset, library: library, navigation: navigation, close: close)
              .id(previewAsset.localIdentifier).opacity(mediaVisible ? 1 : 0)
          }
          .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.28), value: expanded)
        }
      }
      .navigationTitle(album.name)
      .focusedSceneValue(\.photoViewerCommands, previewAsset != nil ? MacViewerCommands(
        back: { navigation.viewerBack?() }, info: { navigation.viewerInfo.toggle() },
        share: { navigation.viewerShare?() }) : nil)
      .toolbar {
        if previewAsset != nil {
          MacViewerToolbar(navigation: navigation, back: { navigation.viewerBack?() })
        } else {
        MacLibraryScale(columns: $columns)
        ToolbarItem(placement: .primaryAction) {
          let chosen = store.rule.choosesAlbum(album.id)
          Button(chosen ? "scope_album_deselect" : "scope_album_choose") {
            store.save(store.rule.toggling(album: album.id, name: album.name))
          }.accessibilityIdentifier("backup.scope.album_browser.choose")
        }
        }
      }
      .task {
        if BackupEnvironment.usesPhotoLibrary { await library.open() }
        else if library.loaded == 0 { library.applyAuthorization(.denied) }
      }
      .onDisappear { library.thumbnails.clear() }
  }
  private func open(_ asset: PHAsset) {
    let token = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
    let source = navigation.coverLanding[.all]?(token, asset.localIdentifier)
    let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    previewAsset = asset; navigation.viewerOpen = true
    expanded = false; mediaVisible = reduce || source == nil
    DispatchQueue.main.async {
      expanded = true
      guard !reduce, let source else { mediaVisible = true; return }
      MacCoverFlight.fly(from: source, to: { target(asset, image: source.image) })
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { mediaVisible = true }
    }
  }
  private func target(_ asset: PHAsset, image: NSImage?) -> MacCoverFlightSource? {
    guard let area = navigation.viewerArea?(), asset.pixelWidth > 0, asset.pixelHeight > 0 else { return nil }
    let aspect = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    var size = CGSize(width: area.width, height: area.width / aspect)
    if size.height > area.height { size = CGSize(width: area.height * aspect, height: area.height) }
    return MacCoverFlightSource(rect: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
      width: size.width, height: size.height), image: image, radius: 0, assetID: asset.localIdentifier,
      clip: area, window: NSApp.keyWindow)
  }
  private func close(_ asset: PHAsset) {
    let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let start = reduce ? nil : target(asset, image: library.thumbnails.poster(for: asset))
    navigation.viewerOpen = false; mediaVisible = false; expanded = false
    let token = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
    navigation.focus(token)
    DispatchQueue.main.async {
      if let cell = navigation.coverLanding[.all]?(token, asset.localIdentifier), var start {
        start.clip = cell.clip
        MacCoverFlight.fly(from: start, to: { navigation.coverLanding[.all]?(token, asset.localIdentifier) })
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0 : 0.3)) {
      guard !expanded else { return }
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
            columns: columns, selecting: false, readOnly: true, prefillsTables: false, preview: open, resize: { columns = $0 })
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityIdentifier("backup.scope.album_browser")
        }
      }
    }
  }
}

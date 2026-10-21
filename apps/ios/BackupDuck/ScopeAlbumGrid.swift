import Combine
import Photos
import SwiftUI
import UIKit

/// The surrounding page owns search and the scope summary. UIKit owns reusable
/// covers, visible requests and scroll position through selection changes.
/// A tap chooses an album, as before; the long-press menu opens it to browse.
struct ScopeAlbumGrid: UIViewControllerRepresentable {
  let albums: [ScopeAlbum]
  let selected: Set<String>
  let search: String
  let listMode: Bool
  let choose: (ScopeAlbum) -> Void
  var open: (ScopeAlbum) -> Void = { _ in }
  func makeUIViewController(context: Context) -> ScopeAlbumController { ScopeAlbumController() }
  static func dismantleUIViewController(_ controller: ScopeAlbumController, coordinator: ()) {
    for cell in controller.collection.visibleCells { (cell as? ScopeAlbumCell)?.setDisplaying(false) }
    controller.policyObservation = nil
  }
  func updateUIViewController(_ controller: ScopeAlbumController, context: Context) {
    controller.apply(self)
  }
}

@MainActor final class ScopeAlbumController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  let layout = UICollectionViewFlowLayout()
  lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
  let empty = UILabel()
  var rows: [ScopeAlbum] = []
  var selected = Set<String>()
  var listMode = false
  var choose: ((ScopeAlbum) -> Void)?
  var open: ((ScopeAlbum) -> Void)?
  var policyObservation: AnyCancellable?
  private var previousWidth: CGFloat = 0
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(DuckRole.background)
    layout.minimumInteritemSpacing = 12; layout.minimumLineSpacing = 16
    layout.sectionInset = UIEdgeInsets(top: 12,left: 16,bottom: 20,right: 16)
    collection.backgroundColor = .clear; collection.dataSource = self; collection.delegate = self
    collection.alwaysBounceVertical = true; collection.contentInsetAdjustmentBehavior = .always
    collection.accessibilityIdentifier = "backup.scope.choices"
    collection.register(ScopeAlbumCell.self,forCellWithReuseIdentifier: "scope.album")
    view.addSubview(collection)
    empty.text = NSLocalizedString("scope_albums_empty",comment: "")
    empty.font = .preferredFont(forTextStyle: .body); empty.numberOfLines = 0; empty.textAlignment = .center
    empty.textColor = .secondaryLabel; collection.backgroundView = empty
    policyObservation = PreviewNetworkPolicy.shared.$choice.dropFirst().sink { [weak self] _ in
      guard let self else { return }
      for cell in self.collection.visibleCells { (cell as? ScopeAlbumCell)?.invalidateImage() }
      self.refreshVisible()
    }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    collection.frame = view.bounds
    if previousWidth != view.bounds.width {
      previousWidth = view.bounds.width; updateSize(); refreshVisible()
    }
  }
  func apply(_ source: ScopeAlbumGrid) {
    loadViewIfNeeded()
    let visible = source.albums.filter { source.search.isEmpty || $0.name.localizedCaseInsensitiveContains(source.search) }
    let membershipChanged = visible.map(\.id) != rows.map(\.id)
    let contentChanged = !membershipChanged && zip(visible,rows).contains { a,b in
      a.name != b.name || a.count != b.count || a.cover.map(PhotoLibraryModel.revision) != b.cover.map(PhotoLibraryModel.revision)
    }
    let geometryChanged = listMode != source.listMode
    rows = visible; selected = source.selected; listMode = source.listMode
    choose = source.choose; open = source.open
    if geometryChanged { updateSize() }
    if membershipChanged || contentChanged { collection.reloadData() }
    else { refreshVisible() }
    empty.isHidden = !rows.isEmpty
  }
  func updateSize() {
    let width = max(1,view.bounds.width-32)
    let columns = traitCollection.userInterfaceIdiom == .pad ? max(3,Int((width+12)/152)) : 3
    let side = listMode ? width : floor((width-CGFloat(columns-1)*12)/CGFloat(columns))
    let name = UIFont.preferredFont(forTextStyle: listMode ? .body : .caption1)
    let count = UIFont.preferredFont(forTextStyle: .caption1)
    layout.itemSize = CGSize(width: side,height: listMode ? max(76,name.lineHeight*2+count.lineHeight+12) : side+name.lineHeight*2+count.lineHeight+12)
    layout.invalidateLayout()
  }
  func refreshVisible() {
    for path in collection.indexPathsForVisibleItems where rows.indices.contains(path.item) {
      if let cell = collection.cellForItem(at: path) as? ScopeAlbumCell { configure(cell,at: path.item) }
    }
  }
  func configure(_ cell: ScopeAlbumCell, at index: Int) {
    let album = rows[index]
    cell.configure(album,selected: selected.contains(album.id),listMode: listMode,
      scale: traitCollection.displayScale,pipeline: ScopeThumbnailCache.pipeline)
    cell.accessibilityCustomActions = [UIAccessibilityCustomAction(name: NSLocalizedString("scope_album_view",comment: "")) { [weak self] _ in
      self?.open?(album); return true
    }]
  }
  func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt paths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
    guard let path = paths.first, rows.indices.contains(path.item) else { return nil }
    let album = rows[path.item], chosen = selected.contains(album.id)
    return UIContextMenuConfiguration(identifier: album.id as NSString, previewProvider: nil) { [weak self] _ in
      UIMenu(children: [
        UIAction(title: NSLocalizedString("scope_album_view",comment: ""),image: UIImage(systemName: "photo.on.rectangle")) { _ in self?.open?(album) },
        UIAction(title: NSLocalizedString(chosen ? "scope_album_deselect" : "scope_album_choose",comment: ""),
          image: UIImage(systemName: chosen ? "xmark.circle" : "checkmark.circle")) { _ in self?.choose?(album) },
      ])
    }
  }
  /// The menu lifts the cover alone, as Photos lifts an album, not the caption.
  private func coverPreview(_ configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    guard let id = configuration.identifier as? String, let index = rows.firstIndex(where: { $0.id == id }),
      let cell = collection.cellForItem(at: IndexPath(item: index,section: 0)) as? ScopeAlbumCell else { return nil }
    let parameters = UIPreviewParameters()
    parameters.visiblePath = UIBezierPath(roundedRect: cell.photo.bounds,cornerRadius: cell.photo.layer.cornerRadius)
    return UITargetedPreview(view: cell.photo,parameters: parameters)
  }
  func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, highlightPreviewForItemAt path: IndexPath) -> UITargetedPreview? {
    coverPreview(configuration)
  }
  func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, dismissalPreviewForItemAt path: IndexPath) -> UITargetedPreview? {
    coverPreview(configuration)
  }
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { rows.count }
  func collectionView(_ collectionView: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "scope.album",for: path) as! ScopeAlbumCell
    configure(cell,at: path.item); return cell
  }
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt path: IndexPath) {
    guard rows.indices.contains(path.item) else { return }; choose?(rows[path.item])
    collectionView.deselectItem(at: path,animated: false)
  }
  func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt path: IndexPath) {
    (cell as? ScopeAlbumCell)?.setDisplaying(true)
  }
  func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt path: IndexPath) {
    (cell as? ScopeAlbumCell)?.setDisplaying(false)
  }
}

@MainActor final class ScopeAlbumCell: UICollectionViewCell {
  let photo = UIImageView(), placeholder = UIImageView(image: UIImage(systemName: "rectangle.stack"))
  let name = UILabel(), count = UILabel(), check = UIImageView()
  var album: ScopeAlbum?, listMode = false, scale: CGFloat = 1
  weak var pipeline: ThumbnailPipeline?
  var request = PHInvalidImageRequestID, requestKey = "", token = UUID()
  var isChosen = false, displaying = false
  override init(frame: CGRect) {
    super.init(frame: frame)
    photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; photo.layer.cornerRadius = 7
    photo.backgroundColor = UIColor(DuckRole.groupedSurface)
    placeholder.contentMode = .scaleAspectFit; placeholder.tintColor = .secondaryLabel
    name.numberOfLines = 2; name.textColor = .label
    count.numberOfLines = 1; count.textColor = .secondaryLabel
    name.adjustsFontForContentSizeCategory = true; count.adjustsFontForContentSizeCategory = true
    [photo,placeholder,name,count,check].forEach { contentView.addSubview($0) }
    DuckMediaSelection.configure(check)
    isAccessibilityElement = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  func configure(_ album: ScopeAlbum, selected: Bool, listMode: Bool, scale: CGFloat, pipeline: ThumbnailPipeline) {
    if self.album?.id != album.id || self.album?.cover?.localIdentifier != album.cover?.localIdentifier { cancel(); photo.image = nil }
    self.album = album; self.listMode = listMode; self.scale = scale; self.pipeline = pipeline; isChosen = selected
    name.text = album.name; count.text = albumItemCount(album.count)
    name.font = .preferredFont(forTextStyle: listMode ? .body : .caption1)
    count.font = .preferredFont(forTextStyle: .caption1)
    DuckMediaSelection.apply(selected,enabled: true,badge: check,image: photo)
    accessibilityIdentifier = "backup.scope.album."+album.id
    accessibilityLabel = album.name; accessibilityValue = count.text
    accessibilityTraits = selected ? [.button,.selected] : .button
    setNeedsLayout(); layoutIfNeeded(); requestCover()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    let side = listMode ? min(76,bounds.height) : bounds.width
    photo.frame = CGRect(x: 0,y: 0,width: side,height: side)
    placeholder.frame = CGRect(x: side/2-14,y: side/2-14,width: 28,height: 28)
    check.frame = DuckMediaSelection.frame(in: photo.frame)
    let labelX: CGFloat = listMode ? side+12 : 0
    let labelY: CGFloat = listMode ? 0 : side+6
    let labelWidth = max(1,bounds.width-labelX)
    let labelHeight = min(name.font.lineHeight*2,max(name.font.lineHeight,name.sizeThatFits(CGSize(width: labelWidth,height: 500)).height))
    name.frame = CGRect(x: labelX,y: labelY,width: labelWidth,height: labelHeight)
    count.frame = CGRect(x: labelX,y: name.frame.maxY+3,width: name.frame.width,height: count.font.lineHeight)
    placeholder.isHidden = photo.image != nil
    requestCover()
  }
  func requestCover() {
    guard displaying, let asset = album?.cover, let pipeline, photo.bounds.width > 0 else { return }
    let pixels = pipeline.size(photo.bounds.width*scale).width
    let key = "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))|\(pixels)|\(pipeline.epoch)"
    guard key != requestKey else { return }
    cancel(); requestKey = key
    let generation = token
    request = pipeline.request(asset,pixels: pixels) { [weak self] image,_ in
      guard let self, self.token == generation else { return }
      if let image { self.photo.image = image; self.placeholder.isHidden = true }
    }
  }
  func setDisplaying(_ visible: Bool) {
    displaying = visible
    if visible { requestCover() } else { cancel() }
  }
  func cancel() { pipeline?.cancel(request); request = PHInvalidImageRequestID; requestKey = ""; token = UUID() }
  func invalidateImage() { cancel(); photo.image = nil; placeholder.isHidden = false }
  override func prepareForReuse() { super.prepareForReuse(); setDisplaying(false); album = nil; photo.image = nil }
}

/// One album's photos in the library grid, read-only. It has its own scoped
/// model (fetch, paging, thumbnail pipeline and scroll), so the main library
/// and the picker behind it keep their state; nothing here registers work.
struct ScopeAlbumBrowser: View {
  let album: ScopeAlbum
  @StateObject private var library: PhotoLibraryModel
  @ObservedObject private var store: BackupScopeStore
  @ObservedObject private var model = BackupModel.shared
  @State private var preview: IOSPreviewItem?
  @Environment(\.dismiss) private var dismiss
  @MainActor init(album: ScopeAlbum, store: BackupScopeStore? = nil) {
    self.album = album
    self.store = store ?? .shared
    _library = StateObject(wrappedValue: PhotoLibraryModel(collection: album.id))
  }
  var body: some View {
    content.frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(album.name).navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          let chosen = store.rule.choosesAlbum(album.id)
          Button { store.save(store.rule.toggling(album: album.id, name: album.name)) } label: {
            Label(chosen ? "scope_album_deselect" : "scope_album_choose", systemImage: chosen ? "checkmark.circle.fill" : "circle")
          }
          .accessibilityAddTraits(chosen ? .isSelected : [])
          .accessibilityIdentifier("backup.scope.album_browser.choose")
        }
      }
      .background(IOSPreviewPresentation(item: preview, library: library) { preview = nil }.frame(width: 0, height: 0))
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
      ContentUnavailableView {
        DuckIllustration(pose: .empty, size: 112)
        Text("library_empty_all")
      } description: { Text("scope_album_no_photos") } actions: {
        Button("mac_fidelity_back") { dismiss() }.buttonStyle(.bordered)
      }.accessibilityIdentifier("backup.scope.album_browser.empty")
    case let placeholder?:
      LibraryPlaceholder(kind: placeholder, requestingAccess: library.requestingPermission,
        requestAccess: {
          guard BackupEnvironment.usesPhotoLibrary else { return }
          Task { await library.open(requestPermission: true) }
        })
    case nil:
      IOSLibraryGrid(library: library,
        preparationRevision: "\(model.pendingImports)|\(model.importingSourceID ?? "")",
        queueRevision: model.queueRevision, receiverID: model.pairing?.receiverID,
        backupModel: model, selectionEnabled: false, browseOnly: true,
        onPreview: { index, frame in
          guard let asset = library.asset(at: index) else { return }
          var transaction = Transaction(); transaction.disablesAnimations = true
          withTransaction(transaction) {
            preview = IOSPreviewItem(asset: asset, frame: frame,
              poster: library.previewPoster?(asset.localIdentifier) ?? library.thumbnails.poster(for: asset))
          }
        }).accessibilityIdentifier("backup.scope.album_browser").duckLibraryViewport()
    }
  }
}

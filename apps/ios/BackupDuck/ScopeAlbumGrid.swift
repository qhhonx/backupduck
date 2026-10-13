import Combine
import Photos
import SwiftUI
import UIKit

/// The surrounding page owns search and the scope summary. UIKit owns reusable
/// covers, visible requests and scroll position through selection changes.
struct ScopeAlbumGrid: UIViewControllerRepresentable {
  let albums: [ScopeAlbum]
  let selected: Set<String>
  let search: String
  let listMode: Bool
  let allSelected: Bool
  let chooseAll: () -> Void
  let choose: (ScopeAlbum) -> Void
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
  let all = UIButton(type: .system), empty = UILabel()
  var rows: [ScopeAlbum] = []
  var selected = Set<String>()
  var listMode = false
  var chooseAll: (() -> Void)?, choose: ((ScopeAlbum) -> Void)?
  var policyObservation: AnyCancellable?
  private var previousWidth: CGFloat = 0
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(DuckColors.canvas)
    layout.minimumInteritemSpacing = 12; layout.minimumLineSpacing = 16
    layout.sectionInset = UIEdgeInsets(top: 12,left: 16,bottom: 20,right: 16)
    collection.backgroundColor = .clear; collection.dataSource = self; collection.delegate = self
    collection.alwaysBounceVertical = true; collection.contentInsetAdjustmentBehavior = .always
    collection.accessibilityIdentifier = "backup.scope.choices"
    collection.register(ScopeAlbumCell.self,forCellWithReuseIdentifier: "scope.album")
    view.addSubview(collection)
    all.contentHorizontalAlignment = .leading; all.titleLabel?.font = .preferredFont(forTextStyle: .body)
    all.titleLabel?.adjustsFontForContentSizeCategory = true
    all.accessibilityIdentifier = "backup.scope.all_albums"
    all.addAction(UIAction { [weak self] _ in self?.chooseAll?() },for: .touchUpInside)
    view.addSubview(all)
    empty.text = NSLocalizedString("scope_albums_empty",comment: "")
    empty.font = .preferredFont(forTextStyle: .body); empty.numberOfLines = 0; empty.textAlignment = .center
    empty.textColor = UIColor(DuckColors.textSecondary); collection.backgroundView = empty
    policyObservation = PreviewNetworkPolicy.shared.$choice.dropFirst().sink { [weak self] _ in
      guard let self else { return }
      for cell in self.collection.visibleCells { (cell as? ScopeAlbumCell)?.invalidateImage() }
      self.refreshVisible()
    }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let allHeight = max(52,UIFont.preferredFont(forTextStyle: .body).lineHeight+24)
    all.frame = CGRect(x: 16,y: 0,width: view.bounds.width-32,height: allHeight)
    collection.frame = CGRect(x: 0,y: allHeight+4,width: view.bounds.width,height: max(0,view.bounds.height-allHeight-4))
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
    chooseAll = source.chooseAll; choose = source.choose
    var configuration = UIButton.Configuration.plain()
    configuration.title = NSLocalizedString("scope_all_albums",comment: "")
    configuration.image = UIImage(systemName: "rectangle.stack")
    configuration.imagePadding = 12
    configuration.baseForegroundColor = UIColor(DuckColors.text)
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12,leading: 16,bottom: 12,trailing: 16)
    configuration.background.backgroundColor = UIColor(DuckColors.surface)
    configuration.background.cornerRadius = 12
    all.configuration = configuration
    all.accessibilityTraits = source.allSelected ? [.button,.selected] : .button
    all.setTitle(NSLocalizedString("scope_all_albums",comment: ""),for: .normal)
    all.accessibilityValue = source.allSelected ? NSLocalizedString("selected",comment: "") : nil
    // The fixed trailing check does not dim or animate the entire choice row.
    let check = all.viewWithTag(58) as? UIImageView ?? UIImageView(image: UIImage(systemName: "checkmark"))
    if check.superview == nil { check.tag = 58; check.tintColor = UIColor(DuckColors.action); all.addSubview(check) }
    check.frame = CGRect(x: max(0,view.bounds.width-32-40),y: 14,width: 24,height: 24)
    check.isHidden = !source.allSelected
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
    cell.configure(rows[index],selected: selected.contains(rows[index].id),listMode: listMode,
      scale: traitCollection.displayScale,pipeline: ScopeThumbnailCache.pipeline)
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
    photo.backgroundColor = UIColor(DuckColors.subtle)
    placeholder.contentMode = .scaleAspectFit; placeholder.tintColor = UIColor(DuckColors.textSecondary)
    name.numberOfLines = 2; name.textColor = UIColor(DuckColors.text)
    count.numberOfLines = 1; count.textColor = UIColor(DuckColors.textSecondary)
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

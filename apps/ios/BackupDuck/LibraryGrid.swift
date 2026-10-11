import Photos
import AVKit
import PhotosUI
import SwiftUI
import UIKit

struct IOSLibraryGrid: UIViewRepresentable {
  @ObservedObject var library: PhotoLibraryModel
  var preparationRevision: String = ""
  var queueRevision: Int64
  var receiverID: String?
  @ObservedObject var backupModel: BackupModel = BackupModel.shared
  var showSupplementaryContent = false
  var selectionEnabled = true
  var onPreview: (Int) -> Void = { _ in }
  var onBeginSelection: (Int) -> Void = { _ in }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UICollectionView {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 3
    layout.minimumInteritemSpacing = 3
    layout.sectionInset = showSupplementaryContent
      ? UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
      : UIEdgeInsets(top: 4, left: 8, bottom: 16, right: 8)
    let view = LibraryCollectionView(frame: .zero, collectionViewLayout: layout)
    view.backgroundColor = .clear
    // The viewport extends beneath the native tab/accessory chrome; UIKit still
    // reserves its real safe area so the final asset can scroll above controls.
    view.contentInsetAdjustmentBehavior = .always
    if #available(iOS 26.0, *) { view.bottomEdgeEffect.style = .soft }
    view.accessibilityIdentifier = "library.grid"
    view.allowsMultipleSelection = true
    view.register(PhotoCell.self, forCellWithReuseIdentifier: "photo")
    view.register(LibrarySupplementaryView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "library.header")
    view.register(LibrarySupplementaryView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "library.footer")
    view.dataSource = context.coordinator
    view.delegate = context.coordinator
    let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
    press.minimumPressDuration = 0.4
    press.cancelsTouchesInView = true
    view.addGestureRecognizer(press)
    context.coordinator.collection = view
    return view
  }
  func updateUIView(_ view: UICollectionView, context: Context) {
    let c = context.coordinator
    c.parent = self
    if c.generation != library.generation { c.stopDrag(revert: true) }
    c.updateSupplementaryContent()
    if c.generation != library.generation {
      c.clearPresentationCache()
      let sameFilter = (c.filter == nil || c.filter == library.filter)
        && (c.scrollResetGeneration == nil || c.scrollResetGeneration == library.scrollResetGeneration)
      if sameFilter, c.restored { c.rememberScroll() }
      let savedOffset = sameFilter ? library.scrollOffset : CGPoint.zero
      let savedAnchor = sameFilter ? library.scrollAnchorID : nil
      let savedInset = library.scrollAnchorInset
      c.filter = library.filter
      c.scrollResetGeneration = library.scrollResetGeneration
      c.generation = library.generation
      c.count = library.loaded
      c.restored = false
      c.applyingSelection = true
      c.appliedSelection = nil
      view.reloadData()
      // SwiftUI can create the collection with zero bounds. Restore only after
      // the native layout has a viewport, otherwise UIKit clamps to the top.
      (view as? LibraryCollectionView)?.restoreScroll = { [weak c] view in
        guard let c else { return true }
        var offset = savedOffset
        if let index = library.index(of: savedAnchor), index < c.count,
          let frame = view.collectionViewLayout.layoutAttributesForItem(
            at: IndexPath(item: index, section: 0))?.frame {
          offset.y = frame.minY + savedInset
        }
        let maximumY = max(-view.adjustedContentInset.top,
          view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        let needsFollowingRows = offset.y > maximumY + 1 && library.hasMoreRows
        offset.y = min(max(-view.adjustedContentInset.top, offset.y), maximumY)
        view.setContentOffset(offset, animated: false)
        if needsFollowingRows {
          // The retained asset can move to the last metadata row after a large
          // insertion. Keep its intended inset until one more page fills the
          // viewport, rather than accepting UIKit's temporary end clamp.
          library.loadMore()
          return false
        }
        c.restored = true
        c.applyingSelection = false
        c.scrolled()
        return true
      }
      view.setNeedsLayout()
      view.layoutIfNeeded()
    } else if c.count < library.loaded {
      let old = c.count
      c.count = library.loaded
      c.appliedSelection = nil
      view.insertItems(at: (old..<c.count).map { IndexPath(item: $0, section: 0) })
      view.setNeedsLayout()
    }
    if c.contentGeneration != library.contentGeneration {
      c.clearPresentationCache()
      c.contentGeneration = library.contentGeneration
      for path in view.indexPathsForVisibleItems {
        if let cell = view.cellForItem(at: path) as? PhotoCell { c.configure(cell, path: path) }
      }
      c.scrolled()
    }
    if c.preparationRevision != preparationRevision {
      c.preparationRevision = preparationRevision
      c.clearPresentationCache()
      c.scrolled()
    }
    if c.queueRevision != queueRevision || c.receiverID != receiverID {
      c.queueRevision = queueRevision
      c.receiverID = receiverID
      c.clearPresentationCache()
      c.scrolled()
    }
    let displayedSelection = selectionEnabled ? library.selection : []
    for path in view.indexPathsForVisibleItems {
      (view.cellForItem(at: path) as? PhotoCell)?.showsSelection = selectionEnabled
    }
    if c.appliedSelection != displayedSelection {
      c.applyingSelection = true
      let desired = selectionEnabled ? library.selectedIndexPaths() : []
      let current = Set(view.indexPathsForSelectedItems ?? [])
      current.subtracting(desired).forEach { view.deselectItem(at: $0, animated: false) }
      desired.subtracting(current).forEach {
        view.selectItem(at: $0, animated: false, scrollPosition: [])
      }
      c.appliedSelection = displayedSelection
      c.applyingSelection = false
    }
    if (view as? LibraryCollectionView)?.restoreScroll != nil { view.setNeedsLayout() }
  }
  static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
    coordinator.stopDrag(revert: true)
    coordinator.rememberScroll()
    coordinator.refresh.cancel()
    coordinator.parent.library.thumbnails.clear()
  }
  @MainActor
  final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout
  {
    var parent: IOSLibraryGrid
    weak var collection: UICollectionView?
    let refresh = LibraryRefreshScheduler()
    var count = 0, generation = -1
    var preparationRevision = ""
    var contentGeneration = -1
    var queueRevision: Int64 = -2
    var receiverID: String?
    var restored = false
    var applyingSelection = false
    var appliedSelection: Set<String>?
    private var presentation: [String: (count: Int?, state: String?)] = [:]
    var filter: LibraryFilter?
    var scrollResetGeneration: Int?
    private var dragStart: Int?
    private var dragGeneration = -1
    private var dragSelection: LibraryRangeSelection?
    private var dragPoint = CGPoint.zero
    private var dragLink: CADisplayLink?
    private var dragTime: CFTimeInterval = 0
    init(_ parent: IOSLibraryGrid) { self.parent = parent }
    func clearPresentationCache() { presentation.removeAll(keepingCapacity: true) }
    private var headerHeight: CGFloat = 0
    private let headerSizer = UIHostingController(rootView: AnyView(EmptyView()))
    private var headerContent: AnyView { AnyView(IOSLibraryHeader(library: parent.library)) }
    func updateSupplementaryContent() {
      guard let collection, parent.showSupplementaryContent, collection.bounds.width > 0 else { return }
      headerSizer.rootView = headerContent
      let size = CGSize(width: collection.bounds.width, height: 10_000)
      let nextHeader = ceil(headerSizer.sizeThatFits(in: size).height)
      if abs(headerHeight - nextHeader) > 1 {
        headerHeight = nextHeader
        collection.collectionViewLayout.invalidateLayout()
      }
      for kind in [UICollectionView.elementKindSectionHeader] {
        for path in collection.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
          (collection.supplementaryView(forElementKind: kind, at: path) as? LibrarySupplementaryView)?
            .setContent(headerContent)
        }
      }
    }
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
      let reuse = kind == UICollectionView.elementKindSectionHeader ? "library.header" : "library.footer"
      let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: reuse, for: indexPath) as! LibrarySupplementaryView
      view.setContent(headerContent)
      return view
    }
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
      guard parent.showSupplementaryContent else { return .zero }
      if headerHeight == 0 {
        headerSizer.rootView = headerContent
        headerHeight = ceil(headerSizer.sizeThatFits(in: CGSize(width: collectionView.bounds.width, height: 10_000)).height)
      }
      return CGSize(width: collectionView.bounds.width, height: max(1, headerHeight))
    }
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
      .zero
    }

    private func presentationKey(_ asset: PHAsset) -> String {
      asset.localIdentifier + "|" + PhotoLibraryModel.revision(asset)
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
      -> Int
    { count }
    func collectionView(
      _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
      sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
      let columns = parent.showSupplementaryContent ? 3 : max(3, floor(collectionView.bounds.width / 135))
      let inset: CGFloat = parent.showSupplementaryContent ? 20 : 16
      let side = floor((collectionView.bounds.width - inset - (columns - 1) * 3) / columns)
      return CGSize(width: side, height: side)
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
      -> UICollectionViewCell
    {
      let cell =
        collectionView.dequeueReusableCell(withReuseIdentifier: "photo", for: indexPath)
        as! PhotoCell
      configure(cell, path: indexPath)
      return cell
    }
    func collectionView(
      _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
      forItemAt indexPath: IndexPath
    ) {
      if let cell = cell as? PhotoCell { configure(cell, path: indexPath) }
      scrolled()
    }
    func configure(_ cell: PhotoCell, path: IndexPath) {
      if let asset = parent.library.asset(at: path.item) {
        cell.accessibilityCustomActions = parent.selectionEnabled ? nil : [UIAccessibilityCustomAction(name: NSLocalizedString("library_select", comment: ""), actionHandler: { [weak self, weak cell] _ in
          guard let self, let cell, let path = self.collection?.indexPath(for: cell) else { return false }
          self.parent.onBeginSelection(path.item)
          return true
        })]
        cell.showsSelection = parent.selectionEnabled
        cell.configure(asset, pipeline: parent.library.thumbnails, pixels: 400,
          identifier: parent.library.identifier(at: path.item))
        if let cached = presentation[presentationKey(asset)] {
          cell.setGroup(count: cached.count, state: cached.state)
        }
      }
    }
    func collectionView(
      _ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
      forItemAt indexPath: IndexPath
    ) { (cell as? PhotoCell)?.cancel() }
    @objc func longPress(_ recognizer: UILongPressGestureRecognizer) {
      guard let collection, let window = collection.window else { return }
      switch recognizer.state {
      case .began:
        guard let path = collection.indexPathForItem(at: recognizer.location(in: collection)),
          let id = parent.library.identifier(at: path.item) else { return }
        dragStart = path.item; dragGeneration = parent.library.generation
        dragSelection = LibraryRangeSelection(baseline: parent.library.selection,
          adding: !parent.library.selection.contains(id))
        if !parent.selectionEnabled { parent.onBeginSelection(path.item) }
        dragPoint = recognizer.location(in: window)
        applyDrag(at: recognizer.location(in: collection))
        dragTime = 0
        let link = CADisplayLink(target: self, selector: #selector(dragTick(_:)))
        link.add(to: .main, forMode: .common); dragLink = link
      case .changed:
        dragPoint = recognizer.location(in: window)
        applyDrag(at: recognizer.location(in: collection))
      case .ended: stopDrag(revert: false)
      case .cancelled, .failed: stopDrag(revert: true)
      default: break
      }
    }
    func stopDrag(revert: Bool) {
      dragLink?.invalidate(); dragLink = nil
      if revert, let snapshot = dragSelection { parent.library.selection = snapshot.baseline }
      dragStart = nil; dragSelection = nil; dragTime = 0
    }
    private func applyDrag(at point: CGPoint) {
      guard let collection, let start = dragStart, let snapshot = dragSelection,
        dragGeneration == parent.library.generation else { stopDrag(revert: true); return }
      let safe = selectionViewport(collection)
      let clamped = CGPoint(x: min(max(point.x, safe.minX + 1), safe.maxX - 1),
        y: min(max(point.y, safe.minY + 1), safe.maxY - 1))
      guard let path = collection.indexPathForItem(at: clamped) else { return }
      let ids = (min(start, path.item)...max(start, path.item)).compactMap(parent.library.identifier(at:))
      let next = snapshot.applying(ids)
      if next != parent.library.selection { parent.library.selection = next }
    }
    private func selectionViewport(_ view: UICollectionView) -> CGRect {
      var rect = view.bounds.inset(by: view.adjustedContentInset)
      if let window = view.window {
        func bars(_ v: UIView) -> [UITabBar] { (v as? UITabBar).map { [$0] } ?? v.subviews.flatMap(bars) }
        if let bar = bars(window).first(where: { !$0.isHidden && $0.alpha > 0 }),
          bar.convert(bar.bounds, to: view).minY > rect.minY {
          rect.size.height = min(rect.maxY, bar.convert(bar.bounds, to: view).minY) - rect.minY
        }
      }
      return rect
    }
    @objc private func dragTick(_ link: CADisplayLink) {
      guard let collection, let window = collection.window, dragStart != nil,
        UIApplication.shared.applicationState == .active,
        dragGeneration == parent.library.generation else { stopDrag(revert: true); return }
      var ancestor: UIView? = collection
      while let view = ancestor { if view.isHidden { stopDrag(revert: true); return }; ancestor = view.superview }
      let point = collection.convert(dragPoint, from: window), viewport = selectionViewport(collection)
      let band: CGFloat = 44
      let velocity: CGFloat = point.y < viewport.minY + band ? -min(1, (viewport.minY + band - point.y) / band) * 480
        : point.y > viewport.maxY - band ? min(1, (point.y - viewport.maxY + band) / band) * 480 : 0
      let dt = dragTime == 0 ? 0 : min(link.timestamp - dragTime, 0.05); dragTime = link.timestamp
      if velocity != 0 {
        let top = -collection.adjustedContentInset.top
        let bottom = max(top, collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom)
        let y = min(max(collection.contentOffset.y + velocity * CGFloat(dt), top), bottom)
        collection.setContentOffset(CGPoint(x: collection.contentOffset.x, y: y), animated: false)
      }
      applyDrag(at: collection.convert(dragPoint, from: window))
    }
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
      if !parent.selectionEnabled { parent.onPreview(indexPath.item); return false }
      return true
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
      guard !applyingSelection, let id = parent.library.identifier(at: indexPath.item) else { return }
      parent.library.selection.insert(id)
      appliedSelection = parent.library.selection
    }
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
      guard !applyingSelection, let id = parent.library.identifier(at: indexPath.item) else { return }
      parent.library.selection.remove(id)
      appliedSelection = parent.library.selection
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      if restored, generation == parent.library.generation { rememberScroll() }
      scrolled()
    }
    func rememberScroll() {
      guard restored, parent.library.authorized, filter == parent.library.filter,
        scrollResetGeneration == parent.library.scrollResetGeneration, let collection,
        let top = collection.indexPathsForVisibleItems.sorted().first,
        let id = (collection.cellForItem(at: top) as? PhotoCell)?.presentationID,
        let frame = collection.collectionViewLayout.layoutAttributesForItem(at: top)?.frame,
        frame.intersects(collection.bounds)
      else { return }
      parent.library.scrollOffset = collection.contentOffset
      parent.library.scrollAnchorID = id
      parent.library.scrollAnchorInset = collection.contentOffset.y - frame.minY
    }
    func scrolled() {
      guard restored else { return }
      refresh.schedule { [weak self] in
        guard let self, !Task.isCancelled, let collection = self.collection else { return }
        let parent = self.parent
        self.rememberScroll()
        let generation = parent.library.generation
        let receiverID = parent.receiverID
        let revision = parent.queueRevision
        let preparation = parent.preparationRevision
        let paths = collection.indexPathsForVisibleItems.sorted()
        guard let first = paths.first?.item, let last = paths.last?.item else { return }
        let identities = Dictionary(uniqueKeysWithValues: paths.compactMap { path in
          parent.library.asset(at: path.item).map { (path, $0.localIdentifier) }
        })
        if last >= parent.library.loaded - 36 { parent.library.loadMore() }
        let range = max(0, first - 18)..<min(parent.library.loaded, last + 37)
        parent.library.thumbnails.preheat(
          range.compactMap { parent.library.asset(at: $0) }, pixels: 400)
        let visible = paths.compactMap { parent.library.asset(at: $0.item) }
        let groups = await parent.library.visibleGroups(visible)
        guard !Task.isCancelled, generation == self.parent.library.generation else { return }
        guard !Set(paths).isDisjoint(with: collection.indexPathsForVisibleItems) else { return }
        guard let states = await librarySourceStates(groups, receiver: receiverID) else { return }
        guard !Task.isCancelled, generation == self.parent.library.generation,
          receiverID == self.parent.receiverID, revision == self.parent.queueRevision,
          preparation == self.parent.preparationRevision else { return }
        for path in paths {
          if let cell = collection.cellForItem(at: path) as? PhotoCell {
            guard cell.assetID == identities[path] else { continue }
            let group = groups[cell.assetID ?? ""]
            guard let asset = parent.library.asset(at: path.item) else { continue }
            let count = asset.burstIdentifier != nil ? group?.count : nil
            let state = group?.state(states)
            self.presentation[self.presentationKey(asset)] = (count, state)
            cell.setGroup(count: count, state: state)
          }
        }
        if self.presentation.count > 256 { self.presentation.removeAll(keepingCapacity: true) }
      }
    }
  }
}

@MainActor private final class LibraryCollectionView: UICollectionView {
  var restoreScroll: ((LibraryCollectionView) -> Bool)?
  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0, let restore = restoreScroll else { return }
    if restore(self) { restoreScroll = nil }
  }
}

@MainActor final class PhotoCell: UICollectionViewCell {
  private let photo = UIImageView()
  private let media = UIImageView()
  private let status = UIImageView()
  private let selection = UIImageView()
  private let cloud = UIImageView()
  private let burstCount = UILabel()
  private let duration = UILabel()
  private var groupDescription = ""
  private var request: PHImageRequestID = PHInvalidImageRequestID
  private var pipeline: ThumbnailPipeline?
  private var token = UUID(), key = ""
  private(set) var assetID: String?
  private(set) var presentationID: String?
  var showsSelection = true {
    didSet { selection.isHidden = !showsSelection; status.isHidden = showsSelection || status.image == nil; updateSelectionAppearance() }
  }
  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.backgroundColor = .tertiarySystemFill
    photo.contentMode = .scaleAspectFill
    photo.clipsToBounds = true
    contentView.addSubview(photo)
    for badge in [media, status, cloud] {
      badge.tintColor = .white
      badge.backgroundColor = .black.withAlphaComponent(0.35)
      badge.layer.cornerRadius = 11
      badge.clipsToBounds = true
      badge.contentMode = .scaleAspectFit
      contentView.addSubview(badge)
    }
    burstCount.textColor = .white
    burstCount.backgroundColor = .black.withAlphaComponent(0.45)
    burstCount.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    burstCount.textAlignment = .center
    burstCount.layer.cornerRadius = 9
    burstCount.clipsToBounds = true
    burstCount.adjustsFontSizeToFitWidth = true
    burstCount.isHidden = true
    contentView.addSubview(burstCount)
    duration.textColor = .white
    duration.backgroundColor = .black.withAlphaComponent(0.55)
    duration.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    duration.textAlignment = .center
    duration.layer.cornerRadius = 5
    duration.clipsToBounds = true
    duration.isHidden = true
    contentView.addSubview(duration)
    cloud.isHidden = true
    media.isHidden = true
    media.backgroundColor = .black.withAlphaComponent(0.35)
    media.layer.cornerRadius = 5; media.clipsToBounds = true
    selection.image = UIImage(systemName: "circle")
    selection.tintColor = .white; selection.backgroundColor = .black.withAlphaComponent(0.35)
    selection.layer.cornerRadius = 12; selection.clipsToBounds = true
    selection.contentMode = .scaleAspectFit; contentView.addSubview(selection)
    isAccessibilityElement = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layoutSubviews() {
    super.layoutSubviews()
    photo.frame = contentView.bounds
    media.frame = CGRect(x: 6, y: 6, width: 22, height: 22)
    burstCount.frame = CGRect(x: 31, y: 6, width: 42, height: 22)
    let durationWidth = min(bounds.width - 12, max(42, duration.intrinsicContentSize.width + 12))
    duration.frame = CGRect(x: 31, y: 6, width: durationWidth, height: 22)
    cloud.frame = CGRect(x: 6, y: bounds.height - 28, width: 22, height: 22)
    status.frame = CGRect(x: bounds.width - 27, y: 6, width: 21, height: 21)
    selection.frame = CGRect(x: bounds.width - 30, y: bounds.height - 30, width: 24, height: 24)
  }
  override var isSelected: Bool {
    didSet { updateSelectionAppearance() }
  }
  private func updateSelectionAppearance() {
      let selected = showsSelection && isSelected
      contentView.layer.borderWidth = selected ? 3 : 0
      contentView.layer.borderColor = UIColor(DuckColors.action).cgColor
      selection.image = UIImage(systemName: selected ? "checkmark" : "circle")
      selection.backgroundColor = selected ? UIColor(DuckColors.action) : .black.withAlphaComponent(0.35)
      accessibilityTraits = selected ? [.button, .selected] : [.button]
  }
  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      // A layer stores a resolved CGColor; UIKit cannot automatically refresh
      // it when the app appearance changes while a selection is retained.
      contentView.layer.borderColor = UIColor(DuckColors.action)
        .resolvedColor(with: traitCollection).cgColor
    }
  }
  func configure(_ asset: PHAsset, pipeline: ThumbnailPipeline, pixels: CGFloat, identifier: String? = nil) {
    presentationID = identifier ?? asset.localIdentifier
    accessibilityIdentifier = "library.asset." + (presentationID ?? asset.localIdentifier)
    let next = asset.localIdentifier + PhotoLibraryModel.revision(asset)
    guard key != next else { return }
    let sameAsset = assetID == asset.localIdentifier
    cancel()
    self.pipeline = pipeline
    key = next
    assetID = asset.localIdentifier
    let expected = token
    photo.image = nil
    cloud.isHidden = true
    let symbol =
      asset.burstIdentifier != nil ? "square.stack" : asset.mediaSubtypes.contains(.photoLive)
      ? "livephoto" : asset.mediaType == .video ? "video" : "photo"
    media.image = UIImage(systemName: symbol)
    media.isHidden = false
    duration.text = asset.mediaType == .video ? videoDurationLabel(asset.duration) : nil
    duration.isHidden = asset.mediaType != .video
    setNeedsLayout()
    let type = asset.burstIdentifier != nil ? "burst" : asset.mediaType == .video ? "video"
      : asset.mediaSubtypes.contains(.photoLive) ? "motion" : "photo"
    accessibilityLabel = [NSLocalizedString("library_filter_" + type, comment: ""),
      asset.creationDate?.formatted(date: .abbreviated, time: .shortened)
        ?? NSLocalizedString("design_capture_unknown", comment: ""),
      asset.mediaType == .video ? videoDurationLabel(asset.duration) : nil]
      .compactMap { $0 }.joined(separator: ", ")
    if !sameAsset { setGroup(count: nil, state: nil); photo.image = nil }
    request = pipeline.request(asset, pixels: pixels) { [weak self] image, inCloud in
      guard let self, expected == self.token else { return }
      if let image { self.photo.image = image }
      self.cloud.image = UIImage(systemName: "icloud")
      self.cloud.isHidden = self.photo.image != nil || !inCloud
    }
  }
  func setGroup(count: Int?, state: String?) {
    if count != nil {
      media.image = UIImage(systemName: "square.stack")
      media.isHidden = false
    }
    accessibilityHint = count == nil ? nil : NSLocalizedString("library_burst_selection", comment: "")
    burstCount.text = count.map(String.init)
    burstCount.isHidden = count == nil
    groupDescription = count.map { String(format: NSLocalizedString("library_burst_count", comment: ""), $0) + ". " } ?? ""
    setState(state)
  }
  func setState(_ state: String?) {
    status.image = UIImage(systemName: taskSymbol(state))
    status.isHidden = showsSelection || status.image == nil
    status.tintColor = state == "failed" ? UIColor(DuckColors.failure) : .white
    accessibilityValue = groupDescription + NSLocalizedString(
      state == "received" ? "state_received_detail" : state.map { "state_" + $0 } ?? "state_not_queued", comment: "")
  }
  func cancel() {
    pipeline?.cancel(request)
    request = PHInvalidImageRequestID
    token = UUID()
    key = ""
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    cancel()
    photo.image = nil
    assetID = nil
    presentationID = nil
  }
}

struct IOSLibraryPage: View {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var model: BackupModel
  @State private var confirmSelectedBackup = false
  @State private var rebackupReceivedSelection = false
  @State private var selecting = false
  @State private var preview: IOSPreviewItem?
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        libraryToolbar.padding(.horizontal, 16).padding(.vertical, 4).frame(minHeight: 60)
          .background(DuckColors.surface).overlay(alignment: .bottom) { Divider() }
        if let placeholder = library.placeholder {
          LibraryPlaceholder(kind: placeholder,
            requestingAccess: library.requestingPermission,
            requestAccess: { Task { await library.open(requestPermission: true) } },
            clearFilter: { Task { await library.changeFilter(.all) } })
        } else {
          IOSLibraryGrid(library: library,
            preparationRevision: "\(model.pendingImports)|\(model.importingSourceID ?? "")",
            queueRevision: model.queueRevision, receiverID: model.pairing?.receiverID,
            backupModel: model, showSupplementaryContent: false, selectionEnabled: selecting,
            onPreview: { index in
              if let asset = library.asset(at: index) { preview = IOSPreviewItem(asset: asset) }
            }, onBeginSelection: { index in
              guard let id = library.identifier(at: index) else { return }
              library.selection.insert(id); selecting = true
            }).frame(maxWidth: 640).ignoresSafeArea(.container, edges: .bottom)
        }
      }.background(DuckColors.canvas).foregroundStyle(DuckColors.text).toolbar(.hidden, for: .navigationBar).symbolVariant(.none)
      .task { await library.open() }
      .sheet(isPresented: $confirmSelectedBackup) { selectedBackupConfirmation }
      .fullScreenCover(item: $preview) { IOSPhotoPreview(asset: $0.asset) }

    }
  }
  @Environment(\.dynamicTypeSize) private var textSize
  private var selectionTitle: some View {
    Text(String(format: NSLocalizedString("library_selection_title", comment: ""), library.selection.count))
      .font(.title2.weight(.semibold)).accessibilityIdentifier("page.header.title")
  }
  private var browsingTitle: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("nav_library").font(.title2.weight(.semibold)).accessibilityIdentifier("page.header.title")
      if library.authorized {
        Text(String(format: NSLocalizedString("library_count_compact", comment: ""), library.total.formatted()))
          .font(.caption).foregroundStyle(DuckColors.textSecondary)
      }
    }
  }
  private var selectionActions: some View {
    HStack(spacing: 8) {
      Button("settings_done") { selecting = false; library.selection.removeAll() }
        .buttonStyle(.plain).foregroundStyle(DuckColors.action).frame(minWidth: 44, minHeight: 44)
        .accessibilityIdentifier("library.select_mode")
      Button("library_backup_action", action: showBackupConfirmation)
        .font(.body.weight(.semibold)).buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small)
        .foregroundStyle(DuckColors.canvas).frame(minWidth: 60, minHeight: 44)
        .disabled(library.selection.isEmpty || model.pairing == nil || model.importing)
        .accessibilityIdentifier("library.backup_selected_footer")
        .accessibilityValue(Text(String(format: NSLocalizedString("library_selected_count", comment: ""), library.selection.count)))
    }
  }
  @ViewBuilder private var typeMenu: some View {
    if library.authorized {
      Menu {
        Picker("media_type", selection: Binding(get: { library.filter }, set: { value in Task { await library.changeFilter(value) } })) {
          ForEach(LibraryFilter.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
        }.pickerStyle(.inline)
      } label: {
        HStack(spacing: 4) {
          Text(String(format: NSLocalizedString("library_type_format", comment: ""), NSLocalizedString(library.filter.title, comment: "")))
          Image(systemName: "chevron.down").font(.caption)
        }.font(.callout).frame(minHeight: 44)
      }.buttonStyle(.plain).foregroundStyle(DuckColors.action).accessibilityIdentifier("library.filter")
    }
  }
  @ViewBuilder private var libraryToolbar: some View {
    if textSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 4) {
        if selecting { selectionTitle } else { browsingTitle }
        HStack { Spacer(minLength: 0); if selecting { selectionActions } else { typeMenu } }
      }
    } else {
      HStack(spacing: 8) {
        if selecting { selectionTitle } else { browsingTitle }
        Spacer(minLength: 4)
        if selecting { selectionActions } else { typeMenu }
      }
    }
  }
  private func showBackupConfirmation() {
    rebackupReceivedSelection = false
    confirmSelectedBackup = true
  }
  private var selectedBackupConfirmation: some View {
    DuckSelectedBackup(count: library.selection.count, rebackup: $rebackupReceivedSelection,
      failureMessage: { model.message.flatMap { $0.isEmpty ? nil : $0 } }) {
      let rebackup = rebackupReceivedSelection
      return await backupSelection(rebackupReceived: rebackup)
    }
  }
  private func backupSelection(rebackupReceived: Bool) async -> Bool {
    let tokens = library.selection
    let ids = await library.selectedAssetIdentifiers(tokens)
    let accepted = await model.backupSelectedAssets(ids, rebackupReceived: rebackupReceived)
    if accepted {
      library.selection.subtract(tokens)
    }
    return accepted
  }
}

@MainActor private final class LibrarySupplementaryView: UICollectionReusableView {
  private var host: UIHostingController<AnyView>?
  func setContent(_ content: AnyView) {
    if let host { host.rootView = content; return }
    let host = UIHostingController(rootView: content)
    self.host = host; host.view.backgroundColor = .clear
    host.view.translatesAutoresizingMaskIntoConstraints = false
    addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: leadingAnchor), host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
      host.view.topAnchor.constraint(equalTo: topAnchor), host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }
}
private struct IOSLibraryHeader: View {
  @ObservedObject var library: PhotoLibraryModel
  @ScaledMetric(relativeTo: .caption) private var caption = 13
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(String(format: NSLocalizedString("library_count", comment: ""), library.total))
          .font(.system(size: caption)).foregroundStyle(DuckColors.textSecondary)
        Spacer()
        Picker("task_filter", selection: Binding(get: { library.filter },
          set: { option in Task { await library.changeFilter(option) } })) {
          ForEach(LibraryFilter.allCases) { option in
            Text(LocalizedStringKey(option.title)).tag(option)
          }
        }.pickerStyle(.menu).labelsHidden().font(.system(size: caption + 1)).frame(minHeight: 44)
          .accessibilityIdentifier("library.filter")
      }
      if library.authorizationStatus == .limited {
        Text("apple_photos_limited_note").font(.system(size: caption)).foregroundStyle(DuckColors.textSecondary)
          .accessibilityIdentifier("library.limited_scope")
      }
    }.padding(.horizontal, 20).padding(.vertical, 4)
  }
}
/// Use the system scroll-edge registration for the fixed action. A solid,
/// full-width background would paint the entire tab safe area opaque.
private struct IOSPreviewItem: Identifiable {
  let asset: PHAsset
  var id: String { asset.localIdentifier }
}

/// Browsing is separate from backup preparation: only locally available media
/// is requested here, and requests/playback are cancelled on dismissal.
private struct IOSPhotoPreview: View {
  let asset: PHAsset
  @Environment(\.dismiss) private var dismiss
  @State private var image: UIImage?
  @State private var livePhoto: PHLivePhoto?
  @State private var player: AVPlayer?
  @State private var unavailable = false
  @State private var requests: [PHImageRequestID] = []
  @State private var active = false
  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        if let player { VideoPlayer(player: player) }
        else if let livePhoto { IOSLivePhotoPreview(photo: livePhoto) }
        else if let image { Image(uiImage: image).resizable().scaledToFit() }
        else if !unavailable { Text("library_loading").foregroundStyle(DuckColors.textSecondary) }
        if unavailable { Text("library_preview_unavailable").font(.callout).padding().foregroundStyle(DuckColors.textSecondary) }
      }.frame(maxWidth: .infinity, maxHeight: .infinity).background(DuckColors.canvas)
        .navigationTitle("library_preview").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
          Button("settings_done") { dismiss() }.accessibilityIdentifier("library.preview.close")
        } }
        .onAppear { load() }
        .onDisappear {
          active = false
          requests.forEach { PHImageManager.default().cancelImageRequest($0) }
          requests.removeAll(); player?.pause(); player = nil
        }
    }
  }
  private func load() {
    guard !active else { return }
    active = true
    let size = CGSize(width: 1600, height: 1600)
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = false
    options.deliveryMode = .highQualityFormat
    requests.append(PHImageManager.default().requestImage(for: asset, targetSize: size,
      contentMode: .aspectFit, options: options) { result, _ in
      Task { @MainActor in
        guard active else { return }
        image = result
        // Video/Live Photo requests own their full-media availability. A
        // poster callback must not overwrite a later playback result.
        if asset.mediaType != .video && !asset.mediaSubtypes.contains(.photoLive) {
          unavailable = result == nil
        }
      }
    })
    if asset.mediaType == .video {
      let options = PHVideoRequestOptions()
      options.isNetworkAccessAllowed = false
      requests.append(PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
        Task { @MainActor in
          guard active else { return }
          if let item { player = AVPlayer(playerItem: item); unavailable = false }
          else { unavailable = true }
        }
      })
    } else if asset.mediaSubtypes.contains(.photoLive) {
      let options = PHLivePhotoRequestOptions()
      options.isNetworkAccessAllowed = false
      options.deliveryMode = .highQualityFormat
      requests.append(PHImageManager.default().requestLivePhoto(for: asset, targetSize: size,
        contentMode: .aspectFit, options: options) { photo, _ in
        Task { @MainActor in
          guard active else { return }
          livePhoto = photo
          unavailable = photo == nil
        }
      })
    }
  }
}
private struct IOSLivePhotoPreview: UIViewRepresentable {
  let photo: PHLivePhoto
  func makeUIView(context: Context) -> PHLivePhotoView {
    let view = PHLivePhotoView(); view.contentMode = .scaleAspectFit
    view.livePhoto = photo // Native press-to-play gesture remains available.
    return view
  }
  func updateUIView(_ view: PHLivePhotoView, context: Context) { view.livePhoto = photo }
  static func dismantleUIView(_ view: PHLivePhotoView, coordinator: ()) { view.stopPlayback() }
}

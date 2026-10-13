import AppKit
import Photos
import SwiftUI

struct MacLibraryGrid: NSViewRepresentable {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var networkPolicy = PreviewNetworkPolicy.shared
  var preparationRevision: String = ""
  var queueRevision: Int64
  var receiverID: String?
  var itemSize: CGFloat
  var selecting = true
  var preview: (PHAsset) -> Void = { _ in }
  var enterSelection: () -> Void = {}
  var resize: (CGFloat) -> Void = { _ in }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let layout = LibraryTimelineLayout(library: library, mode: library.viewMode, target: itemSize)
    let collection = LibraryCollectionView()
    collection.collectionViewLayout = layout
    collection.autoresizingMask = [.width]
    collection.backgroundColors = [.clear]
    collection.isSelectable = selecting
    collection.allowsMultipleSelection = true
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(TimelineDateHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    collection.dataSource = context.coordinator
    collection.delegate = context.coordinator
    collection.toggleSelection = { [weak coordinator = context.coordinator] path in
      coordinator?.toggleSelection(at: path)
    }
    collection.enterSelection = { [weak coordinator = context.coordinator] path in coordinator?.beginSelection(at: path) }
    collection.preview = { [weak coordinator = context.coordinator] path in
      guard let coordinator, let asset = coordinator.parent.library.asset(at: path.item) else { return }
      coordinator.parent.preview(asset)
    }
    let press = NSPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
    press.minimumPressDuration = 0.4
    press.delaysPrimaryMouseButtonEvents = true
    collection.addGestureRecognizer(press)
    let magnify = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.magnify(_:)))
    collection.addGestureRecognizer(magnify)
    let scroll = LibraryScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.documentView = collection
    scroll.contentView.postsBoundsChangedNotifications = true
    context.coordinator.collection = collection
    context.coordinator.observer = NotificationCenter.default.addObserver(
      forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
    ) { [weak coordinator = context.coordinator] _ in
      Task { @MainActor in coordinator?.scrolled() }
    }
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let c = context.coordinator
    c.parent = self
    guard let collection = c.collection,
      let layout = collection.collectionViewLayout as? LibraryTimelineLayout
    else { return }
    collection.isSelectable = selecting
    for path in collection.indexPathsForVisibleItems() {
      (collection.item(at: path) as? PhotoCell)?.setSelectionVisible(selecting)
    }
    if !c.magnifying && (layout.target != itemSize || layout.mode != library.viewMode),
      c.animationTarget?.0 != library.viewMode || c.animationTarget?.1 != itemSize {
      c.animateLayout(mode: library.viewMode, target: itemSize)
    }
    if c.generation != library.generation {
      let sameFilter = (c.filter == nil || c.filter == library.filter)
        && (c.scrollResetGeneration == nil || c.scrollResetGeneration == library.scrollResetGeneration)
      if sameFilter, c.generation >= 0 { c.rememberScroll() }
      let offset = sameFilter ? library.scrollOffset : .zero
      let anchor = sameFilter ? library.scrollAnchorID : nil
      let inset = library.scrollAnchorInset
      c.restoring = true
      c.filter = library.filter
      c.scrollResetGeneration = library.scrollResetGeneration
      c.generation = library.generation
      c.count = library.loaded
      c.applyingSelection = true
      c.appliedSelection = nil
      collection.reloadData()
      (scroll as? LibraryScrollView)?.restoreScroll = { [weak c] scroll in
        guard let c, let collection = c.collection,
          let layout = collection.collectionViewLayout else { return }
        collection.layoutSubtreeIfNeeded()
        var target = offset
        if let index = library.index(of: anchor), index < library.loaded {
          if let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame {
            target.y = frame.minY + inset
          }
        }
        let maximum = max(0, collection.frame.height - scroll.contentView.bounds.height)
        target.y = min(maximum, max(0, target.y))
        scroll.contentView.scroll(to: target)
        scroll.reflectScrolledClipView(scroll.contentView)
        c.restoring = false
        c.applyingSelection = false
        c.scrolled()
      }
      scroll.needsLayout = true
      scroll.layoutSubtreeIfNeeded()
    } else if c.count < library.loaded {
      let old = c.count
      c.count = library.loaded
      c.appliedSelection = nil
      collection.insertItems(at: Set((old..<c.count).map { IndexPath(item: $0, section: 0) }))
    }
    if c.networkAllowed != networkPolicy.allowed {
      c.networkAllowed = networkPolicy.allowed; c.refreshVisibleImages()
    }
    if c.contentGeneration != library.contentGeneration {
      c.contentGeneration = library.contentGeneration
      c.refreshVisibleImages()
      c.scrolled()
    }
    if c.preparationRevision != preparationRevision {
      c.preparationRevision = preparationRevision
      c.scrolled()
    }
    if c.statusRevision != queueRevision || c.receiverID != receiverID {
      c.statusRevision = queueRevision
      c.receiverID = receiverID
      c.scrolled()
    }
    if c.appliedSelection != library.selection {
      c.applyingSelection = true
      collection.selectionIndexPaths = library.selectedIndexPaths()
      c.appliedSelection = library.selection
      c.applyingSelection = false
    }
  }
  static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
    coordinator.stopLayoutAnimation()
    coordinator.rememberScroll()
    coordinator.refresh.cancel()
    if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
    coordinator.parent.library.thumbnails.clear()
  }
  @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate
  {
    var networkAllowed = false
    var magnifying = false
    var animationTarget: (LibraryViewMode, CGFloat)?
    private var layoutTimer: Timer?
    private var layoutStarted: CFTimeInterval = 0
    private var anchor: Int?
    private var anchorFraction: CGFloat = 0
    private var anchorY: CGFloat = 0
    private var keepsTop = false
    private var magnifyBase: CGFloat = 140
    private var magnifyMode: LibraryViewMode = .all
    var parent: MacLibraryGrid
    weak var collection: NSCollectionView?
    var observer: NSObjectProtocol?
    let refresh = LibraryRefreshScheduler()
    var restoring = false
    var applyingSelection = false
    var appliedSelection: Set<String>?
    var count = 0
    var generation = -1
    var filter: LibraryFilter?
    var scrollResetGeneration: Int?
    var preparationRevision = ""
    var contentGeneration = -1
    var statusRevision: Int64 = -2
    var receiverID: String?
    var visibleIdentifiers: [IndexPath: String] = [:]
    init(_ parent: MacLibraryGrid) { self.parent = parent }
    func stopLayoutAnimation() { layoutTimer?.invalidate(); layoutTimer = nil; animationTarget = nil; restoring = false }
    private func captureAnchor(_ point: CGPoint? = nil) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout, let scroll = collection.enclosingScrollView else { return }
      let wasAtTop = point == nil && scroll.contentView.bounds.minY <= 1
      let point = point ?? CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
      let paths = collection.indexPathsForVisibleItems()
      anchor = paths.min { a,b in
        let ra = layout.frame(at: a.item), rb = layout.frame(at: b.item)
        return hypot(ra.midX-point.x,ra.midY-point.y) < hypot(rb.midX-point.x,rb.midY-point.y)
      }?.item
      if let anchor {
        let frame = layout.frame(at: anchor)
        anchorFraction = min(1,max(0,(point.y-frame.minY)/max(1,frame.height)))
        anchorY = point.y-scroll.contentView.bounds.minY
      }
      keepsTop = wasAtTop
    }
    private func positionAnchor() {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout, let scroll = collection.enclosingScrollView else { return }
      collection.needsLayout = true; collection.layoutSubtreeIfNeeded()
      if let anchor {
        let frame = layout.frame(at: anchor), maximum = max(0,layout.collectionViewContentSize.height-scroll.contentView.bounds.height)
        let y = frame.minY+anchorFraction*frame.height-anchorY
        scroll.contentView.scroll(to: CGPoint(x: 0,y: keepsTop ? 0 : min(maximum,max(0,y)))); scroll.reflectScrolledClipView(scroll.contentView)
      }
      for path in collection.indexPathsForVisibleSupplementaryElements(ofKind: LibraryTimelineLayout.headerKind) {
        (collection.supplementaryView(forElementKind: LibraryTimelineLayout.headerKind, at: path) as? TimelineDateHeader)?.setTitle(layout.title(at: path.item))
      }
    }
    func animateLayout(mode: LibraryViewMode, target: CGFloat, retainAnchor: Bool = false) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      stopLayoutAnimation(); if !retainAnchor { captureAnchor() }; restoring = true
      animationTarget = (mode,target); layout.beginMorph(mode: mode, columns: layout.columns(for: target, mode: mode))
      if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { layout.setProgress(1); finishLayoutAnimation(); return }
      layoutStarted = CACurrentMediaTime()
      let timer = Timer(timeInterval: 1/60, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.layoutFrame() }
      }
      RunLoop.main.add(timer, forMode: .common); layoutTimer = timer
    }
    private func layoutFrame() {
      guard let layout = collection?.collectionViewLayout as? LibraryTimelineLayout else { stopLayoutAnimation(); return }
      let value = CGFloat(min(1,(CACurrentMediaTime()-layoutStarted)/0.26))
      layout.setProgress(LibraryMotion.easeOut(value)); positionAnchor()
      if value >= 1 { finishLayoutAnimation() }
    }
    private func finishLayoutAnimation() {
      guard let layout = collection?.collectionViewLayout as? LibraryTimelineLayout, let target = animationTarget else { return }
      layout.target = target.1; layout.adopt(mode: target.0, columns: layout.columns(for: target.1,mode: target.0)); positionAnchor()
      stopLayoutAnimation(); refreshVisibleImages(); scrolled()
    }
    @objc func magnify(_ recognizer: NSMagnificationGestureRecognizer) {
      guard !parent.selecting, let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      switch recognizer.state {
      case .began:
        stopLayoutAnimation(); magnifying = true; restoring = true; magnifyBase = layout.target; magnifyMode = layout.mode
        captureAnchor(recognizer.location(in: collection)); keepsTop = false
      case .changed:
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let target = min(240,max(90,magnifyBase*(1+recognizer.magnification)))
        let density = ((collection.enclosingScrollView?.contentSize.width ?? collection.bounds.width)-48)/(target+8)
        layout.updateDensity(density, startMode: magnifyMode); positionAnchor()
      case .ended:
        let target = min(240,max(90,magnifyBase*(1+recognizer.magnification)))
        let mode: LibraryViewMode = target < 110 ? .months : (magnifyMode == .all ? .all : .days)
        magnifying = false; parent.resize(target); parent.library.viewMode = mode
        animateLayout(mode: mode, target: target, retainAnchor: true)
      case .cancelled, .failed:
        magnifying = false; animateLayout(mode: magnifyMode,target: magnifyBase,retainAnchor: true)
      default: break
      }
    }
    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> NSView {
      let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: .init("timeline"), for: indexPath) as! TimelineDateHeader
      header.setTitle((collectionView.collectionViewLayout as? LibraryTimelineLayout)?.title(at: indexPath.item) ?? "")
      return header
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
      -> Int
    { count }
    func collectionView(
      _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
      let item =
        collectionView.makeItem(withIdentifier: .init("photo"), for: indexPath) as! PhotoCell
      if let asset = parent.library.asset(at: indexPath.item) {
        item.setSelectionVisible(parent.selecting)
        item.configure(
          asset, pipeline: parent.library.thumbnails,
          pixels: parent.itemSize * (collectionView.window?.backingScaleFactor ?? 2),
          identifier: parent.library.identifier(at: indexPath.item))
        visibleIdentifiers[indexPath] = asset.localIdentifier
      }
      return item
    }
    func collectionView(
      _ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
      forRepresentedObjectAt indexPath: IndexPath
    ) {
      if let cell = item as? PhotoCell, let asset = parent.library.asset(at: indexPath.item) {
        cell.setSelectionVisible(parent.selecting)
        cell.configure(
          asset, pipeline: parent.library.thumbnails,
          pixels: parent.itemSize * (collectionView.window?.backingScaleFactor ?? 2),
          identifier: parent.library.identifier(at: indexPath.item))
        visibleIdentifiers[indexPath] = asset.localIdentifier
      }
      scrolled()
    }
    func collectionView(
      _ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
      forRepresentedObjectAt indexPath: IndexPath
    ) {
      (item as? PhotoCell)?.cancel()
      visibleIdentifiers.removeValue(forKey: indexPath)
    }
    func collectionView(
      _ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>
    ) { changeSelection(indexPaths, selected: true) }
    func collectionView(
      _ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>
    ) { changeSelection(indexPaths, selected: false) }
    private func changeSelection(_ paths: Set<IndexPath>, selected: Bool) {
      guard !applyingSelection, parent.selecting else { return }
      let ids = paths.compactMap { parent.library.identifier(at: $0.item) }
      if selected { parent.library.selection.formUnion(ids) }
      else { parent.library.selection.subtract(ids) }
      appliedSelection = parent.library.selection
    }
    @objc func longPress(_ recognizer: NSPressGestureRecognizer) {
      guard recognizer.state == .began, !parent.selecting, let collection,
        let path = collection.indexPathForItem(at: recognizer.location(in: collection)) else { return }
      beginSelection(at: path)
    }
    func beginSelection(at path: IndexPath) {
      guard let collection, let id = parent.library.identifier(at: path.item) else { return }
      parent.library.selection.insert(id)
      applyingSelection = true
      collection.isSelectable = true
      collection.selectionIndexPaths = parent.library.selectedIndexPaths()
      appliedSelection = parent.library.selection
      applyingSelection = false
      parent.enterSelection()
    }
    func toggleSelection(at path: IndexPath) {
      guard parent.selecting, let collection, let id = parent.library.identifier(at: path.item) else { return }
      if parent.library.selection.contains(id) { parent.library.selection.remove(id) }
      else { parent.library.selection.insert(id) }
      applyingSelection = true
      collection.selectionIndexPaths = parent.library.selectedIndexPaths()
      appliedSelection = parent.library.selection
      applyingSelection = false
    }
    func refreshVisibleImages() {
      guard let collection else { return }
      for path in collection.indexPathsForVisibleItems() {
        if let item = collection.item(at: path) as? PhotoCell,
          let asset = parent.library.asset(at: path.item)
        {
          item.configure(
            asset, pipeline: parent.library.thumbnails,
            pixels: parent.itemSize * (collection.window?.backingScaleFactor ?? 2),
            identifier: parent.library.identifier(at: path.item))
        }
      }
    }
    func scrolled() {
      guard !restoring else { return }
      if generation == parent.library.generation { rememberScroll() }
      refresh.schedule { [weak self] in
        guard let self, !Task.isCancelled, let collection = self.collection else { return }
        let parent = self.parent
        self.rememberScroll()
        let generation = parent.library.generation
        let receiverID = parent.receiverID
        let revision = parent.queueRevision
        let preparation = parent.preparationRevision
        let paths = collection.indexPathsForVisibleItems().sorted()
        guard let first = paths.first?.item, let last = paths.last?.item else { return }
        let identities = Dictionary(uniqueKeysWithValues: paths.compactMap { path in
          parent.library.asset(at: path.item).map { (path, $0.localIdentifier) }
        })
        if last >= parent.library.loaded - 48 { parent.library.loadMore() }
        let range = max(0, first - 24)..<min(parent.library.loaded, last + 49)
        let assets = range.compactMap { parent.library.asset(at: $0) }
        parent.library.thumbnails.preheat(
          assets, pixels: parent.itemSize * (collection.window?.backingScaleFactor ?? 2))
        let visible = paths.compactMap { parent.library.asset(at: $0.item) }
        let groups = await parent.library.visibleGroups(visible)
        guard !Task.isCancelled, generation == self.parent.library.generation else { return }
        guard let states = await librarySourceStates(groups, receiver: receiverID) else { return }
        guard !Task.isCancelled, generation == self.parent.library.generation,
          receiverID == self.parent.receiverID, revision == self.parent.queueRevision,
          preparation == self.parent.preparationRevision else { return }
        for path in paths {
          if let item = collection.item(at: path) as? PhotoCell {
            guard item.assetID == identities[path] else { continue }
            let group = groups[item.assetID ?? ""]
            let burst = parent.library.asset(at: path.item)?.burstIdentifier != nil
            item.setGroup(count: burst ? group?.count : nil, state: group?.state(states))
          }
        }
      }
    }
    func rememberScroll() {
      guard !restoring, parent.library.authorized, filter == parent.library.filter,
        scrollResetGeneration == parent.library.scrollResetGeneration, let collection,
        let scroll = collection.enclosingScrollView,
        let top = collection.indexPathsForVisibleItems().sorted().first,
        let id = (collection.item(at: top) as? PhotoCell)?.presentationID,
        let frame = collection.collectionViewLayout?.layoutAttributesForItem(at: top)?.frame,
        frame.intersects(collection.visibleRect)
      else { return }
      parent.library.scrollOffset = scroll.contentView.bounds.origin
      parent.library.scrollAnchorID = id
      parent.library.scrollAnchorInset = scroll.contentView.bounds.origin.y - frame.minY
    }
  }
}

@MainActor private final class LibraryCollectionView: NSCollectionView {
  var toggleSelection: ((IndexPath) -> Void)?
  var preview: ((IndexPath) -> Void)?
  var enterSelection: ((IndexPath) -> Void)?

  override func mouseDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
    let point = convert(event.locationInWindow, from: nil)
    if !isSelectable, let path = indexPathForItem(at: point) {
      if modifiers.contains(.command) || modifiers.contains(.shift) { enterSelection?(path) }
      else { preview?(path) }
      return
    }
    if modifiers.isEmpty, let path = indexPathForItem(at: point) {
      toggleSelection?(path)
      return
    }
    super.mouseDown(with: event)
  }
}

@MainActor final class PhotoCell: NSCollectionViewItem {
  private var pipeline: ThumbnailPipeline?
  private var request: PHImageRequestID = PHInvalidImageRequestID
  private var token = UUID()
  private var imageKey = ""
  private(set) var assetID: String?
  private(set) var presentationID: String?
  private let photoLayer = CALayer()
  private let media = NSImageView()
  private let status = NSImageView()
  private let cloud = NSImageView()
  private let selectionMark = NSImageView()
  private var selectionVisible = true
  private var statusState: String?
  private let burstCount = NSTextField(labelWithString: "")
  private let duration = NSTextField(labelWithString: "")
  private var groupDescription = ""
  override func loadView() {
    view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = 3
    photoLayer.contentsGravity = .resizeAspectFill
    photoLayer.masksToBounds = true
    view.layer?.addSublayer(photoLayer)
    for badge in [media, status, cloud, selectionMark] {
      badge.wantsLayer = true
      badge.contentTintColor = .white
      badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
      badge.layer?.cornerRadius = 12
      badge.imageScaling = .scaleProportionallyUpOrDown
      view.addSubview(badge)
    }
    burstCount.textColor = .white
    burstCount.backgroundColor = .black.withAlphaComponent(0.45)
    burstCount.drawsBackground = true
    burstCount.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    burstCount.alignment = .center
    burstCount.wantsLayer = true
    burstCount.layer?.cornerRadius = 4
    burstCount.isHidden = true
    view.addSubview(burstCount)
    duration.textColor = .white
    duration.backgroundColor = NSColor.black.withAlphaComponent(0.55)
    duration.drawsBackground = true
    duration.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    duration.alignment = .center
    duration.wantsLayer = true
    duration.layer?.cornerRadius = 5
    duration.isHidden = true
    view.addSubview(duration)
    cloud.isHidden = true
    media.isHidden = true
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.image)
  }
  override func viewDidLayout() {
    super.viewDidLayout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    photoLayer.frame = view.bounds
    CATransaction.commit()
    media.frame = NSRect(x: 8, y: view.bounds.height - 32, width: 24, height: 24)
    burstCount.frame = NSRect(x: 36, y: view.bounds.height - 30, width: 42, height: 20)
    let durationWidth = min(view.bounds.width - 16, max(42, duration.intrinsicContentSize.width + 12))
    duration.frame = NSRect(x: view.bounds.width - durationWidth - 8,
      y: view.bounds.height - 30, width: durationWidth, height: 20)
    cloud.frame = NSRect(x: 8, y: 8, width: 24, height: 24)
    status.frame = NSRect(x: view.bounds.width - 32, y: 8, width: 24, height: 24)
    selectionMark.frame = status.frame
  }
  override var isSelected: Bool {
    didSet {
      view.layer?.borderWidth = selectionVisible && isSelected ? 3 : 0
      view.layer?.borderColor = NSColor.controlAccentColor.cgColor
      updateSelectionMark()
    }
  }
  func configure(_ asset: PHAsset, pipeline: ThumbnailPipeline, pixels: CGFloat, identifier: String? = nil) {
    presentationID = identifier ?? asset.localIdentifier
    let key =
      "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))|\(pipeline.size(pixels).width)|\(PreviewNetworkPolicy.shared.allowed)|\(pipeline.epoch)"
    guard imageKey != key else { return }
    cancel()
    self.pipeline = pipeline
    assetID = asset.localIdentifier
    imageKey = key
    let current = token
    photoLayer.contents = nil
    cloud.isHidden = true
    let symbol =
      asset.burstIdentifier != nil ? "square.stack" : asset.mediaSubtypes.contains(.photoLive)
      ? "livephoto" : asset.mediaType == .video ? "video.fill" : nil
    media.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    media.isHidden = symbol == nil
    duration.stringValue = asset.mediaType == .video ? videoDurationLabel(asset.duration) : ""
    duration.isHidden = asset.mediaType != .video
    view.needsLayout = true
    view.setAccessibilityLabel(
      (asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "") + " "
        + NSLocalizedString(
          symbol == "square.stack" ? "library_filter_burst" : symbol == "livephoto"
            ? "library_filter_motion"
            : symbol == nil ? "library_filter_photo" : "library_filter_video", comment: ""))
    setGroup(count: nil, state: nil)
    request = pipeline.request(asset, pixels: pixels) { [weak self] image, inCloud in
      guard let self, self.token == current else { return }
      if let image {
        self.photoLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
      }
      self.cloud.image = NSImage(systemSymbolName: "icloud", accessibilityDescription: nil)
      self.cloud.isHidden = image != nil || !inCloud
    }
  }
  func setGroup(count: Int?, state: String?) {
    if count != nil {
      media.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)
      media.isHidden = false
    }
    burstCount.stringValue = count.map(String.init) ?? ""
    burstCount.isHidden = count == nil
    groupDescription = count.map { String(format: NSLocalizedString("library_burst_count", comment: ""), $0) + ". " } ?? ""
    burstCount.toolTip = NSLocalizedString("library_burst_selection", comment: "")
    setState(state)
  }
  func setState(_ state: String?) {
    statusState = state
    status.image = NSImage(systemSymbolName: taskSymbol(state), accessibilityDescription: nil)
    status.contentTintColor = state == "failed" ? .systemOrange : .white
    status.toolTip = groupDescription + NSLocalizedString(
      state == "received" ? "state_received_detail" : state.map { "state_" + $0 } ?? "state_not_queued", comment: "")
    view.setAccessibilityValue(status.toolTip)
    status.isHidden = selectionVisible || state == nil
  }
  func setSelectionVisible(_ value: Bool) {
    selectionVisible = value
    view.layer?.borderWidth = value && isSelected ? 3 : 0
    status.isHidden = value || statusState == nil
    updateSelectionMark()
  }
  private func updateSelectionMark() {
    selectionMark.isHidden = !selectionVisible
    selectionMark.image = NSImage(systemSymbolName: isSelected ? "checkmark.circle.fill" : "circle", accessibilityDescription: nil)
    selectionMark.contentTintColor = isSelected ? .controlAccentColor : .white
  }
  func cancel() {
    pipeline?.cancel(request)
    request = PHInvalidImageRequestID
    token = UUID()
    imageKey = ""
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    cancel()
    photoLayer.contents = nil
    assetID = nil
    presentationID = nil
  }
}

@MainActor private final class LibraryScrollView: NSScrollView {
  var restoreScroll: ((LibraryScrollView) -> Void)?
  override func layout() {
    super.layout()
    if let collection = documentView as? NSCollectionView,
      collection.frame.width != contentSize.width
    {
      collection.setFrameSize(NSSize(width: contentSize.width, height: collection.frame.height))
      collection.collectionViewLayout?.invalidateLayout()
    }
    if contentSize.width > 0, contentSize.height > 0, let restore = restoreScroll {
      restoreScroll = nil
      restore(self)
    }
  }
}

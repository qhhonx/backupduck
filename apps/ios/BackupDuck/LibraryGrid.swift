import Photos
import AVKit
import PhotosUI
import SwiftUI
import UIKit

struct IOSLibraryGrid: UIViewRepresentable {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var networkPolicy = PreviewNetworkPolicy.shared
  var preparationRevision: String = ""
  var queueRevision: Int64
  var receiverID: String?
  @ObservedObject var backupModel: BackupModel = BackupModel.shared
  var showSupplementaryContent = false
  var selectionEnabled = true
  var onPreview: (Int, CGRect) -> Void = { _, _ in }
  var onBeginSelection: (Int) -> Void = { _ in }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UICollectionView {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 3
    layout.minimumInteritemSpacing = 3
    layout.sectionInset = showSupplementaryContent
      ? UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
      : UIEdgeInsets(top: 4, left: 8, bottom: 16, right: 8)
    let view = LibraryCollectionView(frame: .zero, collectionViewLayout: showSupplementaryContent ? layout : LibraryTimelineLayout(library: library, mode: library.viewMode))
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
    view.register(TimelineDateHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withReuseIdentifier: "timeline")
    view.dataSource = context.coordinator
    view.delegate = context.coordinator
    let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
    press.minimumPressDuration = 0.4
    press.cancelsTouchesInView = true
    view.addGestureRecognizer(press)
    if !showSupplementaryContent {
      let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
      view.addGestureRecognizer(pinch)
    }
    context.coordinator.collection = view
    return view
  }
  func updateUIView(_ view: UICollectionView, context: Context) {
    let c = context.coordinator
    c.parent = self
    if c.generation != library.generation {
      c.stopDrag(revert: true)
      c.stopTimelineMotion()
    }
    if c.generation < 0 { c.viewMode = library.viewMode }
    c.updateSupplementaryContent()
    if c.generation >= 0 && c.viewMode != library.viewMode && !c.timelineAnimating && !showSupplementaryContent {
      c.changeTimelineMode(library.viewMode)
    }
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
    if c.networkAllowed != networkPolicy.allowed {
      c.networkAllowed = networkPolicy.allowed
      for path in view.indexPathsForVisibleItems { if let cell = view.cellForItem(at: path) as? PhotoCell { c.configure(cell, path: path) } }
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
    coordinator.stopTimelineMotion()
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
    var viewMode: LibraryViewMode = .all
    var timelineAnimating = false
    private var timelineLink: CADisplayLink?
    private var timelineStarted: CFTimeInterval = 0
    private var timelineDuration: CFTimeInterval = 0.24
    private var timelineTarget: (LibraryViewMode, Int)?
    private var timelineAnchor: Int?
    private var timelineAnchorFraction: CGFloat = 0
    private var timelineAnchorY: CGFloat = 0
    private var timelineKeepsTop = false
    private var pinchDensity: CGFloat = 3
    private var pinchMode: LibraryViewMode = .all
    var networkAllowed = false
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
    func changeTimelineMode(_ mode: LibraryViewMode) {
      guard let collection else { return }
      stopDrag(revert: true); stopTimelineMotion()
      captureTimelineAnchor(at: CGPoint(x: collection.bounds.midX, y: collection.bounds.midY), keepsTop: true)
      settleTimeline(mode: mode, columns: mode == .months ? 7 : 3, duration: 0.3)
    }
    func stopTimelineMotion() { timelineLink?.invalidate(); timelineLink = nil; timelineAnimating = false }
    private func captureTimelineAnchor(at point: CGPoint, keepsTop: Bool = false) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      layout.prepare()
      let path = collection.indexPathForItem(at: point) ?? collection.indexPathsForVisibleItems.min { a,b in
        let ra = layout.frame(at: a.item), rb = layout.frame(at: b.item)
        return hypot(ra.midX-point.x,ra.midY-point.y) < hypot(rb.midX-point.x,rb.midY-point.y)
      }
      timelineAnchor = path?.item
      if let path {
        let frame = layout.frame(at: path.item)
        timelineAnchorFraction = min(1,max(0,(point.y-frame.minY)/max(1,frame.height)))
        timelineAnchorY = point.y-collection.contentOffset.y
      }
      timelineKeepsTop = keepsTop && collection.contentOffset.y <= -collection.adjustedContentInset.top+1
    }
    private func positionTimelineAnchor() {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      layout.prepare()
      if let timelineAnchor {
        let frame = layout.frame(at: timelineAnchor)
        let maximum = max(-collection.adjustedContentInset.top, layout.collectionViewContentSize.height-collection.bounds.height+collection.adjustedContentInset.bottom)
        let y = frame.minY+timelineAnchorFraction*frame.height-timelineAnchorY
        collection.setContentOffset(CGPoint(x: 0, y: timelineKeepsTop ? -collection.adjustedContentInset.top : min(maximum,max(-collection.adjustedContentInset.top,y))), animated: false)
      }
      collection.layoutIfNeeded()
      for path in collection.indexPathsForVisibleSupplementaryElements(ofKind: LibraryTimelineLayout.headerKind) {
        (collection.supplementaryView(forElementKind: LibraryTimelineLayout.headerKind, at: path) as? TimelineDateHeader)?.setTitle(layout.title(at: path.item))
      }
    }
    private func settleTimeline(mode: LibraryViewMode, columns: Int, duration: CFTimeInterval) {
      guard let layout = collection?.collectionViewLayout as? LibraryTimelineLayout else { return }
      stopTimelineMotion(); timelineAnimating = true; timelineTarget = (mode,columns)
      layout.beginMorph(mode: mode, columns: columns)
      if UIAccessibility.isReduceMotionEnabled { layout.setProgress(1); finishTimeline(); return }
      timelineStarted = CACurrentMediaTime(); timelineDuration = duration
      let link = CADisplayLink(target: self, selector: #selector(timelineFrame(_:)))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
      link.add(to: .main, forMode: .common); timelineLink = link
    }
    @objc private func timelineFrame(_ link: CADisplayLink) {
      guard let layout = collection?.collectionViewLayout as? LibraryTimelineLayout else { stopTimelineMotion(); return }
      let value = CGFloat(min(1,(CACurrentMediaTime()-timelineStarted)/timelineDuration))
      layout.setProgress(LibraryMotion.easeOut(value)); positionTimelineAnchor()
      if value >= 1 { finishTimeline() }
    }
    private func finishTimeline() {
      guard let layout = collection?.collectionViewLayout as? LibraryTimelineLayout, let target = timelineTarget else { stopTimelineMotion(); return }
      layout.adopt(mode: target.0, columns: target.1); positionTimelineAnchor()
      viewMode = target.0; parent.library.phoneColumns = target.1; parent.library.viewMode = target.0
      timelineTarget = nil; stopTimelineMotion(); refreshTimelineImages()
    }
    private func refreshTimelineImages() {
      guard let collection else { return }
      for path in collection.indexPathsForVisibleItems { if let cell = collection.cellForItem(at: path) as? PhotoCell { configure(cell, path: path) } }
      positionTimelineAnchor(); rememberScroll(); scrolled()
    }
    @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
      guard let collection, !parent.selectionEnabled, let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      switch recognizer.state {
      case .began:
        stopDrag(revert: true); stopTimelineMotion(); timelineAnimating = true
        pinchDensity = layout.density; pinchMode = viewMode
        captureTimelineAnchor(at: recognizer.location(in: collection))
      case .changed:
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        layout.updateDensity(pinchDensity/max(0.15,recognizer.scale), startMode: pinchMode)
        positionTimelineAnchor()
      case .ended:
        let desired = min(9,max(3,pinchDensity/max(0.15,recognizer.scale)))
        let target = [3,5,7,9].min { abs(CGFloat($0)-desired) < abs(CGFloat($1)-desired) } ?? 3
        let mode: LibraryViewMode = target >= 5 ? .months : (pinchMode == .all ? .all : .days)
        settleTimeline(mode: mode, columns: target, duration: 0.24)
      case .cancelled, .failed:
        settleTimeline(mode: pinchMode, columns: Int(pinchDensity.rounded()), duration: 0.2)
      default: break
      }
    }
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
      if kind == LibraryTimelineLayout.headerKind {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "timeline", for: indexPath) as! TimelineDateHeader
        header.setTitle((collectionView.collectionViewLayout as? LibraryTimelineLayout)?.title(at: indexPath.item) ?? "")
        return header
      }
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
        cell.configure(asset, pipeline: parent.library.thumbnails, pixels: max(128, cell.bounds.width * (collection?.traitCollection.displayScale ?? UIScreen.main.scale)),
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
      if revert, dragGeneration == parent.library.generation, parent.library.authorized, let snapshot = dragSelection { parent.library.selection = snapshot.baseline }
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
      if !parent.selectionEnabled { parent.onPreview(indexPath.item, collectionView.convert(collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero, to: nil)); return false }
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
      guard !timelineAnimating else { return }
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
        let lower = min(parent.library.loaded, max(0, first - 18))
        let upper = max(lower, min(parent.library.loaded, last + 37))
        let range = lower..<upper
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
    duration.adjustsFontSizeToFitWidth = true
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
    let badge: CGFloat = bounds.width < 100 ? 16 : 22
    media.isHidden = bounds.width < 72 || media.image == nil
    duration.isHidden = bounds.width < 100 || duration.text == nil
    burstCount.isHidden = bounds.width < 100 || burstCount.text == nil
    status.isHidden = showsSelection || bounds.width < 72 || status.image == nil
    cloud.isHidden = bounds.width < 72 || photo.image != nil || cloud.image == nil
    media.frame = CGRect(x: 6, y: 6, width: badge, height: badge)
    burstCount.frame = CGRect(x: 31, y: 6, width: 42, height: 22)
    let durationX = 6 + badge + 4
    let durationWidth = max(1, min(bounds.width - durationX - 6, max(42, duration.intrinsicContentSize.width + 12)))
    duration.frame = CGRect(x: durationX, y: 6, width: durationWidth, height: badge)
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
    let next = asset.localIdentifier + PhotoLibraryModel.revision(asset) + "|\(Int(pixels))|\(PreviewNetworkPolicy.shared.allowed)|\(pipeline.epoch)"
    guard key != next else { return }
    let sameAsset = assetID == asset.localIdentifier
    cancel()
    self.pipeline = pipeline
    key = next
    assetID = asset.localIdentifier
    let expected = token
    if !sameAsset { photo.image = nil }
    cloud.isHidden = true
    let symbol =
      asset.burstIdentifier != nil ? "square.stack" : asset.mediaSubtypes.contains(.photoLive)
      ? "livephoto" : asset.mediaType == .video ? "video" : "photo"
    media.image = symbol == "photo" ? nil : UIImage(systemName: symbol)
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
      self.cloud.image = inCloud ? UIImage(systemName: "icloud") : nil
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
    status.image = state.map { UIImage(systemName: taskSymbol($0)) } ?? nil
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
            onPreview: { index, frame in
              if let asset = library.asset(at: index) {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { preview = IOSPreviewItem(asset: asset, frame: frame, poster: library.thumbnails.poster(for: asset)) }
              }
            }, onBeginSelection: { index in
              guard let id = library.identifier(at: index) else { return }
              library.selection.insert(id); selecting = true
            }).frame(maxWidth: 640).duckLibraryViewport()
        }
      }.background(DuckColors.canvas).foregroundStyle(DuckColors.text).toolbar(.hidden, for: .navigationBar).symbolVariant(.none)
      .task { await library.open() }
      .onAppear { library.refreshVisiblePreviews() }
      .onDisappear { library.thumbnails.clear() }
      .sheet(isPresented: $confirmSelectedBackup) { selectedBackupConfirmation }
      .fullScreenCover(item: $preview) { item in
        IOSPhotoPreview(item: item, library: library) {
          var transaction = Transaction(); transaction.disablesAnimations = true
          withTransaction(transaction) { preview = nil }
        }.presentationBackground(.clear)
      }

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
          .font(.caption).foregroundStyle(DuckColors.textSecondary).accessibilityIdentifier("library.count")
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
  private var viewMenu: some View {
    Menu {
      Picker("library_view_mode", selection: $library.viewMode) {
        ForEach(LibraryViewMode.allCases) { mode in Text(LocalizedStringKey(mode.title)).tag(mode) }
      }.pickerStyle(.inline)
    } label: {
      Image(systemName: "calendar").frame(width: 44, height: 44)
    }.buttonStyle(.plain).foregroundStyle(DuckColors.action)
      .accessibilityLabel(Text("library_view_mode"))
      .accessibilityValue(Text(LocalizedStringKey(library.viewMode.title)))
      .accessibilityIdentifier("library.view_mode")
  }
  @ViewBuilder private var libraryToolbar: some View {
    if textSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 4) {
        if selecting { selectionTitle } else { browsingTitle }
        HStack { Spacer(minLength: 0); if selecting { selectionActions } else { typeMenu; viewMenu } }
      }
    } else {
      HStack(spacing: 8) {
        if selecting { selectionTitle } else { browsingTitle }
        Spacer(minLength: 4)
        if selecting { selectionActions } else { typeMenu; viewMenu }
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
  let frame: CGRect
  let poster: UIImage?
  var id: String { asset.localIdentifier }
}

private struct IOSPhotoPreview: View {
  let item: IOSPreviewItem
  let close: () -> Void
  @StateObject private var session: MediaPreviewSession
  @ObservedObject private var policy = PreviewNetworkPolicy.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var chrome = true
  @State private var drawer: CGFloat = 0
  @State private var drawerStart: CGFloat = 0
  @State private var translation: CGFloat = 0
  @State private var flight = true
  @State private var progress: CGFloat = 0
  @State private var closing = false
  private var motion: Animation { reduceMotion ? .linear(duration: 0) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3) }
  init(item: IOSPreviewItem, library: PhotoLibraryModel, close: @escaping () -> Void) {
    self.item = item; self.close = close
    _session = StateObject(wrappedValue: MediaPreviewSession(asset: item.asset, library: library, poster: item.poster))
  }
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottom) {
        Color.black.opacity(progress).ignoresSafeArea()
        IOSMediaPager(session: session, tap: { withAnimation(motion) { chrome.toggle() } }, vertical: { state, value, predicted in
          vertical(state, value: value, predicted: predicted, height: geometry.size.height)
        })
          .frame(height: geometry.size.height * (1 - drawer))
          .frame(maxHeight: .infinity, alignment: .top)
          .offset(y: translation).scaleEffect(max(0.85, 1 - translation / max(1, geometry.size.height * 2)))
          .opacity(flight ? 0 : 1)
        if chrome && !flight && drawer < 0.15 {
          VStack {
            HStack {
              icon("chevron.left", title: "settings_done", identifier: "library.preview.close", action: dismissViewer)
              Spacer(minLength: 8)
              VStack(spacing: 3) {
                Text(session.current.asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? NSLocalizedString("library_preview", comment: "")).font(.subheadline.weight(.semibold))
                if let date = session.current.asset.creationDate { Text(date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.white.opacity(0.75)) }
              }.accessibilityIdentifier("library.preview.date")
              Spacer(minLength: 8)
              icon("info.circle", title: "apple_photo_detail", identifier: "library.preview.info") { session.fitMedia(); withAnimation(motion) { drawer = 0.45 } }
            }.padding(.horizontal, 12).padding(.top, 12)
              .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
            Spacer()
            HStack {
              icon("chevron.left", title: "preview_previous", identifier: "library.preview.previous") { move(-1) }
                .disabled(session.adjacent(to: session.current.asset, direction: -1) == nil || session.paging)
              Spacer()
              Group {
                if session.current.burstCount > 1 { BurstPreviewControls(preview: session.current, select: session.activate) }
                else { filmstrip }
              }.foregroundStyle(.white)
              Spacer()
              icon("chevron.right", title: "preview_next", identifier: "library.preview.next") { move(1) }
                .disabled(session.adjacent(to: session.current.asset, direction: 1) == nil || session.paging)
            }.padding(12).background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
          }.foregroundStyle(.white).opacity(max(0, 1 - translation / 160))
        }
        if drawer > 0 {
          VStack(spacing: 0) {
            HStack {
              Button { withAnimation(motion) { drawer = 0 } } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel(Text("preview_hide_info")).accessibilityIdentifier("preview.info.close")
              Spacer()
              Capsule().fill(DuckColors.textSecondary.opacity(0.5)).frame(width: 36, height: 4)
                .frame(width: 100,height: 44).contentShape(Rectangle())
                .gesture(DragGesture().onChanged { value in
                  if drawerStart == 0 { drawerStart = drawer }
                  drawer = min(0.8, max(0, drawerStart - value.translation.height / geometry.size.height))
                }.onEnded { value in
                  let projected = drawerStart - value.predictedEndTranslation.height / geometry.size.height
                  withAnimation(motion) { drawer = projected < 0.2 ? 0 : projected > 0.6 ? 0.75 : 0.45 }
                  drawerStart = 0
                })
              Spacer()
              Color.clear.frame(width: 44, height: 44)
            }
            ScrollView { PhotoMetadataPanel(preview: session.current).padding(.horizontal, 20).padding(.bottom, 24) }
          }.frame(height: geometry.size.height * drawer)
            .background(DuckColors.surface, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
            .foregroundStyle(DuckColors.text).tint(DuckColors.action)
            .accessibilityElement(children: .contain).accessibilityIdentifier("preview.info.drawer")
        }
        if flight, let image = session.current.image ?? item.poster {
          let fit = fitted(image.size, in: CGRect(origin: .zero, size: geometry.size))
          let origin = geometry.frame(in: .global).origin
          let source = item.frame.offsetBy(dx: -origin.x, dy: -origin.y)
          let rect = interpolate(source, fit, progress)
          Image(uiImage: image).resizable().scaledToFill().frame(width: max(1, rect.width), height: max(1, rect.height)).clipped()
            .position(x: rect.midX, y: rect.midY).allowsHitTesting(false)
        }
      }.opacity(closing ? 0 : 1)
        .previewCloudConsent()
        .onAppear {
          session.start()
          if item.poster == nil || reduceMotion { progress = 1; flight = false }
          else { withAnimation(motion, completionCriteria: .logicallyComplete) { progress = 1 } completion: { flight = false } }
        }
        .onDisappear { session.stop() }
        .onChange(of: policy.choice) { _, _ in session.reloadForPolicy() }
    }.preferredColorScheme(.dark).background(Color.clear).persistentSystemOverlays(chrome ? .automatic : .hidden)
  }
  private var filmstrip: some View {
    HStack(spacing: 4) {
      if let index = session.library.previewIndex(of: session.current.asset) {
        ForEach(max(0,index-2)..<min(session.library.loaded,index+3), id: \.self) { i in
          if let asset = session.library.asset(at: i) {
            Button { session.activate(asset) } label: {
              ReadOnlyMediaThumbnail(asset: asset, width: i == index ? 42 : 24, height: 38)
                .overlay { if i == index { RoundedRectangle(cornerRadius: 6).stroke(.white,lineWidth: 1.5) } }
            }.buttonStyle(.plain).accessibilityLabel(Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? NSLocalizedString("library_preview", comment: "")))
          }
        }
      }
    }.frame(maxWidth: .infinity)
  }
  private func vertical(_ state: UIGestureRecognizer.State, value: CGFloat, predicted: CGFloat, height: CGFloat) {
    guard !session.zoomed else { return }
    switch state {
    case .began: drawerStart = drawer
    case .changed:
      if value < 0 || drawerStart > 0 { drawer = max(0, min(0.8, drawerStart - value / height)) }
      else { translation = max(0, value) }
    case .ended:
      if drawerStart == 0 && value > 0 {
        if value > 120 || predicted > 260 { dismissViewer() }
        else { withAnimation(motion) { translation = 0 } }
      } else {
        let projected = drawerStart - predicted / height
        withAnimation(motion) { drawer = projected < 0.18 ? 0 : projected > 0.65 ? 0.75 : 0.45 }
      }
      drawerStart = 0
    case .cancelled, .failed: withAnimation(motion) { drawer = drawerStart; translation = 0 }; drawerStart = 0
    default: break
    }
  }
  private func move(_ direction: Int) {
    guard !session.paging, let asset = session.adjacent(to: session.current.asset, direction: direction) else { return }
    session.activate(asset)
  }
  private func dismissViewer() {
    guard !closing else { return }
    if reduceMotion { close(); return }
    if session.current.asset.localIdentifier == item.id, session.current.image != nil, drawer == 0 {
      flight = true; translation = 0
      withAnimation(motion, completionCriteria: .logicallyComplete) { progress = 0 } completion: { close() }
    } else { withAnimation(motion, completionCriteria: .logicallyComplete) { closing = true } completion: { close() } }
  }
  private func icon(_ symbol: String, title: String, identifier: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44).background(.black.opacity(0.3), in: Circle()) }
      .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(title))).accessibilityIdentifier(identifier)
  }
  private func fitted(_ size: CGSize, in bounds: CGRect) -> CGRect {
    let scale = min(bounds.width / max(1, size.width), bounds.height / max(1, size.height))
    let fit = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(x: bounds.midX - fit.width / 2, y: bounds.midY - fit.height / 2, width: fit.width, height: fit.height)
  }
  private func interpolate(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: a.minX + (b.minX-a.minX)*t, y: a.minY + (b.minY-a.minY)*t, width: a.width+(b.width-a.width)*t, height: a.height+(b.height-a.height)*t)
  }
}

private struct IOSMediaPager: UIViewControllerRepresentable {
  @ObservedObject var session: MediaPreviewSession
  let tap: () -> Void
  let vertical: (UIGestureRecognizer.State, CGFloat, CGFloat) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIViewController(context: Context) -> UIPageViewController {
    let controller = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 12])
    controller.dataSource = context.coordinator; controller.delegate = context.coordinator
    context.coordinator.controller = controller
    controller.setViewControllers([context.coordinator.page(session.current.asset)], direction: .forward, animated: false)
    let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
    pan.delegate = context.coordinator; controller.view.addGestureRecognizer(pan)
    controller.view.backgroundColor = .clear
    return controller
  }
  func updateUIViewController(_ controller: UIPageViewController, context: Context) {
    let c = context.coordinator; c.parent = self
    (controller.view.subviews.first { $0 is UIScrollView } as? UIScrollView)?.isScrollEnabled = !session.zoomed
    guard let old = controller.viewControllers?.first as? PreviewPageController,
      old.asset.localIdentifier != session.current.asset.localIdentifier, !c.animating else { return }
    let before = session.library.previewIndex(of: old.asset) ?? 0, after = session.library.previewIndex(of: session.current.asset) ?? 0
    c.animating = true; session.paging = true
    controller.setViewControllers([c.page(session.current.asset)], direction: after > before ? .forward : .reverse, animated: !UIAccessibility.isReduceMotionEnabled) { _ in
      c.animating = false; self.session.paging = false; c.trim()
    }
  }
  static func dismantleUIViewController(_ controller: UIPageViewController, coordinator: Coordinator) { controller.dataSource = nil; controller.delegate = nil; coordinator.pages.removeAll() }
  @MainActor final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
    var parent: IOSMediaPager
    weak var controller: UIPageViewController?
    var pages: [String: PreviewPageController] = [:]
    var animating = false
    init(_ parent: IOSMediaPager) { self.parent = parent }
    func page(_ asset: PHAsset) -> PreviewPageController {
      if let page = pages[asset.localIdentifier] { return page }
      let page = PreviewPageController(asset: asset, session: parent.session, tap: { [weak self] in self?.parent.tap() })
      pages[asset.localIdentifier] = page; return page
    }
    func trim() {
      let asset = parent.session.current.asset
      let keep = Set([asset, parent.session.adjacent(to: asset, direction: -1), parent.session.adjacent(to: asset, direction: 1)].compactMap { $0?.localIdentifier })
      for id in Array(pages.keys) where !keep.contains(id) { pages.removeValue(forKey: id) }
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? { neighbour(viewController, -1) }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? { neighbour(viewController, 1) }
    private func neighbour(_ controller: UIViewController, _ direction: Int) -> UIViewController? {
      guard let page = controller as? PreviewPageController, let asset = parent.session.adjacent(to: page.asset, direction: direction) else { return nil }
      return self.page(asset)
    }
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { parent.session.paging = true }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
      if completed, let page = pageViewController.viewControllers?.first as? PreviewPageController { parent.session.activate(page.asset) }
      parent.session.paging = false; trim()
    }
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
      guard let pan = gesture as? UIPanGestureRecognizer, let view = pan.view else { return false }
      let velocity = pan.velocity(in: view)
      return !parent.session.zoomed && !parent.session.paging && abs(velocity.y) > abs(velocity.x)*1.25 && pan.location(in: view).y < view.bounds.height*0.85
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc func pan(_ gesture: UIPanGestureRecognizer) {
      let y = gesture.translation(in: gesture.view).y, velocity = gesture.velocity(in: gesture.view).y
      parent.vertical(gesture.state, y, y + velocity*0.18)
    }
  }
}
@MainActor private final class PreviewPageController: UIHostingController<IOSPreviewPageContent> {
  let asset: PHAsset
  init(asset: PHAsset, session: MediaPreviewSession, tap: @escaping () -> Void) {
    self.asset = asset
    super.init(rootView: IOSPreviewPageContent(preview: session.model(for: asset), session: session, zoom: { value in
      if session.current.asset.localIdentifier == asset.localIdentifier { session.zoomed = value }
    }, tap: tap))
    view.backgroundColor = .clear
  }
  @MainActor required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}
private struct IOSPreviewPageContent: View {
  @ObservedObject var preview: MediaPreviewModel
  @ObservedObject var session: MediaPreviewSession
  let zoom: (Bool) -> Void
  let tap: () -> Void
  var body: some View {
    ZStack {
      if let player = preview.player { VideoPlayer(player: player).accessibilityIdentifier("library.preview.video") }
      else if let image = preview.image { IOSZoomMedia(image: image, live: preview.livePhoto, active: session.current === preview, identity: preview.asset.localIdentifier, fitRevision: session.fitRevision, zoom: zoom, tap: tap) }
      if preview.loading {
        if preview.image == nil { ProgressView().tint(.white).padding(16).background(.black.opacity(0.4), in: Circle()) }
        else {
          VStack { Spacer(); HStack { Spacer(); ProgressView().tint(.white).padding(10).background(.black.opacity(0.5), in: Circle()) } }
            .padding(.trailing,16).padding(.bottom,80).allowsHitTesting(false)
        }
      }
      if preview.cloudNeeded || preview.failure {
        VStack(spacing: 12) {
          Image(systemName: preview.cloudNeeded ? "icloud.and.arrow.down" : "exclamationmark.circle").font(.largeTitle)
          Text(preview.cloudNeeded ? "preview_cloud_title" : "library_preview_unavailable").font(.callout)
          Button(PreviewNetworkPolicy.shared.allowed ? "retry_task" : "preview_cloud_allow") {
            if PreviewNetworkPolicy.shared.allowed { preview.load() }
            else { PreviewNetworkPolicy.shared.asking = true }
          }.buttonStyle(.bordered).tint(.white)
        }.padding(20).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
  }
}
private struct IOSZoomMedia: UIViewRepresentable {
  let image: UIImage
  let live: PHLivePhoto?
  let active: Bool
  let identity: String
  let fitRevision: Int
  let zoom: (Bool) -> Void
  let tap: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> MediaZoomScroll {
    let scroll = MediaZoomScroll(); scroll.delegate = context.coordinator
    scroll.maximumZoomScale = 5; scroll.minimumZoomScale = 1
    scroll.showsHorizontalScrollIndicator = false; scroll.showsVerticalScrollIndicator = false
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.photo.isAccessibilityElement = true; scroll.photo.accessibilityIdentifier = "library.preview.photo"; scroll.photo.accessibilityTraits = .image
    let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:))); double.numberOfTapsRequired = 2
    let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap(_:))); single.require(toFail: double)
    scroll.addGestureRecognizer(double); scroll.addGestureRecognizer(single)
    scroll.panGestureRecognizer.isEnabled = false
    return scroll
  }
  func updateUIView(_ scroll: MediaZoomScroll, context: Context) {
    context.coordinator.parent = self
    if active && (!scroll.active || scroll.fitRevision != fitRevision) { scroll.setZoomScale(1,animated: false) }
    scroll.fitRevision = fitRevision
    scroll.active = active; scroll.photo.accessibilityValue = identity
    if scroll.photo.image !== image { scroll.photo.image = image; scroll.setNeedsLayout() }
    scroll.live.livePhoto = live; scroll.live.isHidden = live == nil
  }
  static func dismantleUIView(_ scroll: MediaZoomScroll, coordinator: Coordinator) { scroll.live.stopPlayback(); scroll.live.livePhoto = nil; scroll.delegate = nil }
  final class Coordinator: NSObject, UIScrollViewDelegate {
    var parent: IOSZoomMedia
    init(_ parent: IOSZoomMedia) { self.parent = parent }
    func viewForZooming(in scroll: UIScrollView) -> UIView? { (scroll as? MediaZoomScroll)?.media }
    func scrollViewDidZoom(_ scroll: UIScrollView) {
      let zoomed = scroll.zoomScale > 1.01; scroll.panGestureRecognizer.isEnabled = zoomed
      parent.zoom(zoomed); (scroll as? MediaZoomScroll)?.centerMedia()
    }
    @objc func singleTap(_ gesture: UITapGestureRecognizer) { parent.tap() }
    @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
      guard let scroll = gesture.view as? MediaZoomScroll else { return }
      if scroll.zoomScale > 1.01 { scroll.setZoomScale(1, animated: !UIAccessibility.isReduceMotionEnabled) }
      else {
        let point = gesture.location(in: scroll.media), w = scroll.bounds.width/2.5, h = scroll.bounds.height/2.5
        scroll.zoom(to: CGRect(x: point.x-w/2, y: point.y-h/2, width: w, height: h), animated: !UIAccessibility.isReduceMotionEnabled)
      }
    }
  }
}
@MainActor private final class MediaZoomScroll: UIScrollView {
  let media = UIView(), photo = UIImageView(), live = PHLivePhotoView()
  var active = false
  var fitRevision = -1
  private var lastBounds = CGSize.zero
  private var lastImage: CGSize = .zero
  override init(frame: CGRect) {
    super.init(frame: frame); addSubview(media); media.addSubview(photo); media.addSubview(live)
    photo.contentMode = .scaleAspectFit; live.contentMode = .scaleAspectFit
    backgroundColor = .black
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layoutSubviews() {
    super.layoutSubviews()
    let size = photo.image?.size ?? .zero
    if bounds.size != lastBounds || size != lastImage {
      let wasZoomed = zoomScale > 1.01
      if !wasZoomed { fit(size) }
      lastBounds = bounds.size; lastImage = size
    }
    centerMedia()
  }
  private func fit(_ size: CGSize) {
    guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else { return }
    let factor = min(bounds.width/size.width, bounds.height/size.height)
    let fit = CGSize(width: size.width*factor, height: size.height*factor)
    media.frame = CGRect(origin: .zero, size: fit); photo.frame = media.bounds; live.frame = media.bounds; contentSize = fit
  }
  func centerMedia() {
    contentInset = UIEdgeInsets(top: max(0,(bounds.height-contentSize.height)/2), left: max(0,(bounds.width-contentSize.width)/2), bottom: 0, right: 0)
  }
}

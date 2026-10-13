import Combine
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
    if !showSupplementaryContent {
      library.previewFrame = { [weak view, weak library] id in
        guard let view, let library, let index = library.index(of: id), index < library.loaded else { return nil }
        let path = IndexPath(item: index, section: 0)
        if view.cellForItem(at: path) == nil { view.scrollToItem(at: path, at: .centeredVertically, animated: false); view.layoutIfNeeded() }
        guard let attributes = view.layoutAttributesForItem(at: path) else { return nil }
        return view.convert(attributes.frame, to: nil)
      }
    }
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
    if !coordinator.parent.showSupplementaryContent { coordinator.parent.library.previewFrame = nil }
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
    private var timelineDuration: CFTimeInterval = 0.36
    private var timelineTarget: (LibraryViewMode, Int)?
    private var timelineAnchor: Int?
    private var timelineAnchorFraction: CGFloat = 0
    private var timelineAnchorFractionX: CGFloat = 0
    private var timelineAnchorX: CGFloat = 0
    private var timelineReleaseX: CGFloat = 0
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
      settleTimeline(mode: mode, columns: mode == .months ? 7 : 3, duration: 0.42)
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
        timelineAnchorFractionX = min(1,max(0,(point.x-frame.minX)/max(1,frame.width)))
        timelineAnchorX = point.x
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
      timelineReleaseX = layout.focusTranslationX
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
      let settled = LibraryMotion.settle(value)
      layout.focusTranslationX = timelineReleaseX*(1-settled)
      layout.setProgress(settled); positionTimelineAnchor()
      if value >= 1 { finishTimeline() }
    }
    private func finishTimeline() {
      guard let layout = collection?.collectionViewLayout as? LibraryTimelineLayout, let target = timelineTarget else { stopTimelineMotion(); return }
      layout.focusTranslationX = 0
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
        if let timelineAnchor {
          let frame = layout.frame(at: timelineAnchor).offsetBy(dx: -layout.focusTranslationX,dy: 0)
          timelineAnchorX = recognizer.location(in: collection).x
          timelineAnchorY = recognizer.location(in: collection).y-collection.contentOffset.y
          layout.focusTranslationX = timelineAnchorX-frame.minX-timelineAnchorFractionX*frame.width
        }
        positionTimelineAnchor()
      case .ended:
        let desired = min(9,max(3,pinchDensity/max(0.15,recognizer.scale)))
        let target = [3,5,7,9].min { abs(CGFloat($0)-desired) < abs(CGFloat($1)-desired) } ?? 3
        let mode: LibraryViewMode = target >= 5 ? .months : (pinchMode == .all ? .all : .days)
        settleTimeline(mode: mode, columns: target, duration: 0.32)
      case .cancelled, .failed:
        settleTimeline(mode: pinchMode, columns: Int(pinchDensity.rounded()), duration: 0.3)
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
  var body: some View {
    if UIDevice.current.userInterfaceIdiom == .phone { IOSCalendarLibraryPage(library: library, model: model) }
    else { IOSLegacyLibraryPage(library: library, model: model) }
  }
}

private struct IOSCalendarLibraryPage: View {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var model: BackupModel
  @State private var rebackupReceivedSelection = false
  @State private var confirmSelectedBackup = false
  @State private var preview: IOSPreviewItem?
  var body: some View {
    Group {
      if let placeholder = library.placeholder {
        NavigationStack {
          LibraryPlaceholder(kind:placeholder,requestingAccess:library.requestingPermission,
            requestAccess:{Task { await library.open(requestPermission:true) }},
            clearFilter:{Task { await library.changeFilter(.all) }})
            .navigationTitle("nav_library")
        }
      } else {
        IOSCalendarLibrary(library:library,model:model,onPreview:{ asset,frame in
          var transaction=Transaction();transaction.disablesAnimations=true
          withTransaction(transaction) { preview=IOSPreviewItem(asset:asset,frame:frame,poster:library.thumbnails.poster(for:asset)) }
        },onBackup:showBackupConfirmation).ignoresSafeArea(.container)
      }
    }.background(DuckColors.canvas).tint(DuckColors.action)
      .task { await library.open() }
      .onAppear { library.refreshVisiblePreviews() }
      .onDisappear { library.thumbnails.clear() }
      .sheet(isPresented:$confirmSelectedBackup) { selectedBackupConfirmation }
      .background(IOSPreviewPresentation(item:preview,library:library) { preview=nil }.frame(width:0,height:0))
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
private struct IOSLegacyLibraryPage: View {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var model: BackupModel
  @State private var confirmSelectedBackup = false
  @State private var rebackupReceivedSelection = false
  @State private var selecting = false
  @State private var preview: IOSPreviewItem?
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
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
      }.background(DuckColors.canvas).foregroundStyle(DuckColors.text).symbolVariant(.none)
      .navigationTitle(selecting ? String(format: NSLocalizedString("library_selection_title",comment: ""),library.selection.count) : NSLocalizedString("nav_library",comment: ""))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          if selecting { selectionTitle } else { browsingTitle }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          if selecting { selectionActions } else { typeMenu; viewMenu }
        }
      }
      .toolbarBackground(DuckColors.surface,for: .navigationBar).toolbarBackground(.visible,for: .navigationBar)
      .task { await library.open() }
      .onAppear { library.refreshVisiblePreviews() }
      .onDisappear { library.thumbnails.clear() }
      .sheet(isPresented: $confirmSelectedBackup) { selectedBackupConfirmation }
      .background(IOSPreviewPresentation(item: preview, library: library) {
        preview = nil
      }.frame(width: 0, height: 0))

    }
  }
  @Environment(\.dynamicTypeSize) private var textSize
  private var selectionTitle: some View {
    Text(String(format: NSLocalizedString("library_selection_title", comment: ""), library.selection.count))
      .font(.title2.weight(.semibold)).accessibilityIdentifier("page.header.title")
  }
  private var browsingTitle: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("nav_library").font(.headline).accessibilityIdentifier("page.header.title")
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
        Image(systemName: "line.3.horizontal.decrease.circle")
          .font(.system(size: 20)).frame(width: 44,height: 44)
          .overlay(alignment: .topTrailing) {
            if library.filter != .all { Circle().fill(DuckColors.action).frame(width: 6,height: 6).padding(7) }
          }
      }.buttonStyle(.plain).foregroundStyle(DuckColors.action).accessibilityIdentifier("library.filter")
        .accessibilityLabel(Text("media_type"))
        .accessibilityValue(Text(LocalizedStringKey(library.filter.title)))
    }
  }
  private var viewMenu: some View {
    Menu {
      Picker("library_view_mode", selection: $library.viewMode) {
        ForEach(LibraryViewMode.allCases) { mode in Text(LocalizedStringKey(mode.title)).tag(mode) }
      }.pickerStyle(.inline)
    } label: {
      HStack(spacing: 4) { Text(LocalizedStringKey(library.viewMode.title)); Image(systemName: "chevron.down").font(.caption2) }.font(.callout).frame(minHeight: 44)
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

private struct IOSPreviewPresentation: UIViewControllerRepresentable {
  let item: IOSPreviewItem?
  let library: PhotoLibraryModel
  let close: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
  func updateUIViewController(_ host: UIViewController, context: Context) {
    guard let item, context.coordinator.active == nil else { return }
    let coordinator = context.coordinator
    DispatchQueue.main.async {
      guard host.view.window != nil, host.presentedViewController == nil, coordinator.active == nil else { return }
      coordinator.active = item.id
      let viewer = UIHostingController(rootView: IOSPhotoPreview(item: item, library: library) {
        host.dismiss(animated: false) { coordinator.active = nil; close() }
      })
      viewer.overrideUserInterfaceStyle = .dark
      viewer.view.backgroundColor = .clear; viewer.modalPresentationStyle = .overFullScreen
      viewer.modalPresentationCapturesStatusBarAppearance = true
      host.present(viewer, animated: false)
    }
  }
  final class Coordinator { var active: String? }
}
private struct IOSPhotoPreview: View {
  let item: IOSPreviewItem
  let close: () -> Void
  @StateObject private var session: MediaPreviewSession
  init(item: IOSPreviewItem, library: PhotoLibraryModel, close: @escaping () -> Void) {
    self.item = item; self.close = close
    _session = StateObject(wrappedValue: MediaPreviewSession(asset: item.asset, library: library, poster: item.poster))
  }
  var body: some View {
    IOSNativeViewer(item: item, session: session, close: close).ignoresSafeArea()
      .previewCloudConsent(appearance: .dark).environment(\.colorScheme, .dark).preferredColorScheme(.dark)
  }
}
private struct IOSNativeViewer: UIViewControllerRepresentable {
  let item: IOSPreviewItem
  let session: MediaPreviewSession
  let close: () -> Void
  func makeUIViewController(context: Context) -> NativeMediaViewer { NativeMediaViewer(item: item, session: session, close: close) }
  func updateUIViewController(_ controller: NativeMediaViewer, context: Context) {}
}

/// One UIKit owner coordinates paging, scrubbing, information and image flight.
/// Gesture progress is direct; controllers are recycled only after a page settles.
@MainActor private final class NativeMediaViewer: UIViewController, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
  let item: IOSPreviewItem, session: MediaPreviewSession, closeViewer: () -> Void
  let backdrop = UIView(), stage = UIView(), pager = UIScrollView(), header = UIView(), footer = UIView()
  let date = UILabel(), status = UILabel(), progress = UIProgressView(progressViewStyle: .default)
  let spinner = UIActivityIndicatorView(style: .medium), retry = UIButton(type: .system)
  lazy var strip: UICollectionView = {
    let layout = UICollectionViewFlowLayout(); layout.scrollDirection = .horizontal
    layout.itemSize = CGSize(width: 30, height: 42); layout.minimumLineSpacing = 4
    return UICollectionView(frame: .zero, collectionViewLayout: layout)
  }()
  let information = UIView(), infoHeader = UIView()
  var informationHost: UIHostingController<AnyView>?
  var pages: [UIHostingController<IOSPreviewPageContent>] = []
  var pageCache: [String: UIHostingController<IOSPreviewPageContent>] = [:]
  var pageAssets: [PHAsset] = []
  var cancellables = Set<AnyCancellable>(), mediaObservations = Set<AnyCancellable>()
  var animator: UIViewPropertyAnimator?, infoAnimator: UIViewPropertyAnimator?
  var suppress = false, closing = false, flying = true, chrome = true, infoHeight: CGFloat = 0
  var index: Int = 0, verticalKind = 0, startInfo: CGFloat = 0, lastSize = CGSize.zero
  var pendingAsset: PHAsset?
  init(item: IOSPreviewItem, session: MediaPreviewSession, close: @escaping () -> Void) {
    self.item = item; self.session = session; closeViewer = close; super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
  override func viewDidLoad() {
    super.viewDidLoad(); overrideUserInterfaceStyle = .dark; view.backgroundColor = .clear
    backdrop.backgroundColor = .black; backdrop.alpha = 0; view.addSubview(backdrop)
    view.addSubview(stage); stage.addSubview(pager); view.addSubview(header); view.addSubview(footer)
    pager.isPagingEnabled = true; pager.decelerationRate = .fast; pager.delegate = self
    pager.contentInsetAdjustmentBehavior = .never; pager.showsHorizontalScrollIndicator = false
    pager.accessibilityIdentifier = "library.preview.pager"
    let pan = UIPanGestureRecognizer(target: self, action: #selector(vertical(_:))); pan.delegate = self
    stage.addGestureRecognizer(pan); pager.panGestureRecognizer.require(toFail: pan)
    let back = icon("chevron.left", label: "settings_done", id: "library.preview.close") { [weak self] in self?.dismissViewer() }
    back.tag = 1; header.addSubview(back)
    let info = icon("info.circle", label: "apple_photo_detail", id: "library.preview.info") { [weak self] in self?.setInfo(true) }
    info.tag = 2; header.addSubview(info)
    date.font = .preferredFont(forTextStyle: .subheadline); date.textColor = .white; date.textAlignment = .center
    date.numberOfLines = 2; date.adjustsFontForContentSizeCategory = true
    date.accessibilityIdentifier = "library.preview.date"; header.addSubview(date)
    status.font = .preferredFont(forTextStyle: .caption1); status.textColor = .lightGray; status.textAlignment = .center
    status.adjustsFontForContentSizeCategory = true; status.numberOfLines = 2; header.addSubview(status)
    progress.progressTintColor = UIColor(DuckColors.action); header.addSubview(progress)
    spinner.color = .white; spinner.hidesWhenStopped = true; header.addSubview(spinner)
    retry.titleLabel?.font = .preferredFont(forTextStyle: .caption1); retry.tintColor = UIColor(DuckColors.action)
    retry.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      if PreviewNetworkPolicy.shared.allowed { self.session.current.load() } else { PreviewNetworkPolicy.shared.asking = true }
    }, for: .touchUpInside); header.addSubview(retry)
    strip.backgroundColor = .clear; strip.showsHorizontalScrollIndicator = false
    strip.dataSource = self; strip.delegate = self; strip.accessibilityIdentifier = "library.preview.filmstrip"
    strip.register(PreviewStripCell.self, forCellWithReuseIdentifier: "preview.strip"); footer.addSubview(strip)
    information.backgroundColor = UIColor(DuckColors.surface); information.layer.cornerRadius = 20
    information.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]; information.clipsToBounds = true
    information.accessibilityIdentifier = "preview.info.drawer"; view.addSubview(information); information.addSubview(infoHeader)
    let handle = UIView(); handle.backgroundColor = .lightGray; handle.layer.cornerRadius = 2; handle.tag = 3; infoHeader.addSubview(handle)
    let done = icon("xmark", label: "preview_hide_info", id: "preview.info.close") { [weak self] in self?.setInfo(false) }
    done.tag = 4; done.tintColor = UIColor(DuckColors.action); infoHeader.addSubview(done)
    let handlePan = UIPanGestureRecognizer(target: self, action: #selector(dragInformation(_:))); handlePan.delegate = self
    infoHeader.addGestureRecognizer(handlePan)
    session.$current.receive(on: DispatchQueue.main).sink { [weak self] model in self?.currentChanged(model) }.store(in: &cancellables)
    session.$zoomed.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] zoomed in self?.pager.isScrollEnabled = !zoomed && !(self?.closing ?? true) }.store(in: &cancellables)
    PreviewNetworkPolicy.shared.$choice.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.session.reloadForPolicy() }.store(in: &cancellables)
    PreviewNetworkPolicy.shared.$asking.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateStatus() }.store(in: &cancellables)
    index = session.library.previewIndex(of: session.current.asset) ?? 0; installPages(); observeMedia()
  }
  override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if flying { session.start(); enter() } }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews(); guard lastSize != view.bounds.size else { return }
    lastSize = view.bounds.size; layoutMedia(); centerStrip()
  }
  deinit { animator?.stopAnimation(true); infoAnimator?.stopAnimation(true) }
  func layoutMedia() {
    let b = view.bounds, top = view.safeAreaInsets.top, bottom = view.safeAreaInsets.bottom
    let dateHeight = max(24,date.sizeThatFits(CGSize(width: max(1,b.width-116),height: 120)).height)
    let statusHeight = max(20,status.sizeThatFits(CGSize(width: max(1,b.width-140),height: 100)).height)
    let statusY = dateHeight+7, headerHeight = max(68,statusY+statusHeight+14)
    backdrop.frame = b
    header.frame = CGRect(x: 0,y: top,width: b.width,height: headerHeight)
    header.viewWithTag(1)?.frame = CGRect(x: 8,y: 4,width: 44,height: 44)
    header.viewWithTag(2)?.frame = CGRect(x: b.width-52,y: 4,width: 44,height: 44)
    date.frame = CGRect(x: 58,y: 5,width: b.width-116,height: dateHeight)
    status.frame = CGRect(x: 70,y: statusY,width: b.width-140,height: statusHeight)
    progress.frame = CGRect(x: b.midX-54,y: headerHeight-11,width: 108,height: 2)
    spinner.frame = CGRect(x: 30,y: statusY,width: 20,height: 20)
    retry.frame = CGRect(x: 60,y: statusY-3,width: b.width-120,height: max(28,statusHeight+6))
    footer.frame = CGRect(x: 0,y: b.height-bottom-58,width: b.width,height: 58)
    strip.frame = footer.bounds.insetBy(dx: 16,dy: 8)
    strip.contentInset = UIEdgeInsets(top: 0,left: max(0,strip.bounds.width/2-15),bottom: 0,right: max(0,strip.bounds.width/2-15))
    let reserved = infoHeight > 0 ? infoHeight : bottom+58
    stage.frame = CGRect(x: 0,y: top+headerHeight,width: b.width,height: max(1,b.height-top-headerHeight-reserved))
    suppress = true; pager.frame = stage.bounds
    pager.contentSize = CGSize(width: stage.bounds.width*3,height: stage.bounds.height)
    for (i,page) in pages.enumerated() { page.view.frame = CGRect(x: CGFloat(i)*stage.bounds.width,y: 0,width: stage.bounds.width,height: stage.bounds.height) }
    if !pager.isDragging && !pager.isDecelerating { pager.contentOffset.x = pager.bounds.width }
    suppress = false
    information.frame = CGRect(x: 0,y: b.height-infoHeight,width: b.width,height: infoHeight)
    infoHeader.frame = CGRect(x: 0,y: 0,width: b.width,height: 48)
    infoHeader.viewWithTag(3)?.frame = CGRect(x: b.midX-18,y: 10,width: 36,height: 4)
    infoHeader.viewWithTag(4)?.frame = CGRect(x: b.width-52,y: 2,width: 44,height: 44)
    informationHost?.view.frame = CGRect(x: 0,y: 48,width: b.width,height: max(0,infoHeight-48))
    header.alpha = chrome && !flying ? 1 : 0; footer.alpha = chrome && infoHeight == 0 && !flying ? 1 : 0
  }
  func makePage(_ asset: PHAsset, cache: Bool = true) -> UIHostingController<IOSPreviewPageContent> {
    if cache, let cached = pageCache[asset.localIdentifier] { return cached }
    let controller = UIHostingController(rootView: IOSPreviewPageContent(preview: session.model(for: asset), session: session, zoom: { [weak self] zoomed in
      guard let self, self.session.current.asset.localIdentifier == asset.localIdentifier else { return }
      if self.session.zoomed != zoomed { DispatchQueue.main.async { self.session.zoomed = zoomed } }
    }, tap: { [weak self] in self?.toggleChrome() }))
    controller.view.backgroundColor = .clear; if cache { pageCache[asset.localIdentifier] = controller }; return controller
  }
  func installPages() {
    suppress = true
    for page in pages { page.willMove(toParent: nil); page.view.removeFromSuperview(); page.removeFromParent() }
    let asset = session.current.asset
    pageAssets = [session.adjacent(to: asset,direction: -1) ?? asset,asset,session.adjacent(to: asset,direction: 1) ?? asset]
    pages = pageAssets.enumerated().map { slot,asset in makePage(asset,cache: slot == 1 || asset.localIdentifier != session.current.asset.localIdentifier) }
    for page in pages { addChild(page); pager.addSubview(page.view); page.didMove(toParent: self) }
    let keep = Set(pageAssets.map(\.localIdentifier))
    for id in Array(pageCache.keys) where !keep.contains(id) { pageCache.removeValue(forKey: id) }
    pager.isScrollEnabled = true; layoutMedia(); suppress = false
  }
  func currentChanged(_ model: MediaPreviewModel) {
    guard !closing else { return }
    if pager.isDragging || pager.isDecelerating { pendingAsset = model.asset; return }
    index = session.library.previewIndex(of: model.asset) ?? index
    if pageAssets.count != 3 || pageAssets[1].localIdentifier != model.asset.localIdentifier { installPages() }
    if !strip.isDragging && !strip.isDecelerating { strip.reloadData(); centerStrip() }
    else { for path in strip.indexPathsForVisibleItems { if let cell = strip.cellForItem(at: path) as? PreviewStripCell { cell.setSelected(path.item == index) } } }
    observeMedia(); refreshInformation()
  }
  func observeMedia() {
    mediaObservations.removeAll()
    session.current.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateStatus() }.store(in: &mediaObservations)
    updateStatus()
  }
  func updateStatus() {
    let model = session.current
    date.text = model.asset.creationDate?.formatted(date: .abbreviated,time: .omitted) ?? NSLocalizedString("library_preview",comment: "")
    status.text = model.asset.creationDate?.formatted(date: .omitted,time: .shortened)
    retry.isHidden = PreviewNetworkPolicy.shared.asking || !(model.failure || model.cloudNeeded)
    retry.setTitle(NSLocalizedString(model.cloudNeeded ? "preview_cloud_allow" : "retry_task",comment: ""),for: .normal)
    status.isHidden = !retry.isHidden
    if model.loading { spinner.startAnimating(); status.text = NSLocalizedString("preview_loading",comment: "") } else { spinner.stopAnimating() }
    progress.isHidden = !model.loading || model.progress <= 0 || model.progress >= 1
    progress.progress = Float(model.progress)
    if !flying && !closing && verticalKind == 0 && infoAnimator?.isRunning != true { layoutMedia() }
  }
  func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { session.library.loaded }
  func collectionView(_ collectionView: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "preview.strip",for: path) as! PreviewStripCell
    if let asset = session.library.asset(at: path.item) { cell.configure(asset, selected: path.item == index, pipeline: session.library.thumbnails) }
    return cell
  }
  func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) { (cell as? PreviewStripCell)?.cancel() }
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt path: IndexPath) {
    guard !pager.isDragging && !pager.isDecelerating, let asset = session.library.asset(at: path.item) else { return }
    session.activate(asset)
  }
  func centerStrip() {
    guard !strip.isDragging && !strip.isDecelerating else { return }
    suppress = true; strip.contentOffset.x = CGFloat(index)*34-strip.contentInset.left; suppress = false
  }
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard !suppress, !flying, !closing else { return }
    if scrollView === pager {
      session.paging = true
      if !strip.isDragging && !strip.isDecelerating {
        suppress = true; strip.contentOffset.x = (CGFloat(index)+pager.contentOffset.x/max(1,pager.bounds.width)-1)*34-strip.contentInset.left; suppress = false
      }
    } else if scrollView === strip, strip.isDragging || strip.isDecelerating {
      let next = max(0,min(session.library.loaded-1,Int(round((strip.contentOffset.x+strip.contentInset.left)/34))))
      if next != index, let asset = session.library.asset(at: next) {
        index = next; session.activate(asset)
      }
    }
  }
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { settle(scrollView) } }
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle(scrollView) }
  func settle(_ scrollView: UIScrollView) {
    if scrollView === pager {
      let shift = Int(round(pager.contentOffset.x/max(1,pager.bounds.width)))-1
      if shift != 0, let asset = session.library.asset(at: index+shift) { session.activate(asset) }
      suppress = true; pager.contentOffset.x = pager.bounds.width; suppress = false
      session.paging = false
      if let pendingAsset { self.pendingAsset = nil; currentChanged(session.model(for: pendingAsset)) }
    }
    centerStrip()
  }
  func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    guard !flying, !closing, !session.zoomed, !pager.isDragging, !pager.isDecelerating, !PreviewNetworkPolicy.shared.asking else { return false }
    if let pan = recognizer as? UIPanGestureRecognizer { let velocity = pan.velocity(in: view); return abs(velocity.y) > abs(velocity.x)*1.35 }
    return true
  }
  func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    var node = touch.view
    while let view = node { if view is UIControl { return false }; node = view.superview }
    return recognizer.view === infoHeader || touch.location(in: stage).y < stage.bounds.height*0.84
  }
  @objc func vertical(_ gesture: UIPanGestureRecognizer) {
    let point = gesture.translation(in: view), velocity = gesture.velocity(in: view)
    switch gesture.state {
    case .began:
      animator?.stopAnimation(true); interruptInformation()
      startInfo = infoHeight; verticalKind = infoHeight > 0 || velocity.y < 0 ? 2 : 1
    case .changed:
      if verticalKind == 1 {
        stage.transform = CGAffineTransform(translationX: point.x*0.2,y: max(0,point.y))
        backdrop.alpha = max(0,1-max(0,point.y)/320); header.alpha = max(0,1-point.y/100); footer.alpha = header.alpha
      } else { ensureInformation(); infoHeight = max(0,min(view.bounds.height*0.7,startInfo-point.y)); layoutMedia() }
    case .ended, .cancelled, .failed:
      if verticalKind == 1 {
        if gesture.state == .ended && (point.y > view.bounds.height*0.14 || velocity.y > 750) { dismissViewer(velocity: velocity.y) }
        else { animate { self.stage.transform = .identity; self.backdrop.alpha = 1; self.layoutMedia() } }
      } else {
        setInfo(gesture.state == .ended ? infoHeight-velocity.y*0.12 > 140 : startInfo > 0)
      }
      verticalKind = 0
    default: break
    }
  }
  @objc func dragInformation(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began: interruptInformation(); startInfo = infoHeight
    case .changed: infoHeight = max(0,min(view.bounds.height*0.7,startInfo-gesture.translation(in: view).y)); layoutMedia()
    case .ended, .cancelled, .failed: setInfo(gesture.state == .ended ? infoHeight-gesture.velocity(in: view).y*0.12 > 140 : startInfo > 0)
    default: break
    }
  }
  func ensureInformation() {
    guard informationHost == nil else { return }
    let host = UIHostingController(rootView: AnyView(ScrollView { PhotoMetadataPanel(preview: session.current).padding(.horizontal,20).padding(.bottom,24) }.preferredColorScheme(.dark)))
    host.overrideUserInterfaceStyle = .dark
    addChild(host); information.addSubview(host.view); host.view.backgroundColor = .clear; host.didMove(toParent: self); informationHost = host
  }
  func refreshInformation() {
    informationHost?.rootView = AnyView(ScrollView { PhotoMetadataPanel(preview: session.current).padding(.horizontal,20).padding(.bottom,24) }.preferredColorScheme(.dark))
  }
  func setInfo(_ open: Bool) {
    guard !flying && !closing && !PreviewNetworkPolicy.shared.asking else { return }
    interruptInformation()
    session.fitMedia(); if open { ensureInformation() }
    let target: CGFloat = open ? min(500,view.bounds.height*0.45) : 0
    infoHeight = target
    let finish: () -> Void = { [weak self] in
      guard let self, self.infoHeight == 0 else { return }
      self.informationHost?.willMove(toParent: nil); self.informationHost?.view.removeFromSuperview()
      self.informationHost?.removeFromParent(); self.informationHost = nil
    }
    if UIAccessibility.isReduceMotionEnabled { layoutMedia(); finish() } else {
      let animation = UIViewPropertyAnimator(duration: 0.36,dampingRatio: 0.94) { self.layoutMedia() }
      animation.addCompletion { position in if position == .end { finish() } }
      infoAnimator = animation; animation.startAnimation()
    }
  }
  /// Freeze the visible geometry before reversing a drawer animation. The model
  /// height is already the destination while Core Animation is interpolating.
  func interruptInformation() {
    guard let infoAnimator else { return }
    let visibleHeight = information.layer.presentation()?.frame.height ?? infoHeight
    infoAnimator.stopAnimation(true); self.infoAnimator = nil
    infoHeight = visibleHeight
    UIView.performWithoutAnimation { layoutMedia() }
  }
  func toggleChrome() { guard !flying && !closing && infoHeight == 0 else { return }; chrome.toggle(); animate(duration: 0.18) { self.layoutMedia() } }
  func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> UIButton {
    let button = UIButton(type: .system); button.setImage(UIImage(systemName: symbol),for: .normal); button.tintColor = .white
    button.accessibilityLabel = NSLocalizedString(label,comment: ""); button.accessibilityIdentifier = id
    button.addAction(UIAction { _ in action() },for: .touchUpInside); return button
  }
  func animate(duration: TimeInterval = 0.36, velocity: CGFloat = 0, changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
    animator?.stopAnimation(true)
    if UIAccessibility.isReduceMotionEnabled { changes(); completion?(); return }
    let timing = UISpringTimingParameters(dampingRatio: 0.94,initialVelocity: CGVector(dx: 0,dy: min(4,abs(velocity)/800)))
    let animation = UIViewPropertyAnimator(duration: duration,timingParameters: timing)
    animation.addAnimations(changes); animation.addCompletion { _ in completion?() }; animator = animation; animation.startAnimation()
  }
  func imageRect() -> CGRect {
    let asset = session.current.asset; let size = CGSize(width: max(1,asset.pixelWidth),height: max(1,asset.pixelHeight))
    let scale = min(stage.bounds.width/size.width,stage.bounds.height/size.height)
    let frame = CGRect(x: stage.bounds.midX-size.width*scale/2,y: stage.bounds.midY-size.height*scale/2,width: size.width*scale,height: size.height*scale)
    return stage.convert(frame,to: view)
  }
  func enter() {
    layoutMedia(); guard let image = item.poster ?? session.current.image else { flying = false; backdrop.alpha = 1; layoutMedia(); return }
    let proxy = UIImageView(image: image); proxy.contentMode = .scaleAspectFill; proxy.clipsToBounds = true
    proxy.frame = view.convert(item.frame,from: nil); view.addSubview(proxy); stage.alpha = 0
    animate(changes: { proxy.frame = self.imageRect(); self.backdrop.alpha = 1 }) { [weak self] in
      guard let self else { return }; proxy.removeFromSuperview(); self.stage.alpha = 1; self.flying = false; self.layoutMedia()
    }
  }
  func dismissViewer(velocity: CGFloat = 0) {
    guard !flying && !closing else { return }; closing = true; pager.isScrollEnabled = false
    let destination = session.library.previewFrame?(session.current.asset.localIdentifier)
    if let image = session.current.image, let destination, infoHeight == 0 {
      let proxy = UIImageView(image: image); proxy.contentMode = .scaleAspectFill; proxy.clipsToBounds = true
      proxy.frame = imageRect(); view.addSubview(proxy); stage.alpha = 0
      animate(velocity: velocity,changes: {
        proxy.frame = self.view.convert(destination,from: nil); self.backdrop.alpha = 0; self.header.alpha = 0; self.footer.alpha = 0
      }) { self.session.stop(); self.closeViewer() }
    } else { animate(duration: 0.2,changes: { self.view.alpha = 0 }) { self.session.stop(); self.closeViewer() } }
  }
}
@MainActor private final class PreviewStripCell: UICollectionViewCell {
  let photo = UIImageView()
  weak var pipeline: ThumbnailPipeline?
  var request = PHInvalidImageRequestID, identity: String?
  override init(frame: CGRect) {
    super.init(frame: frame); photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; photo.layer.cornerRadius = 5; contentView.addSubview(photo)
    isAccessibilityElement = true; accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layoutSubviews() { super.layoutSubviews(); photo.frame = contentView.bounds }
  func configure(_ asset: PHAsset, selected: Bool, pipeline: ThumbnailPipeline) {
    setSelected(selected)
    accessibilityLabel = asset.creationDate?.formatted(date: .abbreviated,time: .shortened); accessibilityTraits = selected ? [.button,.selected] : .button
    guard identity != asset.localIdentifier else { return }; cancel(); self.pipeline = pipeline; identity = asset.localIdentifier
    photo.image = pipeline.poster(for: asset)
    request = pipeline.request(asset,pixels: 120) { [weak self] image,_ in guard let self, self.identity == asset.localIdentifier else { return }; if let image { self.photo.image = image } }
  }
  func setSelected(_ selected: Bool) { photo.layer.borderColor = UIColor.white.cgColor; photo.layer.borderWidth = selected ? 2 : 0 }
  func cancel() { pipeline?.cancel(request); request = PHInvalidImageRequestID; identity = nil }
  override func prepareForReuse() { super.prepareForReuse(); cancel(); photo.image = nil }
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

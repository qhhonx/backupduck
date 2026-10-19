import AppKit
import AVFoundation
import Photos
import SwiftUI

struct MacLibraryGrid: NSViewRepresentable {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var navigation: MacLibraryNavigation
  @ObservedObject var networkPolicy = PreviewNetworkPolicy.shared
  var preparationRevision: String = ""
  var queueRevision: Int64
  var receiverID: String?
  var columns: Int
  var selecting = true
  var active = true
  /// The overview table prefill is app-wide and keyed by one fetch: only the
  /// library grid may start it. An album grid reads the tables but would cancel
  /// the library's pass and make it start over when the album closes.
  var prefillsTables = true
  var preview: (PHAsset) -> Void = { _ in }
  var enterSelection: () -> Void = {}
  var resize: (Int) -> Void = { _ in }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let layout = LibraryTimelineLayout(library: library, mode: .all, target: 135)
    // The first layout must already use the chosen column count; a second pass
    // would change the content height under a restored offset.
    layout.requestedColumns = columns
    layout.columns = columns
    layout.denseThreshold = MacLibraryDensity.denseThreshold
    let collection = LibraryCollectionView()
    collection.collectionViewLayout = layout
    collection.autoresizingMask = [.width]
    collection.backgroundColors = [.clear]
    collection.isSelectable = true
    collection.allowsMultipleSelection = true
    let canvas = MacDenseCanvas(frame: .zero)
    canvas.autoresizingMask = [.width, .height]
    canvas.isHidden = true
    collection.addSubview(canvas)
    context.coordinator.denseCanvas = canvas
    collection.denseHit = { [weak coordinator = context.coordinator] point in coordinator?.denseIndex(at: point) }
    collection.drill = { [weak coordinator = context.coordinator] index in coordinator?.drillDown(from: index) }
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(TimelineDateHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    collection.dataSource = context.coordinator
    collection.delegate = context.coordinator
    collection.toggleSelection = { [weak coordinator = context.coordinator] path in
      coordinator?.toggleSelection(at: path)
    }
    collection.enterSelection = { [weak coordinator = context.coordinator] path in coordinator?.beginSelection(at: path) }
    collection.preview = { [weak coordinator = context.coordinator] path in
      guard let coordinator, let asset = coordinator.asset(at: path.item) else { return }
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
    library.previewPoster = { [weak collection] id in
      collection?.visibleItems().compactMap { $0 as? PhotoCell }.first { $0.assetID == id }?.displayedImage
    }
    library.previewFrame = { [weak collection] id in
      guard let cell = collection?.visibleItems().compactMap({ $0 as? PhotoCell }).first(where: { $0.assetID == id }) else { return nil }
      return cell.view.convert(cell.view.bounds, to: nil)
    }
    collection.postsFrameChangedNotifications = true
    context.coordinator.frameObserver = NotificationCenter.default.addObserver(
      forName: NSView.frameDidChangeNotification, object: collection, queue: .main
    ) { [weak coordinator = context.coordinator] _ in
      Task { @MainActor in coordinator?.contentResized() }
    }
    // All Photos: the visible cell showing a token (source) or an asset (landing).
    navigation.coverFlight[.all] = { [weak c = context.coordinator] token in
      c?.flightCell { $0.assetID == token || $0.presentationID == token }
    }
    navigation.coverLanding[.all] = { [weak c = context.coordinator] token, asset in
      c?.flightCell { $0.assetID == asset } ?? c?.flightCell { $0.presentationID == token || $0.assetID == token }
    }
    navigation.focusCandidate[.all] = { [weak c = context.coordinator] in c?.centerToken() }
    navigation.cellFrame = { [weak collection, weak scroll] id in
      guard let collection, let scroll,
        let cell = collection.visibleItems().compactMap({ $0 as? PhotoCell }).first(where: { $0.assetID == id || $0.presentationID == id })
      else { return nil }
      let rect = cell.view.convert(cell.view.bounds, to: scroll)
      guard rect.intersects(scroll.bounds) else { return nil }
      return CGRect(x: rect.minX, y: scroll.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }
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
    collection.isSelectable = true
    // Level layers stay mounted and cross-fade in AppKit: a SwiftUI opacity swap
    // cut between levels and showed a blank page on first use.
    scroll.setAccessibilityHidden(navigation.level != .all)
    MacLevelFade.apply(scroll,layer: .all,current: navigation.level)
    // Changing visibility inside a SwiftUI update pass makes AppKit query the
    // key view loop, which reads the same attribute graph and cycles. Apply it
    // once per change, after the pass.
    if c.appliedActive != active {
      c.appliedActive = active
      DispatchQueue.main.async { [weak scroll, weak collection] in
        scroll?.isHidden = !active
        collection?.setAccessibilityHidden(!active)
      }
    }
    for path in collection.indexPathsForVisibleItems() {
      (collection.item(at: path) as? PhotoCell)?.setSelectionVisible(true)
    }
    if !c.magnifying { c.syncDensity(columns: columns, layout: layout) }
    var reloaded = false
    if c.generation != library.generation {
      reloaded = true
      c.stopLayoutAnimation(); c.removeZoomStage(); c.magnifying = false
      let sameFilter = (c.filter == nil || c.filter == library.filter)
        && (c.scrollResetGeneration == nil || c.scrollResetGeneration == library.scrollResetGeneration)
      if sameFilter, c.generation >= 0 { c.rememberScroll() }
      let offset = sameFilter ? library.scrollOffset : .zero
      let anchor = sameFilter ? library.scrollAnchorID : nil
      let inset = library.scrollAnchorInset
      c.restoring = true
      if !sameFilter { c.pinnedToNewest = true }
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
        c.ensureDocumentHeight()
        let maximum = max(0, c.settledContentHeight - scroll.contentView.bounds.height)
        if c.pinnedToNewest {
          // Rest at the newest edge, at the bottom.
          target.y = maximum
        } else if let index = c.displayIndex(of: anchor) {
          if let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame {
            target.y = frame.minY + inset
          }
        }
        target.y = min(maximum, max(0, target.y))
        scroll.contentView.scroll(to: target)
        scroll.reflectScrolledClipView(scroll.contentView)
        c.restoring = false
        c.applyingSelection = false
        c.applyPendingFocus()
        c.scrolled()
      }
      scroll.needsLayout = true
      scroll.layoutSubtreeIfNeeded()
    } else if c.count < library.loaded {
      // Older pages are presented above the oldest loaded row: keep the item at
      // the top of the viewport where it is.
      let clip = scroll.contentView
      let atNewestEdge = clip.bounds.maxY >= c.settledContentHeight - 2
      let top = c.visibleRange()?.first
      let topModel = top.map { c.count - 1 - $0 }
      let topY = top.map { layout.frame(at: $0).minY - clip.bounds.minY }
      c.count = library.loaded
      c.zoomStage?.count = c.count
      c.appliedSelection = nil
      collection.reloadData()
      collection.needsLayout = true; collection.layoutSubtreeIfNeeded()
      c.pinnedToNewest = atNewestEdge
      c.ensureDocumentHeight()
      if atNewestEdge {
        // Resting at the newest edge stays there as older rows appear above.
        clip.scroll(to: CGPoint(x: 0, y: max(0, c.settledContentHeight - clip.bounds.height)))
        scroll.reflectScrolledClipView(clip)
      } else if let topModel, let topY,
        let frame = layout.layoutAttributesForItem(at: IndexPath(item: c.count - 1 - topModel, section: 0))?.frame {
        clip.scroll(to: CGPoint(x: 0, y: max(0, frame.minY - topY)))
        scroll.reflectScrolledClipView(clip)
      }
    }
    // Paging older rows in while scrolling republished the library, which
    // re-evaluated the whole window and relaid the toolbar (about 40 ms) every
    // few hundred photos. The Mac reads the remaining rows in one background
    // pass shortly after the newest page is on screen.
    if library.hasMoreRows, c.bulkGeneration != library.generation {
      c.bulkGeneration = library.generation
      let library = library, generation = library.generation
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        for _ in 0..<40 where library.hasMoreRows && library.generation == generation {
          await library.loadAllRows()
          if library.hasMoreRows { try? await Task.sleep(nanoseconds: 250_000_000) }
        }
      }
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
    if c.focusRevision != navigation.focusRevision, let token = navigation.focusToken,
      c.displayIndex(of: token) != nil {
      c.focusRevision = navigation.focusRevision
      c.pinnedToNewest = false
      c.pendingFocus = token
      // After a reload the restore pass applies it, once the layout is current.
      c.applyPendingFocus()
    }
    if c.newestRevision != navigation.newestRevision {
      c.newestRevision = navigation.newestRevision
      c.scrollToNewest()
    }
    if c.originalAspect != navigation.originalAspect {
      c.originalAspect = navigation.originalAspect; c.refreshVisibleImages()
    }
    if c.appliedSelection != library.selection {
      c.applyingSelection = true
      collection.selectionIndexPaths = c.selectedPaths()
      c.appliedSelection = library.selection
      c.applyingSelection = false
    }
    c.updateFooter()
    if prefillsTables { MacThumbnailTables.prefill(library.fetch) }
  }
  static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
    coordinator.stopLayoutAnimation()
    coordinator.removeZoomStage()
    coordinator.rememberScroll()
    coordinator.refresh.cancel()
    if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
    if let observer = coordinator.frameObserver { NotificationCenter.default.removeObserver(observer) }
    coordinator.parent.library.previewPoster = nil
    coordinator.parent.library.previewFrame = nil
    coordinator.parent.navigation.cellFrame = nil
  }
  @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate
  {
    var networkAllowed = false
    var originalAspect = false
    var focusRevision = 0
    var magnifying = false
    var appliedActive: Bool?
    private var appliedColumns: Int?
    /// True while the viewport rests at the newest edge (the bottom). Older pages
    /// and reloads then keep it there instead of preserving a stale item.
    var pinnedToNewest = true
    var newestRevision = 0
    /// Returns to the newest edge, easing instead of jumping.
    func scrollToNewest() {
      guard let collection, let scroll = collection.enclosingScrollView else { return }
      pinnedToNewest = true
      ensureDocumentHeight()
      let target = max(0, settledContentHeight - scroll.contentView.bounds.height)
      guard abs(scroll.contentView.bounds.minY - target) > 1 else { return }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.35
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        scroll.contentView.animator().setBoundsOrigin(CGPoint(x: 0, y: target))
      } completionHandler: { [weak self, weak scroll] in
        Task { @MainActor in
          guard let scroll else { return }
          scroll.reflectScrolledClipView(scroll.contentView); self?.scrolled()
        }
      }
    }
    var denseCanvas: MacDenseCanvas?
    /// Empty slots before the first photo in the settled grid, so a focal photo
    /// keeps its column when the density changes (as on iPhone).
    var leading = 0
    private var gestureLeading: [Int: Int] = [:]
    private var settleLeading = 0
    /// Leading slots that keep the anchor in the column it occupies on screen.
    private func phase(for columns: Int) -> Int {
      if let cached = gestureLeading[columns] { return cached }
      guard let anchor, let stage = zoomStage else { return 0 }
      let pitch = naturalPitch(columns), side = pitch - gap(columns)
      let column = min(columns - 1, max(0, Int(((stage.focus.x - side * anchorFractionX - inset(columns)) / pitch).rounded())))
      let value = ((column - anchor % columns) % columns + columns) % columns
      gestureLeading[columns] = value
      return value
    }
    private var layoutDense: Bool {
      (collection?.collectionViewLayout as? LibraryTimelineLayout)?.isDense ?? false
    }
    /// Draws the settled overview mosaic for the rows in view.
    func updateDense() {
      guard let collection, let canvas = denseCanvas,
        let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      let dense = layout.isDense
      canvas.isHidden = !dense
      guard dense else { canvas.reset(); return }
      canvas.pipeline = parent.library.thumbnails
      canvas.assetAt = { [weak self] index in self?.asset(at: index) }
      canvas.factAt = { [weak self] index in self?.fact(at: index) }
      canvas.count = count
      canvas.frame = collection.bounds
      let columns = max(1, layout.columns)
      let topInset = collection.enclosingScrollView?.contentInsets.top ?? 0
      canvas.render(columns: columns, origin: CGPoint(x: inset(columns), y: 4),
        pitch: naturalPitch(columns), visible: collection.visibleRect, leading: leading,
        pinTop: collection.visibleRect.minY + topInset + 6)
    }
    func denseIndex(at point: CGPoint) -> Int? {
      guard layoutDense, let canvas = denseCanvas, let layout = collection?.collectionViewLayout as? LibraryTimelineLayout
      else { return nil }
      let columns = max(1, layout.columns)
      return canvas.index(at: point, columns: columns, origin: CGPoint(x: inset(columns), y: 4),
        pitch: naturalPitch(columns), leading: leading)
    }
    /// Index range in view for the settled grid, whether cells or mosaic.
    func visibleRange() -> (first: Int, last: Int)? {
      guard let collection else { return nil }
      if layoutDense, let layout = collection.collectionViewLayout as? LibraryTimelineLayout {
        let columns = max(1, layout.columns), pitch = naturalPitch(columns)
        let rect = collection.visibleRect
        let rowStart = max(0, Int(floor((rect.minY - 4) / pitch)))
        let rowEnd = Int(ceil((rect.maxY - 4) / pitch))
        guard count > 0 else { return nil }
        return (max(0, min(count - 1, rowStart * columns - leading)), max(0, min(count - 1, (rowEnd + 1) * columns - 1 - leading)))
      }
      // Called on every scroll step; the ends need no sort.
      let items = collection.indexPathsForVisibleItems().map(\.item)
      guard let first = items.min(), let last = items.max() else { return nil }
      return (first, last)
    }
    /// A click on an overview tile steps toward the grid around that photo.
    func drillDown(from index: Int) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        let scroll = collection.enclosingScrollView else { return }
      let current = stopIndex(layout.columns)
      let target = columnStops[max(min(2, columnStops.count - 1), current - 1)]
      guard target != layout.columns else { return }
      let frame = layout.frame(at: index)
      anchor = index; anchorFraction = 0.5; anchorFractionX = 0.5
      anchorY = frame.midY - scroll.contentView.bounds.minY
      keepsTop = false
      parent.resize(target)
      forcedAnchor = true
      animateLayout(columns: target)
    }
    var forcedAnchor = false
    /// Item to bring to the centre once the layout is current (viewer return,
    /// level change). Consumed by `applyPendingFocus`.
    var pendingFocus: String?
    func applyPendingFocus() {
      guard let token = pendingFocus, let collection, let scroll = collection.enclosingScrollView,
        let index = displayIndex(of: token) else { return }
      pendingFocus = nil
      ensureDocumentHeight()
      collection.needsLayout = true; collection.layoutSubtreeIfNeeded()
      guard let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      let frame = layout.frame(at: index)
      let clip = scroll.contentView
      let maximum = max(0, settledContentHeight - clip.bounds.height)
      clip.scroll(to: CGPoint(x: 0, y: min(maximum, max(0, frame.midY - clip.bounds.height / 2))))
      scroll.reflectScrolledClipView(clip)
      pinnedToNewest = false
      rememberScroll()
    }
    var animationTarget: (LibraryViewMode, CGFloat)?
    private var anchor: Int?
    private var anchorFraction: CGFloat = 0
    private var anchorY: CGFloat = 0
    private var keepsTop = false
    var parent: MacLibraryGrid
    weak var collection: NSCollectionView?
    var observer: NSObjectProtocol?
    var frameObserver: NSObjectProtocol?
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
    var zoomStage: MacGridZoomStage?
    private var anchorFractionX: CGFloat = 0.5
    // Shared zoom rules (apps/apple/Shared/GridZoom.swift). The host owns tiles
    // and scrolling; every threshold, curve and boundary comes from GridZoom.
    private var columnStops: [Int] = []
    private var stops = GridZoom.Stops(pitches: [1])
    private var pinch: GridZoom.Pinch?
    private var direction: GridZoom.Direction?
    private var boundary: GridZoom.Boundary?
    private var settle: GridZoom.Settle?
    private var samples: [(CFTimeInterval, CGFloat)] = []
    private var settleLink: CADisplayLink?
    private var settleColumns = 0
    private var finalOffset: CGFloat = 0
    /// Row count and newest-edge state when the settle's offset was chosen. The
    /// whole library can finish loading mid-settle; the offset is then re-derived
    /// instead of applying one computed for the shorter document.
    private var settleCount = 0
    private var settleAtNewest = false
    private var startOffset: CGFloat = 0
    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func stopLayoutAnimation() {
      settleLink?.invalidate(); settleLink = nil; settle = nil; animationTarget = nil; restoring = false
    }
    /// A layout pass changed the document height. A viewport resting at the
    /// newest edge stays there until the person scrolls away.
    func contentResized() {
      // The first update can run before the grid has a width (a sheet's first
      // pass), when the requested column count cannot be applied yet.
      if appliedColumns == nil, width() > 120, let layout = collection?.collectionViewLayout as? LibraryTimelineLayout {
        syncDensity(columns: parent.columns, layout: layout)
      }
      guard pinnedToNewest, zoomStage == nil, !restoring, let collection, let scroll = collection.enclosingScrollView else { return }
      let clip = scroll.contentView, height = settledContentHeight
      guard clip.bounds.maxY < height - 2 else { return }
      ensureDocumentHeight()
      clip.scroll(to: CGPoint(x: 0, y: max(0, height - clip.bounds.height)))
      scroll.reflectScrolledClipView(clip)
      updateDense()
    }
    func removeZoomStage() {
      zoomStage?.stop(); zoomStage?.removeFromSuperview(); zoomStage = nil
      collection?.alphaValue = 1
    }
    private func width() -> CGFloat {
      collection?.enclosingScrollView?.contentSize.width ?? collection?.bounds.width ?? 1
    }
    private func viewportHeight() -> CGFloat {
      collection?.enclosingScrollView?.contentSize.height ?? collection?.bounds.height ?? 1
    }
    /// Cell side plus the 2 pt gap for a column count, matching the collection layout.
    /// Displayed cell side for the settled column count; sizes thumbnail requests.
    var cellSide: CGFloat {
      let columns = (collection?.collectionViewLayout as? LibraryTimelineLayout)?.columns ?? parent.columns
      return naturalPitch(max(1,columns))-2
    }
    private func inset(_ columns: Int) -> CGFloat { MacLibraryDensity.isDense(columns) ? 0 : 2 }
    private func gap(_ columns: Int) -> CGFloat { MacLibraryDensity.isDense(columns) ? 0 : 2 }
    private func naturalPitch(_ columns: Int) -> CGFloat {
      let gap = gap(columns), inset = inset(columns)
      return max(1,floor((width()-inset*2-CGFloat(columns-1)*gap)/CGFloat(columns)))+gap
    }
    private func contentHeight(_ columns: Int,leading: Int? = nil) -> CGFloat {
      let lead = leading ?? self.leading
      let pitch = naturalPitch(columns), slots = count+lead, rows = (slots+columns-1)/columns
      let side = pitch-gap(columns)
      let last = slots%columns == 0 ? pitch : side
      return 4+CGFloat(max(0,rows-1))*pitch+last+16+Self.footerHeight
    }
    static let footerHeight: CGFloat = 56
    /// Content height for the current count and column count, independent of
    /// whether AppKit has prepared the layout yet.
    /// AppKit sizes the document view lazily; scrolling to a far offset before
    /// that clamps to the old height. Size it from the known content first.
    func ensureDocumentHeight() {
      guard let collection, let scroll = collection.enclosingScrollView else { return }
      let height = settledContentHeight, width = scroll.contentSize.width
      if abs(collection.frame.height - height) > 0.5 || abs(collection.frame.width - width) > 0.5 {
        collection.setFrameSize(NSSize(width: width, height: height))
      }
    }
    var settledContentHeight: CGFloat {
      let layout = collection?.collectionViewLayout as? LibraryTimelineLayout
      return contentHeight(max(1, layout?.requestedColumns ?? layout?.columns ?? parent.columns))
    }
    private let footer: NSTextField = {
      let label = NSTextField(labelWithString: "")
      label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
      label.alignment = .center; label.maximumNumberOfLines = 1
      return label
    }()
    private var footerKey = ""
    // Items are presented oldest first (newest at the bottom, as in Photos). The
    // library model indexes newest first, so every display index is mirrored
    // against the number of items the collection currently holds.
    func asset(at item: Int) -> PHAsset? { parent.library.asset(at: count - 1 - item) }
    /// Capture date from the prefill's facts when known, so scrolling an
    /// overview does not fetch a PhotoKit batch for two dates.
    func date(at item: Int) -> Date? {
      if let fact = fact(at: item) { return fact.date }
      return asset(at: item)?.creationDate
    }
    func fact(at item: Int) -> MacThumbnailTables.Fact? {
      let library = parent.library
      return library.rawIndex(at: count - 1 - item).flatMap { MacThumbnailTables.fact(library.fetch, at: $0) }
    }
    func identifier(at item: Int) -> String? { parent.library.identifier(at: count - 1 - item) }
    /// A visible cell as a flight endpoint, in window coordinates.
    func flightCell(_ match: (PhotoCell) -> Bool) -> MacCoverFlightSource? {
      guard let collection, let scroll = collection.enclosingScrollView,
        let cell = collection.visibleItems().compactMap({ $0 as? PhotoCell }).first(where: match),
        let id = cell.assetID, let window = cell.view.window else { return nil }
      let frame = cell.photoRect
      guard cell.view.convert(frame, to: scroll).intersects(scroll.bounds) else { return nil }
      return MacCoverFlightSource(rect: cell.view.convert(frame, to: nil), image: cell.displayedImage,
        radius: cell.photoCornerRadius, assetID: id, clip: MacCoverFlightSource.clip(of: scroll), window: window)
    }
    /// The photo a level change keeps: the selection when it is on screen,
    /// otherwise the cell nearest the centre of the visible area.
    func centerToken() -> String? {
      guard let collection, let scroll = collection.enclosingScrollView else { return nil }
      let visible = collection.visibleItems().compactMap { $0 as? PhotoCell }
      if let selected = visible.first(where: { $0.isSelected }) { return selected.presentationID ?? selected.assetID }
      // Keep the photo the last level change landed on while it is still on screen.
      if let focus = parent.navigation.focusToken,
        let cell = visible.first(where: { $0.presentationID == focus || $0.assetID == focus }),
        scroll.contentView.bounds.intersects(cell.view.frame) { return focus }
      let clip = scroll.contentView.bounds
      let center = CGPoint(x: clip.midX, y: clip.midY)
      return visible.min { hypot($0.view.frame.midX - center.x, $0.view.frame.midY - center.y)
        < hypot($1.view.frame.midX - center.x, $1.view.frame.midY - center.y) }.flatMap { $0.presentationID ?? $0.assetID }
    }
    func displayIndex(of identifier: String?) -> Int? {
      parent.library.index(of: identifier).flatMap { $0 < count ? count - 1 - $0 : nil }
    }
    func selectedPaths() -> Set<IndexPath> {
      Set(parent.library.selection.compactMap { displayIndex(of: $0) }.map { IndexPath(item: $0, section: 0) })
    }
    /// Totals under the last row, shown at the newest edge as Photos does. No
    /// sync state is invented: only counts the library fetch actually reports.
    func updateFooter() {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      layout.footerHeight = Self.footerHeight
      if footer.superview !== collection { collection.addSubview(footer) }
      let key = "\(parent.library.generation)|\(count)"
      if key != footerKey {
        footerKey = key
        if let fetch = parent.library.fetch {
          footer.stringValue = String(format: NSLocalizedString("library_footer_counts", comment: ""),
            fetch.countOfAssets(with: .image).formatted(), fetch.countOfAssets(with: .video).formatted())
        } else { footer.stringValue = "" }
      }
      let height = layout.collectionViewContentSize.height
      footer.frame = CGRect(x: 0,y: max(0,height-Self.footerHeight+14),width: collection.bounds.width,height: 20)
      footer.isHidden = count == 0
    }
    /// Item size whose column count is exactly `columns`.
    private func itemSize(forColumns columns: Int) -> CGFloat {
      max(4,(width()-inset(columns)*2)/CGFloat(columns)-gap(columns)-0.01)
    }
    /// Applies the requested column count from the toolbar or a restored state.
    func syncDensity(columns requested: Int, layout: LibraryTimelineLayout) {
      guard width() > 120, zoomStage == nil else { return }
      let target = itemSize(forColumns: requested)
      if let animation = animationTarget, abs(animation.1-target) < 0.5 { return }
      layout.requestedColumns = requested
      guard layout.columns != requested || layout.mode != .all || abs(layout.target-target) > 0.5 else {
        appliedColumns = requested; return
      }
      let animate = appliedColumns != nil && appliedColumns != requested && !restoring
      appliedColumns = requested
      if animate { animateLayout(columns: requested) } else {
        layout.target = target
        layout.leadingSlots = leading
        layout.adopt(mode: .all,columns: requested)
        collection?.needsLayout = true
      }
    }
    private func rebuildStops(_ layout: LibraryTimelineLayout) {
      MacLibraryDensity.overview = MacLibraryDensity.overview(forWidth: width())
      let usable = MacLibraryDensity.columns.filter { naturalPitch($0) >= 8 }
      columnStops = usable.isEmpty ? [MacLibraryDensity.standard] : usable
      stops = GridZoom.Stops(pitches: columnStops.map(naturalPitch))
    }
    private func stopIndex(_ columns: Int) -> Int {
      columnStops.firstIndex(of: columns) ?? columnStops.indices.min {
        abs(columnStops[$0]-columns) < abs(columnStops[$1]-columns)
      } ?? 0
    }
    /// The anchor's point in a column count's content coordinates at natural pitch.
    private func anchorContentPoint(columns: Int,leading: Int? = nil) -> CGPoint {
      let pitch = naturalPitch(columns), a = (anchor ?? 0)+(leading ?? self.leading)
      let gap = gap(columns), inset = inset(columns)
      return CGPoint(x: inset+CGFloat(a%columns)*pitch+anchorFractionX*(pitch-gap),
        y: 4+CGFloat(a/columns)*pitch+anchorFraction*(pitch-gap))
    }
    private func makeStage(_ layout: LibraryTimelineLayout, _ scroll: NSScrollView, _ collection: NSCollectionView) -> MacGridZoomStage? {
      guard let anchor else { return nil }
      let frame = layout.frame(at: anchor)
      let focus = CGPoint(x: frame.minX+frame.width*anchorFractionX,y: anchorY)
      let stage = MacGridZoomStage(count: count,anchor: anchor,fraction: CGPoint(x: anchorFractionX,y: anchorFraction),
        columns: layout.columns,pitch: frame.width+2,focus: focus)
      stage.frame = scroll.contentView.frame; stage.autoresizingMask = [.width,.height]
      stage.referenceSide = { [weak self] columns in (self?.naturalPitch(columns) ?? 3)-(self?.gap(columns) ?? 2) }
      stage.denseAsset = { [weak self] index in self?.asset(at: index) }
      stage.denseFact = { [weak self] index in self?.fact(at: index) }
      stage.thumbnails = parent.library.thumbnails
      stage.makeTile = { [weak self] index, side in
        guard let self, let asset = self.asset(at: index) else { return NSView() }
        let tile = MacZoomMediaTile()
        tile.frame.size = CGSize(width: side,height: side)
        let scale = collection.window?.backingScaleFactor ?? 2
        tile.configure(asset, side: side, pixels: side*scale, pipeline: self.parent.library.thumbnails,
          originalAspect: self.parent.navigation.originalAspect,
          selected: self.parent.library.selection.contains(self.identifier(at: index) ?? ""), scale: scale)
        if tile.displayedImage == nil,
          let visible = collection.visibleItems().compactMap({ $0 as? PhotoCell }).first(where: { $0.assetID == asset.localIdentifier }),
          let image = visible.displayedImage { tile.show(image) }
        return tile
      }
      stage.releaseTile = { ($0 as? MacZoomMediaTile)?.cancel() }
      return stage
    }
    private func beginStage() {
      guard zoomStage == nil, let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        let scroll = collection.enclosingScrollView,
        let stage = makeStage(layout,scroll,collection) else { return }
      rebuildStops(layout)
      scroll.addSubview(stage); zoomStage = stage
      gestureLeading = [layout.columns: leading]
      stage.ensureFace(layout.columns,opacity: 1,leading: leading)
      stage.render()
      startOffset = scroll.contentView.bounds.minY
      collection.alphaValue = 0.001
    }
    private func captureAnchor(_ point: CGPoint? = nil) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout, let scroll = collection.enclosingScrollView else { return }
      let wasAtTop = point == nil && scroll.contentView.bounds.minY <= 1
      let point = point ?? CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
      if layout.isDense {
        // No cells exist in an overview: resolve the photo under the point from
        // the lattice, clamped to the last row.
        let columns = max(1, layout.columns), pitch = naturalPitch(columns)
        let col = min(columns - 1, max(0, Int(point.x / pitch)))
        let row = max(0, Int((point.y - 4) / pitch))
        anchor = count > 0 ? min(count - 1, max(0, row * columns + col - leading)) : nil
      } else {
        let paths = collection.indexPathsForVisibleItems()
        anchor = paths.min { a,b in
          let ra = layout.frame(at: a.item), rb = layout.frame(at: b.item)
          return hypot(ra.midX-point.x,ra.midY-point.y) < hypot(rb.midX-point.x,rb.midY-point.y)
        }?.item
      }
      if let anchor {
        let frame = layout.frame(at: anchor)
        anchorFraction = min(1,max(0,(point.y-frame.minY)/max(1,frame.height)))
        anchorFractionX = min(1,max(0,(point.x-frame.minX)/max(1,frame.width)))
        anchorY = point.y-scroll.contentView.bounds.minY
      }
      keepsTop = wasAtTop
    }
    private func placeOffset(_ offset: CGFloat) {
      guard let collection, let scroll = collection.enclosingScrollView else { return }
      collection.needsLayout = true; collection.layoutSubtreeIfNeeded()
      let limit = max(0,(collection.collectionViewLayout?.collectionViewContentSize.height ?? 0)-scroll.contentView.bounds.height)
      scroll.contentView.scroll(to: CGPoint(x: 0,y: min(limit,max(0,offset)))); scroll.reflectScrolledClipView(scroll.contentView)
      if let layout = collection.collectionViewLayout as? LibraryTimelineLayout {
        for path in collection.indexPathsForVisibleSupplementaryElements(ofKind: LibraryTimelineLayout.headerKind) {
          (collection.supplementaryView(forElementKind: LibraryTimelineLayout.headerKind, at: path) as? TimelineDateHeader)?.setTitle(layout.title(at: path.item))
        }
      }
    }
    /// Slider and menu changes settle through the same stage as a pinch.
    func animateLayout(columns: Int) {
      guard collection != nil else { return }
      stopLayoutAnimation()
      removeZoomStage()
      if forcedAnchor { forcedAnchor = false } else { captureAnchor() }
      if !reducedMotion { beginStage() }
      restoring = true
      finishStage(columns: columns,size: itemSize(forColumns: columns),cancelled: false)
    }
    private func finishStage(columns: Int,size: CGFloat,cancelled: Bool) {
      if MacLibraryDensity.isDense(columns) { Task { await parent.library.loadAllRows() } }
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        let scroll = collection.enclosingScrollView else { return }
      animationTarget = (.all,size)
      settleColumns = columns
      settleLeading = zoomStage == nil ? leading : phase(for: columns)
      let natural = naturalPitch(columns), focusInContent = anchorContentPoint(columns: columns,leading: settleLeading)
      let offset = cancelled ? startOffset : keepsTop ? 0 : GridZoom.offset(
        focusInContent: focusInContent.y,screenFocus: zoomStage?.focus.y ?? anchorY,
        contentHeight: contentHeight(columns,leading: settleLeading),viewportHeight: scroll.contentSize.height)
      finalOffset = offset
      settleCount = count
      // A short document fits the viewport and reads as "at the top", so the
      // newest-edge state the zoom started from decides.
      settleAtNewest = !cancelled && (pinnedToNewest || (!keepsTop
        && offset >= max(0, contentHeight(columns, leading: settleLeading) - scroll.contentSize.height) - 2))
      guard let stage = zoomStage, !reducedMotion else {
        completeStage(); return
      }
      stage.ensureFace(columns,opacity: 0,leading: settleLeading)
      stage.show(columns,animated: true)
      stage.hurryBlend(within: 0.15)
      let now = CACurrentMediaTime()
      settle = GridZoom.Settle(start: now,pitch: stage.pitch,focus: stage.focus,
        velocity: GridZoom.Settle.velocity(of: samples),targetPitch: natural,
        targetFocus: CGPoint(x: focusInContent.x,y: focusInContent.y-offset))
      settleLink?.invalidate()
      // Frames follow the display, not a timer: a free-running timer beats
      // against the refresh and shows as judder on every settle.
      let link = scroll.displayLink(target: self,selector: #selector(settleTick(_:)))
      link.add(to: .main,forMode: .common); settleLink = link
    }
    @objc private func settleTick(_ link: CADisplayLink) { settleFrame() }
    // MARK: Scroll benchmark
    /// `-scroll-benchmark`: after each density change the grid scrolls itself
    /// towards older photos at 1500 pt/s for four seconds, driven by the display,
    /// and appends frame statistics to /tmp/scroll-benchmark.log.
    static let scrollBenchmark = ProcessInfo.processInfo.arguments.contains("-scroll-benchmark")
    private var benchLink: CADisplayLink?, benchStart: CFTimeInterval = 0, benchLast: CFTimeInterval = 0
    private var benchIntervals: [Double] = [], benchScheduled = false, benchDuration: Double = 1.0 / 60
    var bulkGeneration = -1
    func scheduleBenchmark() {
      guard Self.scrollBenchmark, !benchScheduled else { return }
      benchScheduled = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.startBenchmark() }
    }
    private func startBenchmark() {
      guard let scroll = collection?.enclosingScrollView else { benchScheduled = false; return }
      benchIntervals = []; benchLast = 0; benchStart = CACurrentMediaTime()
      let link = scroll.displayLink(target: self, selector: #selector(benchTick(_:)))
      link.add(to: .main, forMode: .common); benchLink = link
    }
    @objc private func benchTick(_ link: CADisplayLink) {
      guard let scroll = collection?.enclosingScrollView else { return }
      if benchLast > 0 { benchIntervals.append(link.timestamp - benchLast) }
      benchLast = link.timestamp
      benchDuration = max(0.004, link.targetTimestamp - link.timestamp)
      let clip = scroll.contentView
      let step = 1500 * (benchIntervals.last ?? benchDuration)
      clip.scroll(to: CGPoint(x: 0, y: max(0, clip.bounds.minY - step))); scroll.reflectScrolledClipView(clip)
      guard CACurrentMediaTime() - benchStart > 4 || clip.bounds.minY <= 0 else { return }
      link.invalidate(); benchLink = nil; benchScheduled = false
      let total = benchIntervals.reduce(0, +)
      let hitches = benchIntervals.filter { $0 > benchDuration * 1.5 }
      let hitchTime = hitches.reduce(0) { $0 + ($1 - benchDuration) }
      let sorted = benchIntervals.sorted()
      let at = benchIntervals.indices.filter { benchIntervals[$0] > benchDuration * 1.5 }.map(String.init).joined(separator: ",")
      let line = String(format: "columns=%d frames=%d refresh=%.0fHz mean=%.1fms p99=%.1fms max=%.1fms hitches=%d hitch-ratio=%.1fms/s at=%@\n",
        (collection?.collectionViewLayout as? LibraryTimelineLayout)?.columns ?? 0, benchIntervals.count, 1 / benchDuration,
        total / Double(max(1, benchIntervals.count)) * 1000, (sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.99)]) * 1000,
        (sorted.last ?? 0) * 1000, hitches.count, total > 0 ? hitchTime / total * 1000 : 0, at)
      if let h = FileHandle(forWritingAtPath: "/tmp/scroll-benchmark.log") { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!) }
      else { try? line.write(toFile: "/tmp/scroll-benchmark.log", atomically: false, encoding: .utf8) }
    }
    private func settleFrame() {
      guard let stage = zoomStage, let settle else { stopLayoutAnimation(); return }
      let now = CACurrentMediaTime()
      stage.advanceBlend(to: now)
      let state = settle.state(at: now)
      stage.pitch = state.pitch; stage.focus = state.focus
      stage.render()
      // Visually settled well before the numeric tolerance: half a point of
      // pitch and one point of focus, or 0.6 s, whichever comes first.
      let close = abs(state.pitch-settle.targetPitch) < 0.5
        && hypot(state.focus.x-settle.targetFocus.x,state.focus.y-settle.targetFocus.y) < 1
      if (close || now-settle.start > 0.6), !stage.isBlending {
        // Hand off at the exact destination pose so the collection adopts
        // without a sub-point shift.
        stage.pitch = settle.targetPitch; stage.focus = settle.targetFocus
        stage.render()
        completeStage()
      }
    }
    private func completeStage() {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        let target = animationTarget else { stopLayoutAnimation(); removeZoomStage(); return }
      settleLink?.invalidate(); settleLink = nil; settle = nil
      leading = settleLeading
      layout.requestedColumns = settleColumns
      layout.leadingSlots = leading
      layout.target = target.1
      layout.adopt(mode: target.0,columns: settleColumns)
      appliedColumns = settleColumns
      if count != settleCount {
        if settleAtNewest {
          finalOffset = max(0, settledContentHeight - viewportHeight())
        } else if let anchor {
          // Older rows arrived above: the anchor moved down by the new items.
          let columns = max(1, settleColumns), pitch = naturalPitch(columns)
          let before = (anchor + leading) / columns, after = (anchor + count - settleCount + leading) / columns
          finalOffset += CGFloat(after - before) * pitch
        }
        settleCount = count
      }
      placeOffset(finalOffset); refreshVisibleImages(); updateDense()
      pinnedToNewest = finalOffset >= max(0, settledContentHeight - viewportHeight()) - 2
      if let stage = zoomStage {
        for item in collection.visibleItems().compactMap({ $0 as? PhotoCell }) {
          if let index = collection.indexPath(for: item)?.item,
            let tile = stage.tile(at: index) as? MacZoomMediaTile,
            let image = tile.displayedImage { item.retainDisplayedImage(image) }
        }
      }
      // The native cells show first; the stage leaves only once that commit
      // has landed, so no stale cell contents are ever visible.
      let stage = zoomStage
      collection.alphaValue = 1
      // Never flush or lay out here: completion can run inside a SwiftUI update
      // pass, and forcing a display cycle re-enters it.
      DispatchQueue.main.async { [weak self, weak stage] in
        guard let self else { return }
        if let stage, self.zoomStage === stage { self.removeZoomStage() }
        // The document settles its height after this pass; draw the mosaic for
        // the final scroll position rather than the one at handoff.
        self.updateDense()
      }
      stopLayoutAnimation(); scrolled()
      scheduleBenchmark()
    }
    @objc func magnify(_ recognizer: NSMagnificationGestureRecognizer) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        let scroll = collection.enclosingScrollView else { return }
      switch recognizer.state {
      case .began:
        let interrupted = zoomStage != nil && settle != nil
        let location = recognizer.location(in: collection)
        let startColumns: Int
        if interrupted, let stage = zoomStage {
          // Take over the running settle in place: re-anchor on the new pointer
          // without moving any pixel, from the density the release had chosen.
          settleLink?.invalidate(); settleLink = nil; settle = nil; animationTarget = nil
          startColumns = settleColumns
          gestureLeading[settleColumns] = settleLeading
          stage.reanchor(to: CGPoint(x: location.x,y: location.y-scroll.contentView.bounds.minY))
          anchor = stage.anchor; anchorFraction = stage.fraction.y; anchorFractionX = stage.fraction.x
          anchorY = stage.focus.y
        } else {
          stopLayoutAnimation(); removeZoomStage()
          captureAnchor(location)
          startColumns = layout.columns
          beginStage()
        }
        keepsTop = false
        magnifying = true; restoring = true
        guard let stage = zoomStage else { magnifying = false; restoring = false; return }
        samples = []
        pinch = GridZoom.Pinch(startDistance: 1,startPitch: stage.pitch,deadZone: 0)
        direction = GridZoom.Direction(startIndex: stopIndex(startColumns),startPitch: stage.pitch)
        let natural = naturalPitch(stage.shown)
        let shownLeading = gestureLeading[stage.shown] ?? leading
        let content = anchorContentPoint(columns: stage.shown,leading: shownLeading)
        boundary = GridZoom.Boundary(startFocusY: stage.focus.y,contentHeight: contentHeight(stage.shown,leading: shownLeading),
          focusInContent: content.y,pitch: natural)
      case .changed:
        guard let stage = zoomStage, var pinch, var direction, let boundary else { return }
        let raw = pinch.pitch(distance: 1+recognizer.magnification)
        let pitch = stops.rubber(raw)
        let now = CACurrentMediaTime()
        samples.append((now,pitch)); samples.removeAll { now-$0.0 > 0.08 }
        stage.pitch = pitch
        let next = direction.update(pitch: pitch,shown: stopIndex(stage.shown),stops: stops)
        self.pinch = pinch; self.direction = direction
        let columns = columnStops[next]
        if columns != stage.shown {
          stage.ensureFace(columns,opacity: 0,leading: phase(for: columns))
          stage.show(columns,animated: !reducedMotion)
        }
        stage.advanceBlend(to: now)
        stage.focus.y = boundary.focusY(pitch: pitch,viewportBottom: viewportHeight(),viewportTop: 0)
        if !reducedMotion { stage.render() }
      case .ended, .cancelled, .failed:
        magnifying = false
        guard let stage = zoomStage, let pinch, let direction else {
          restoring = false; return
        }
        let cancelled = recognizer.state != .ended
        let index = GridZoom.releaseIndex(shown: stopIndex(stage.shown),start: direction.startIndex,
          recognized: pinch.recognized,intent: 0,cancelled: cancelled,count: columnStops.count)
        let columns = columnStops[index]
        let size = itemSize(forColumns: columns)
        if !cancelled { parent.resize(columns) }
        self.pinch = nil; self.direction = nil; self.boundary = nil
        finishStage(columns: columns,size: size,cancelled: cancelled)
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
      if let asset = asset(at: indexPath.item) {
        item.setSelectionVisible(parent.selecting)
        item.configure(
          asset, pipeline: parent.library.thumbnails,
          pixels: cellSide * (collectionView.window?.backingScaleFactor ?? 2),
          originalAspect: parent.navigation.originalAspect,
          identifier: identifier(at: indexPath.item))
        visibleIdentifiers[indexPath] = asset.localIdentifier
      }
      return item
    }
    func collectionView(
      _ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
      forRepresentedObjectAt indexPath: IndexPath
    ) {
      if let cell = item as? PhotoCell, let asset = asset(at: indexPath.item) {
        cell.setSelectionVisible(parent.selecting)
        cell.configure(
          asset, pipeline: parent.library.thumbnails,
          pixels: cellSide * (collectionView.window?.backingScaleFactor ?? 2),
          originalAspect: parent.navigation.originalAspect,
          identifier: identifier(at: indexPath.item))
        visibleIdentifiers[indexPath] = asset.localIdentifier
      }
      scrolled()
    }
    func collectionView(
      _ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
      forRepresentedObjectAt indexPath: IndexPath
    ) {
      // An old end-display callback may arrive after AppKit reuses the item.
      if !collectionView.visibleItems().contains(where: { $0 === item }) { (item as? PhotoCell)?.cancel() }
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
      let ids = paths.compactMap { identifier(at: $0.item) }
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
      guard let collection, let id = identifier(at: path.item) else { return }
      parent.library.selection.insert(id)
      applyingSelection = true
      collection.isSelectable = true
      collection.selectionIndexPaths = selectedPaths()
      appliedSelection = parent.library.selection
      applyingSelection = false
      parent.enterSelection()
    }
    func toggleSelection(at path: IndexPath) {
      guard parent.selecting, let collection, let id = identifier(at: path.item) else { return }
      if parent.library.selection.contains(id) { parent.library.selection.remove(id) }
      else { parent.library.selection.insert(id) }
      applyingSelection = true
      collection.selectionIndexPaths = selectedPaths()
      appliedSelection = parent.library.selection
      applyingSelection = false
    }
    func refreshVisibleImages() {
      guard let collection else { return }
      for path in collection.indexPathsForVisibleItems() {
        if let item = collection.item(at: path) as? PhotoCell,
          let asset = asset(at: path.item)
        {
          item.configure(
            asset, pipeline: parent.library.thumbnails,
            pixels: cellSide * (collection.window?.backingScaleFactor ?? 2),
            originalAspect: parent.navigation.originalAspect,
            identifier: identifier(at: path.item))
        }
      }
    }
    func scrolled() {
      updateFooter()
      updateDense()
      guard !restoring else { return }
      if let collection, let scroll = collection.enclosingScrollView, zoomStage == nil {
        let clip = scroll.contentView, height = settledContentHeight
        let atBottom = clip.bounds.maxY >= height - 2
        let types: Set<NSEvent.EventType> = [.scrollWheel, .leftMouseDragged, .keyDown, .magnify, .swipe, .leftMouseDown, .smartMagnify]
        let userDriven = NSApp.currentEvent.map { types.contains($0.type) } ?? false
        if userDriven { pinnedToNewest = atBottom }
      }
      if generation == parent.library.generation { rememberScroll() }
      refresh.schedule { [weak self] in
        guard let self, !Task.isCancelled, let collection = self.collection else { return }
        let parent = self.parent
        guard parent.active, parent.navigation.level == .all else { return }
        self.rememberScroll()
        let generation = parent.library.generation
        let receiverID = parent.receiverID
        let revision = parent.queueRevision
        let preparation = parent.preparationRevision
        let paths = collection.indexPathsForVisibleItems().sorted()
        guard let span = self.visibleRange() else { return }
        let first = span.first, last = span.last
        let identities = Dictionary(uniqueKeysWithValues: paths.compactMap { path in
          self.asset(at: path.item).map { (path, $0.localIdentifier) }
        })
        if first <= 48 { parent.library.loadMore() }
        // An overview shows thousands of photos: faulting each PhotoKit asset to
        // preheat it or to look up its backup state (no badges are drawn there)
        // was most of the main thread while it scrolled. Its tiles come from
        // the decoded tables; only the date range below is read.
        let dense = self.layoutDense
        if !dense {
          let range = max(0, first - 24)..<min(self.count, last + 49)
          parent.library.thumbnails.preheat(
            range.compactMap { self.asset(at: $0) }, pixels: cellSide * (collection.window?.backingScaleFactor ?? 2))
        }
        let visible = dense ? [] : (first...last).prefix(400).compactMap { self.asset(at: $0) }
        // The range spans the first and last photo on screen; an overview shows
        // thousands, so the ends are read directly rather than from a prefix.
        if let date = self.date(at: first) {
          let last = self.date(at: last) ?? date
          let title = Calendar.current.isDate(date,equalTo: last,toGranularity: .month)
            ? date.formatted(.dateTime.year().month(.wide))
            : date.formatted(.dateTime.year().month(.wide)) + " – " + last.formatted(.dateTime.year().month(.wide))
          if parent.navigation.visibleDate != title { parent.navigation.visibleDate = title }
        }
        guard !dense else { return }
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
            let burst = self.asset(at: path.item)?.burstIdentifier != nil
            item.setGroup(count: burst ? group?.count : nil, state: group?.state(states))
          }
        }
      }
    }
    func rememberScroll() {
      guard !restoring, parent.library.authorized, filter == parent.library.filter,
        scrollResetGeneration == parent.library.scrollResetGeneration, let collection,
        let scroll = collection.enclosingScrollView,
        let first = visibleRange()?.first, let id = identifier(at: first),
        let frame = collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: first, section: 0))?.frame,
        frame.intersects(collection.visibleRect)
      else { return }
      parent.library.scrollOffset = scroll.contentView.bounds.origin
      parent.library.scrollAnchorID = id
      parent.library.scrollAnchorInset = scroll.contentView.bounds.origin.y - frame.minY
    }
  }
}

@MainActor private final class LibraryCollectionView: NSCollectionView {
  /// In original aspect the visible gap around a photo belongs to its cell, so
  /// AppKit treats a press there as a press on the photo. Such a point is
  /// background: a drag from it draws a marquee, as between square cells.
  private func inGap(_ point: NSPoint) -> Bool {
    guard let path = super.indexPathForItem(at: point), let cell = item(at: path) as? PhotoCell,
      cell.view.superview != nil else { return false }
    return !cell.photoRect.contains(cell.view.convert(point, from: self))
  }
  override func indexPathForItem(at point: NSPoint) -> IndexPath? {
    inGap(point) ? nil : super.indexPathForItem(at: point)
  }
  private func marquee(from start: NSPoint, with event: NSEvent) {
    let extend = !event.modifierFlags.intersection([.command, .shift]).isEmpty
    let base = extend ? selectionIndexPaths : []
    if !extend, !selectionIndexPaths.isEmpty {
      let old = selectionIndexPaths
      deselectItems(at: old); delegate?.collectionView?(self, didDeselectItemsAt: old)
    }
    let band = MacMarqueeView(frame: .zero)
    addSubview(band)
    defer { band.removeFromSuperview() }
    var current = base
    while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseUp { break }
      autoscroll(with: next)
      let point = convert(next.locationInWindow, from: nil)
      let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
        width: abs(point.x - start.x), height: abs(point.y - start.y))
      band.frame = rect
      var hits = Set<IndexPath>()
      for attributes in collectionViewLayout?.layoutAttributesForElements(in: rect) ?? [] {
        guard attributes.representedElementCategory == .item, let path = attributes.indexPath else { continue }
        let photo = (item(at: path) as? PhotoCell).map { $0.photoRect.offsetBy(dx: attributes.frame.minX, dy: attributes.frame.minY) }
          ?? attributes.frame
        if photo.intersects(rect) { hits.insert(path) }
      }
      let target = base.union(hits)
      let added = target.subtracting(current), removed = current.subtracting(target)
      if !removed.isEmpty { deselectItems(at: removed); delegate?.collectionView?(self, didDeselectItemsAt: removed) }
      if !added.isEmpty { selectItems(at: added, scrollPosition: []); delegate?.collectionView?(self, didSelectItemsAt: added) }
      current = target
    }
  }
  var denseHit: ((CGPoint) -> Int?)?
  var drill: ((Int) -> Void)?
  var toggleSelection: ((IndexPath) -> Void)?
  var preview: ((IndexPath) -> Void)?
  var enterSelection: ((IndexPath) -> Void)?

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    // Overview mosaics have no cells: a click drills down one stop around the
    // photo, as on iPhone, instead of selecting.
    if let index = denseHit?(point) { if event.clickCount == 1 { drill?(index) }; return }
    if event.clickCount == 2, let path = indexPathForItem(at: point) { preview?(path); return }
    if event.clickCount == 1, inGap(point) { marquee(from: point, with: event); return }
    // AppKit owns plain, Command, Shift and rubber-band selection, including
    // keyboard extension. A plain click must not open an iPhone-style modal.
    super.mouseDown(with: event)
  }
  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " || event.keyCode == 36 {
      if let path = selectionIndexPaths.sorted().first { preview?(path) }
      return
    }
    if event.keyCode == 53 { deselectAll(nil); return }
    if event.keyCode == 123 || event.keyCode == 124, arrowStep(event.keyCode == 124 ? 1 : -1, extend: event.modifierFlags.contains(.shift)) { return }
    super.keyDown(with: event)
  }
  private var keyAnchor: IndexPath?, keyCursor: IndexPath?
  /// Left and Right move through the library in reading order, continuing onto
  /// the next or previous row, as Photos does. Shift extends from the anchor.
  private func arrowStep(_ step: Int, extend: Bool) -> Bool {
    let count = numberOfSections > 0 ? numberOfItems(inSection: 0) : 0
    guard count > 0 else { return false }
    let selected = selectionIndexPaths
    let cursor = keyCursor.flatMap { selected.contains($0) ? $0 : nil } ?? (step > 0 ? selected.max() : selected.min())
    guard let cursor else { return false }
    let next = IndexPath(item: min(count - 1, max(0, cursor.item + step)), section: 0)
    let anchor = extend ? (keyAnchor.flatMap { selected.contains($0) ? $0 : nil } ?? cursor) : next
    let range = min(anchor.item, next.item)...max(anchor.item, next.item)
    let target = Set(range.map { IndexPath(item: $0, section: 0) })
    let removed = selected.subtracting(target), added = target.subtracting(selected)
    if !removed.isEmpty { deselectItems(at: removed); delegate?.collectionView?(self, didDeselectItemsAt: removed) }
    if !added.isEmpty { selectItems(at: added, scrollPosition: []); delegate?.collectionView?(self, didSelectItemsAt: added) }
    keyAnchor = anchor; keyCursor = next
    scrollToItems(at: [next], scrollPosition: .nearestHorizontalEdge)
    return true
  }
}

private final class MacMarqueeView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
    layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
    layer?.borderWidth = 1
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Grid badges are layers drawn from cached bitmaps. Badges were image views
/// holding SF Symbols, then labels: every cell that scrolled in re-rasterized
/// its symbols and re-typeset its text on the main thread, and each badge view
/// added layer-tree and tracking-area work. A cell is now one view.
@MainActor final class MacBadgeLayer: CALayer {
  var symbol: String? { didSet { if symbol != oldValue { refresh() } } }
  var tint: NSColor = .white { didSet { if tint != oldValue { refresh() } } }
  var scale: CGFloat = 2 { didSet { if scale != oldValue { refresh() } } }
  private let glyph = CALayer()
  private static var cache: [String: CGImage] = [:]
  static let still: [String: CAAction] = [
    "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "hidden": NSNull(),
  ]
  override init() {
    super.init()
    actions = Self.still
    glyph.contentsGravity = .resizeAspect
    glyph.actions = Self.still
    addSublayer(glyph)
  }
  override init(layer: Any) { super.init(layer: layer) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layoutSublayers() {
    super.layoutSublayers()
    glyph.frame = bounds.insetBy(dx: bounds.width * 0.2, dy: bounds.height * 0.2)
  }
  private func refresh() {
    glyph.contentsScale = scale
    glyph.contents = symbol.flatMap { Self.image($0, tint: tint, scale: scale) }
  }
  private static func image(_ name: String, tint: NSColor, scale: CGFloat) -> CGImage? {
    let key = "\(name)|\(tint.description)|\(scale)"
    if let cached = cache[key] { return cached }
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold).applying(.init(paletteColors: [tint]))) else { return nil }
    var rect = CGRect(origin: .zero, size: symbol.size)
    let image = symbol.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
    cache[key] = image
    return image
  }
}

/// A text badge (video length, burst count) as a layer from a cached bitmap.
@MainActor final class MacTextBadgeLayer: CALayer {
  var text = "" { didSet { if text != oldValue { refresh() } } }
  var scale: CGFloat = 2 { didSet { if scale != oldValue { refresh() } } }
  /// Width of the text alone, in points.
  private(set) var textWidth: CGFloat = 0
  private var weight: NSFont.Weight = .regular
  private let glyph = CALayer()
  private static var cache: [String: (image: CGImage, size: CGSize)] = [:]
  init(weight: NSFont.Weight, fill: NSColor, radius: CGFloat) {
    self.weight = weight
    super.init()
    actions = MacBadgeLayer.still
    backgroundColor = fill.cgColor
    cornerRadius = radius
    glyph.contentsGravity = .center
    glyph.actions = MacBadgeLayer.still
    addSublayer(glyph)
  }
  override init(layer: Any) { super.init(layer: layer) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layoutSublayers() {
    super.layoutSublayers()
    glyph.frame = bounds
  }
  private func refresh() {
    let rendered = text.isEmpty ? nil : Self.image(text, weight: weight, scale: scale)
    glyph.contentsScale = scale
    glyph.contents = rendered?.image
    textWidth = rendered?.size.width ?? 0
  }
  private static func image(_ text: String, weight: NSFont.Weight, scale: CGFloat) -> (image: CGImage, size: CGSize)? {
    let key = "\(text)|\(weight.rawValue)|\(scale)"
    if let cached = cache[key] { return cached }
    let string = NSAttributedString(string: text, attributes: [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: weight), .foregroundColor: NSColor.white,
    ])
    let measured = string.size()
    let size = CGSize(width: ceil(measured.width), height: ceil(measured.height))
    let image = NSImage(size: size, flipped: false) { _ in string.draw(at: .zero); return true }
    var rect = CGRect(origin: .zero, size: size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
    else { return nil }
    if cache.count > 2000 { cache.removeAll() }
    cache[key] = (cg, size)
    return (cg, size)
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
  private(set) var displayedImage: NSImage?
  private let media = MacBadgeLayer()
  private let status = MacBadgeLayer()
  private let cloud = MacBadgeLayer()
  private let selectionMark = MacBadgeLayer()
  private var selectionVisible = true
  private var statusState: String?
  private var groupCount: Int?
  private let burstCount = MacTextBadgeLayer(weight: .medium, fill: .black.withAlphaComponent(0.45), radius: 4)
  private let duration = MacTextBadgeLayer(weight: .semibold, fill: .black.withAlphaComponent(0.55), radius: 5)
  /// Hover help for the visible status and burst badges, as tooltip rectangles
  /// on the cell's one view.
  private var statusTip: String?
  private var burstTip: String?
  private var groupDescription = ""
  override func loadView() {
    view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor(DuckColors.subtle).cgColor
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = 0
    photoLayer.contentsGravity = .resizeAspectFill
    photoLayer.masksToBounds = true
    // Core Animation cross-fades `contents` by default: every image swap or
    // reused cell then ghosted over the previous photo. Tiles change instantly.
    photoLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(),
      "frame": NSNull(), "opacity": NSNull(), "hidden": NSNull(), "contentsRect": NSNull()]
    view.layer?.addSublayer(photoLayer)
    view.layer?.addSublayer(selectionOutline)
    selectionOutline.borderColor = NSColor.controlAccentColor.cgColor
    for badge in [media, status, cloud, selectionMark] {
      badge.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
      badge.cornerRadius = 12
      view.layer?.addSublayer(badge)
    }
    if DesignPreview.proposedDesign {
      // design/library.md § Tile marks: white glyphs with a soft shadow, no circles.
      for badge in [media, status, cloud] {
        badge.backgroundColor = nil
        badge.shadowColor = NSColor.black.cgColor  // design-exception: legibility shadow on photos
        badge.shadowOpacity = 0.45
        badge.shadowRadius = 2
        badge.shadowOffset = CGSize(width: 0, height: -0.5)
      }
    }
    burstCount.isHidden = true
    view.layer?.addSublayer(burstCount)
    duration.isHidden = true
    view.layer?.addSublayer(duration)
    cloud.isHidden = true
    media.isHidden = true
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.image)
  }
  override func viewDidLayout() {
    super.viewDidLayout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    photoLayer.frame = photoFrame()
    photoLayer.cornerRadius = photoRadius(); selectionOutline.cornerRadius = photoRadius()
    CATransaction.commit()
    // Badges sit on the photo, not the cell, so original aspect keeps them on it.
    let f = photoFrame()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    let scale = view.window?.backingScaleFactor ?? 2
    for badge in [media, status, cloud, selectionMark] { badge.scale = scale }
    burstCount.scale = scale; duration.scale = scale
    media.frame = NSRect(x: f.minX + 7, y: f.minY + 7, width: 18, height: 18)
    burstCount.frame = NSRect(x: f.minX + 28, y: f.minY + 7, width: 36, height: 18)
    let durationWidth = min(f.width - 16, max(42, duration.textWidth + 12))
    duration.frame = NSRect(x: f.maxX - durationWidth - 7, y: f.minY + 7, width: durationWidth, height: 18)
    cloud.frame = NSRect(x: f.minX + 8, y: f.minY + 8, width: 24, height: 24)
    status.frame = NSRect(x: f.maxX - 32, y: f.minY + 8, width: 24, height: 24)
    selectionMark.frame = NSRect(x: f.maxX - 30, y: f.minY + 6, width: 24, height: 24)
    selectionOutline.frame = photoFrame()
    CATransaction.commit()
    updateTips()
  }
  override var isSelected: Bool {
    didSet {
      view.layer?.borderWidth = 0
      view.layer?.borderColor = NSColor.controlAccentColor.cgColor
      updateSelectionMark()
    }
  }
  func configure(_ asset: PHAsset, pipeline: ThumbnailPipeline, pixels: CGFloat, originalAspect: Bool = false, identifier: String? = nil) {
    presentationID = identifier ?? asset.localIdentifier
    let key =
      "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))|\(pipeline.size(pixels).width)|\(PreviewNetworkPolicy.shared.allowed)|\(pipeline.epoch)|\(originalAspect)"
    guard imageKey != key else { return }
    let sameAsset = assetID == asset.localIdentifier
    cancel()
    self.pipeline = pipeline
    assetID = asset.localIdentifier
    imageKey = key
    let current = token
    if !sameAsset {
      displayedImage = nil
      // A decoded table thumbnail fills the cell at once while its own size
      // loads; without it a reused cell stays blank until PhotoKit delivers.
      photoLayer.contents = MacThumbnailTables.placeholder(asset)
    }
    // The layer always fills its own frame; original aspect shrinks the frame to
    // the photo's rectangle (animated), so the selection outline hugs the photo.
    assetAspect = asset.pixelHeight > 0 ? CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight) : 1
    if fitted != originalAspect {
      fitted = originalAspect
      applyPhotoFrame(animated: sameAsset)
    } else if !sameAsset { applyPhotoFrame(animated: false) }
    cloud.isHidden = true
    let symbol =
      asset.burstIdentifier != nil ? "square.stack" : asset.mediaSubtypes.contains(.photoLive)
      ? "livephoto" : asset.mediaType == .video ? "video.fill" : nil
    media.symbol = symbol
    media.isHidden = symbol == nil || asset.mediaType == .video
    duration.text = asset.mediaType == .video ? videoDurationLabel(asset.duration) : ""
    duration.isHidden = asset.mediaType != .video
    view.needsLayout = true
    view.setAccessibilityLabel(
      (asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "") + " "
        + NSLocalizedString(
          symbol == "square.stack" ? "library_filter_burst" : symbol == "livephoto"
            ? "library_filter_motion"
            : symbol == nil ? "library_filter_photo" : "library_filter_video", comment: ""))
    setGroup(count: nil, state: nil)
    request = pipeline.request(asset, pixels: pixels, contentMode: originalAspect ? .aspectFit : .aspectFill) { [weak self] image, inCloud in
      guard let self, self.token == current else { return }
      if let image {
        self.retainDisplayedImage(image)
        if !inCloud, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
          MacThumbnailTables.remember(asset, image: cg)
        }
      }
      self.cloud.symbol = "icloud"
      self.cloud.isHidden = image != nil || !inCloud
    }
  }
  private var fitted = false
  private var assetAspect: CGFloat = 1
  /// The rectangle the photo occupies in the cell: the whole cell, or the
  /// aspect-fit rectangle in original-aspect mode.
  private func photoFrame() -> CGRect {
    var b = view.bounds
    guard fitted, assetAspect > 0, b.width > 0, b.height > 0 else { return b }
    // Photos shows original-aspect photos with real gaps: the photo is inset in
    // its square cell and its corners are rounded.
    b = b.insetBy(dx: b.width * 0.055, dy: b.height * 0.055)
    if assetAspect >= b.width / b.height {
      let h = b.width / assetAspect
      return CGRect(x: b.minX, y: b.minY + (b.height - h) / 2, width: b.width, height: h)
    }
    let w = b.height * assetAspect
    return CGRect(x: b.minX + (b.width - w) / 2, y: b.minY, width: w, height: b.height)
  }
  var photoRect: CGRect { photoFrame() }
  var photoCornerRadius: CGFloat { photoRadius() }
  private func photoRadius() -> CGFloat { fitted ? max(2, view.bounds.width * 0.035) : 0 }
  private func applyPhotoFrame(animated: Bool) {
    let target = photoFrame()
    view.layer?.backgroundColor = fitted ? NSColor.clear.cgColor : NSColor(DuckColors.subtle).cgColor
    for layer in [photoLayer, selectionOutline] {
      let fromRadius = layer.presentation()?.cornerRadius ?? layer.cornerRadius
      layer.cornerRadius = photoRadius()
      if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        let r = CABasicAnimation(keyPath: "cornerRadius")
        r.fromValue = fromRadius; r.toValue = layer.cornerRadius; r.duration = 0.3
        layer.add(r, forKey: "aspect.radius")
      }
    }
    let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    view.needsLayout = true
    for layer in [photoLayer, selectionOutline] {
      let from = layer.presentation()
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.frame = target
      CATransaction.commit()
      guard animate, let from else { continue }
      for (key, a, b) in [("bounds", NSValue(rect: from.bounds), NSValue(rect: layer.bounds)),
        ("position", NSValue(point: from.position), NSValue(point: layer.position))] {
        let move = CABasicAnimation(keyPath: key)
        move.fromValue = a; move.toValue = b
        move.duration = 0.3; move.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        layer.add(move, forKey: "aspect." + key)
      }
    }
  }
  func retainDisplayedImage(_ image: NSImage) {
    if let current = displayedImage {
      let edge: (NSImage) -> Int = { $0.representations.map { max($0.pixelsWide,$0.pixelsHigh) }.max() ?? 0 }
      let oldAspect = current.size.width/max(1,current.size.height)
      let newAspect = image.size.width/max(1,image.size.height)
      if abs(log(oldAspect/newAspect)) < 0.02,edge(current) > edge(image) { return }
    }
    displayedImage = image
    photoLayer.contents = image.cgImage(forProposedRect: nil,context: nil,hints: nil)
  }
  func copyDecorations(from other: PhotoCell) { setGroup(count: other.groupCount,state: other.statusState) }
  func setGroup(count: Int?, state: String?) {
    groupCount = count
    if count != nil {
      media.symbol = "square.stack"
      media.isHidden = false
    }
    burstCount.text = count.map(String.init) ?? ""
    burstCount.isHidden = count == nil
    groupDescription = count.map { String(format: NSLocalizedString("library_burst_count", comment: ""), $0) + ". " } ?? ""
    burstTip = count == nil ? nil : NSLocalizedString("library_burst_selection", comment: "")
    setState(state)
  }
  func setState(_ state: String?) {
    statusState = state
    status.symbol = state == nil ? nil : taskSymbol(state)
    status.tint = state == "failed" ? .systemOrange : .white
    if DesignPreview.proposedDesign {
      // Proposed marks (design/library.md): none once the Pixel has the photo,
      // an arrow while it is on its way, an exclamation when it needs the user.
      switch state {
      // design-exception: tile marks are white glyphs with a shadow on photos (visual-language.md)
      case "failed": status.symbol = "exclamationmark.triangle.fill"; status.tint = .white  // design-exception: tile mark on a photo
      case "preparing", "running", "queued", "waiting", "paused", "scheduled", "partial":
        status.symbol = "arrow.up"; status.tint = .white  // design-exception: tile mark on a photo
      default: status.symbol = nil
      }
    }
    let detail = groupDescription + NSLocalizedString(
      state == "received" ? "state_received_detail" : state.map { "state_" + $0 } ?? "state_not_queued", comment: "")
    view.setAccessibilityValue(detail)
    status.isHidden = selectionVisible || state == nil || status.symbol == nil
    statusTip = detail
    updateTips()
  }
  /// A tooltip registers a tracking area that every scroll step recomputes;
  /// only a visible badge carries one.
  private var tipsShown = false
  private func updateTips() {
    let tips = [(status, statusTip), (burstCount as CALayer, burstTip)].compactMap { layer, tip in
      layer.isHidden ? nil : tip.map { (layer.frame, $0) }
    }
    guard tipsShown || !tips.isEmpty else { return }
    view.removeAllToolTips()
    for (rect, tip) in tips { view.addToolTip(rect, owner: tip as NSString, userData: nil) }
    tipsShown = !tips.isEmpty
  }
  func setSelectionVisible(_ value: Bool) {
    selectionVisible = value
    view.layer?.borderWidth = 0
    status.isHidden = value || statusState == nil || status.symbol == nil
    updateTips()
    updateSelectionMark()
  }
  /// Selection is an accent outline around the photo, as in Photos: no check
  /// mark and no dimming. Rebuilding layer state on every SwiftUI update pass
  /// was a measurable hot spot, so only changes are applied.
  private func updateSelectionMark() {
    selectionMark.isHidden = true
    let outlined = selectionVisible && isSelected
    guard markedSelected != outlined else { return }
    markedSelected = outlined
    photoLayer.opacity = 1
    selectionOutline.isHidden = !outlined
    view.needsLayout = true
  }
  private var markedSelected: Bool?
  /// Drawn above the photo, inset by half its width so the photo is never cropped.
  private lazy var selectionOutline: CALayer = {
    let layer = CALayer()
    layer.borderWidth = 3
    layer.cornerRadius = 0
    layer.isHidden = true
    layer.actions = ["borderColor": NSNull(), "hidden": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
    return layer
  }()
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
    displayedImage = nil
    presentationID = nil
  }
}

@MainActor private final class LibraryScrollView: NSScrollView {
  var restoreScroll: ((LibraryScrollView) -> Void)?
  /// A level layer that has faded out stays mounted (so its covers are ready)
  /// but must not take clicks meant for the level beneath it.
  override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.05 ? nil : super.hitTest(point) }
  override func layout() {
    super.layout()
    if let collection = documentView as? NSCollectionView,
      collection.frame.width != contentSize.width
    {
      let oldOffset = contentView.bounds.origin
      let path = restoreScroll == nil ? collection.indexPathsForVisibleItems().sorted().first : nil
      let oldFrame = path.flatMap { collection.collectionViewLayout?.layoutAttributesForItem(at: $0)?.frame }
      let fraction = oldFrame.map { (oldOffset.y-$0.minY)/max(1,$0.height) } ?? 0
      collection.setFrameSize(NSSize(width: contentSize.width, height: collection.frame.height))
      collection.collectionViewLayout?.invalidateLayout()
      collection.layoutSubtreeIfNeeded()
      if let path, let frame = collection.collectionViewLayout?.layoutAttributesForItem(at: path)?.frame {
        let maximum = max(0,collection.frame.height-contentSize.height)
        contentView.scroll(to: CGPoint(x: 0,y: min(maximum,max(0,frame.minY+fraction*frame.height))))
        reflectScrolledClipView(contentView)
      }
    }
    // Restoring at a transient few-point width (a sheet's first pass) measured
    // the content at that width and left the viewport untiled.
    if contentSize.width > 120, contentSize.height > 0, let restore = restoreScroll {
      restoreScroll = nil
      restore(self)
    }
  }
}

/// Native virtualized calendar covers over the same filtered PhotoKit fetch.
struct MacCalendarGrid: NSViewRepresentable {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var navigation: MacLibraryNavigation
  /// The level this instance presents. Years and Months stay mounted as
  /// separate layers so a level change can transition between live views.
  var kind: MacLibraryLevel
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let flow = NSCollectionViewFlowLayout()
    flow.minimumInteritemSpacing = 12; flow.minimumLineSpacing = 20
    flow.sectionInset = NSEdgeInsets(top: 16, left: 28, bottom: 28, right: 28)
    let collection = MacCalendarCollection()
    collection.collectionViewLayout = flow; collection.backgroundColors = [.clear]
    collection.register(MacCalendarCell.self, forItemWithIdentifier: .init("period"))
    collection.dataSource = context.coordinator; collection.delegate = context.coordinator
    collection.isSelectable = true; collection.allowsMultipleSelection = false
    collection.select = { [weak c = context.coordinator] path, point in c?.select(path.item, at: point) }
    collection.open = { [weak c = context.coordinator] path, point in c?.open(path.item, at: point) }
    collection.openSelected = { [weak c = context.coordinator] in c?.openSelected() }
    let scroll = LibraryScrollView()
    scroll.hasVerticalScroller = true; scroll.drawsBackground = false
    scroll.alphaValue = navigation.level == kind ? 1 : 0
    scroll.documentView = collection; collection.autoresizingMask = [.width]
    // The source is the cover actually showing the focus photo; a date lookup
    // can name a different card than the one on screen.
    navigation.coverFlight[kind] = { [weak c = context.coordinator] token in c?.flightLanding(token, token) }
    navigation.coverLanding[kind] = { [weak c = context.coordinator] token, asset in c?.flightLanding(token, asset) }
    navigation.focusCandidate[kind] = { [weak c = context.coordinator] in c?.focusToken() }
    navigation.presentFocus[kind] = { [weak c = context.coordinator] asset, image in c?.presentFocus(asset, image) }
    context.coordinator.collection = collection
    scroll.contentView.postsBoundsChangedNotifications = true
    context.coordinator.observer = NotificationCenter.default.addObserver(
      forName: NSView.boundsDidChangeNotification,object: scroll.contentView,queue: .main
    ) { [weak c = context.coordinator] _ in Task { @MainActor in c?.scrolled() } }
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let c = context.coordinator; c.parent = self
    // Oldest first, resting at the newest edge at the bottom.
    let periods = Array((kind == .years ? navigation.years : navigation.months).reversed())
    let key = "\(kind.rawValue)|\(library.generation)|\(periods.map(\.id).joined(separator: ","))"
    let active = navigation.level == kind
    scroll.setAccessibilityHidden(!active)
    MacLevelFade.apply(scroll,layer: kind,current: navigation.level)
    c.startCoverLife()
    guard let collection = c.collection else { return }
    if c.key != key {
      c.key = key; c.periods = periods; c.positioning = true
      collection.reloadData()
      collection.collectionViewLayout?.invalidateLayout()
      collection.setFrameSize(CGSize(width: scroll.contentSize.width,height: collection.frame.height))
      collection.layoutSubtreeIfNeeded()
      if active { place(scroll,c) }
      c.positioning = false
    } else if active, !c.wasActive {
      c.positioning = true
      collection.layoutSubtreeIfNeeded()
      place(scroll,c)
      c.positioning = false
    }
    c.wasActive = active
  }
  /// Centres the period containing the shared focus, as Photos does on a level
  /// change, or rests at the newest edge (the bottom) when there is none. The
  /// flow layout can resize its document after this pass and AppKit then resets
  /// the offset, so the placement is re-applied until the person scrolls.
  private func place(_ scroll: NSScrollView,_ c: Coordinator) {
    guard let collection = c.collection else { return }
    let expectedKey = c.key
    c.userScrolled = false
    var target: Int?
    if let token = navigation.focusToken, let raw = Self.rawPosition(token, in: library.fetch),
      let fetch = library.fetch {
      let date = fetch.object(at: raw).creationDate
      let granularity: Calendar.Component = kind == .years ? .year : .month
      target = c.periods.firstIndex { period in
        guard let start = period.date, let date else { return period.date == nil && date == nil }
        return Calendar.current.isDate(date, equalTo: start, toGranularity: granularity)
      }
    }
    func apply() {
      collection.layoutSubtreeIfNeeded()
      let content = max(collection.frame.height, collection.collectionViewLayout?.collectionViewContentSize.height ?? 0)
      let maximum = max(0, content - scroll.contentSize.height)
      var y = maximum
      if let target, let frame = collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: target, section: 0))?.frame {
        y = min(maximum, max(0, frame.midY - scroll.contentSize.height / 2))
      }
      guard abs(scroll.contentView.bounds.minY - y) > 0.5 else { return }
      scroll.contentView.scroll(to: CGPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
    }
    apply()
    for delay in [0.05, 0.2, 0.5] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak c] in
        guard let c, c.key == expectedKey, !c.userScrolled, navigation.level == kind else { return }
        c.positioning = true; apply(); c.positioning = false
      }
    }
  }
  fileprivate static func rawPosition(_ token: String, in fetch: PHFetchResult<PHAsset>?) -> Int? {
    guard let fetch else { return nil }
    let result: PHFetchResult<PHAsset>
    if token.hasPrefix("burst:") { result = PHAsset.fetchAssets(withBurstIdentifier: String(token.dropFirst(6)), options: photoLibraryFetchOptions()) }
    else { result = PHAsset.fetchAssets(withLocalIdentifiers: [token], options: photoLibraryFetchOptions()) }
    guard let asset = result.firstObject else { return nil }
    let index = fetch.index(of: asset)
    return index == NSNotFound ? nil : index
  }
  @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    var parent: MacCalendarGrid
    var key = ""
    var wasActive = false
    var userScrolled = false
    var periods: [LibraryCalendarPeriod] = []
    var observer: NSObjectProtocol?
    var positioning = false
    /// Pins each visible month heading under the top edge of the visible area.
    func updatePins() {
      guard parent.kind == .months, let collection, let scroll = collection.enclosingScrollView else { return }
      let top = collection.visibleRect.minY + scroll.contentInsets.top
      for case let cell as MacCalendarCell in collection.visibleItems() {
        let frame = cell.view.frame
        cell.setPin(min(max(0, top - frame.minY + 6), max(0, frame.height - MacCalendarCover.headingHeight - 40)))
      }
    }
    func scrolled() {
      updatePins()
      let types: Set<NSEvent.EventType> = [.scrollWheel, .leftMouseDragged, .keyDown, .swipe, .leftMouseDown]
      if let type = NSApp.currentEvent?.type, types.contains(type) {
        userScrolled = true; lastUserScroll = Date()
        collection?.visibleItems().forEach { ($0 as? MacCalendarCell)?.stopVideo() }
      }
      guard !positioning, let collection, parent.navigation.level == parent.kind else { return }
      let center = CGPoint(x: collection.visibleRect.midX,y: collection.visibleRect.midY)
      let path = collection.indexPathsForVisibleItems().min { a,b in
        guard let left = collection.collectionViewLayout?.layoutAttributesForItem(at: a)?.frame,
          let right = collection.collectionViewLayout?.layoutAttributesForItem(at: b)?.frame else { return a < b }
        return hypot(left.midX-center.x,left.midY-center.y) < hypot(right.midX-center.x,right.midY-center.y)
      }
      guard let path, periods.indices.contains(path.item), let token = periods[path.item].tokens.first else { return }
      parent.navigation.focusToken = token
      if parent.navigation.visibleDate != periods[path.item].title { parent.navigation.visibleDate = periods[path.item].title }
    }
    weak var collection: NSCollectionView?
    private var opening: Task<Void, Never>?
    init(_ parent: MacCalendarGrid) { self.parent = parent }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { periods.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
      let item = collectionView.makeItem(withIdentifier: .init("period"), for: indexPath) as! MacCalendarCell
      let period = periods[indexPath.item]
      let photos = period.covers.compactMap { index -> PHAsset? in
        guard let fetch = parent.library.fetch, index < fetch.count else { return nil }
        return fetch.object(at: index)
      }
      if let selected = selectedCover, selected.item == indexPath.item { item.setSelectedCover(selected.cover) } else { item.setSelectedCover(nil) }
      item.configure(period: period, assets: photos, choices: parent.kind == .years ? yearChoices(period) : [], kind: parent.kind, pipeline: parent.library.thumbnails,
        mirrored: period.date.map { Calendar.current.component(.month, from: $0) % 2 == 0 } ?? false)
      return item
    }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
      sizeForItemAt indexPath: IndexPath) -> NSSize {
      let width = collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width
      let content = max(1, width - 56)
      if parent.kind == .years {
        // Portrait cards, about 4:5 as in Photos, three or more across.
        let columns = max(1, Int((content + 12) / (250 + 12)))
        let side = floor((content - CGFloat(columns - 1) * 12) / CGFloat(columns))
        return NSSize(width: max(1, side), height: max(1, round(side * 1.25)))
      }
      // A month is one full-width module whose composition follows how many day
      // covers were sampled (one to six), as on iPhone.
      let covers = periods.indices.contains(indexPath.item) ? periods[indexPath.item].covers.count : 1
      return NSSize(width: content, height: MacCalendarCover.monthHeight(width: content, count: covers))
    }
    /// The cover under the pointer is selected with an outline; opening is a
    /// separate, deliberate act (double click, Return or Space).
    var selectedCover: (item: Int, cover: Int)?
    private func coverCell(_ item: Int) -> MacCalendarCell? {
      collection?.item(at: IndexPath(item: item, section: 0)) as? MacCalendarCell
    }
    func select(_ item: Int, at point: CGPoint) {
      let cover = coverCell(item)?.coverIndex(at: point) ?? 0
      if let old = selectedCover { coverCell(old.item)?.setSelectedCover(nil) }
      selectedCover = (item, cover)
      coverCell(item)?.setSelectedCover(cover)
    }
    func openSelected() {
      if let selected = selectedCover { open(selected.item, cover: selected.cover) }
      else if let first = collection?.indexPathsForVisibleItems().sorted().first { open(first.item, cover: 0) }
    }
    func open(_ item: Int, at point: CGPoint) {
      open(item, cover: coverCell(item)?.coverIndex(at: point) ?? 0)
    }
    func open(_ item: Int, cover: Int) {
      guard periods.indices.contains(item) else { return }
      let period = periods[item]
      // A year opens at the cover it is showing; a day opens All at that day.
      let token: String
      if parent.kind == .years, let hero = coverCell(item)?.coverView(0)?.asset ?? coverCell(item)?.heroAsset {
        token = hero.burstIdentifier.map { "burst:" + $0 } ?? hero.localIdentifier
      } else if period.tokens.indices.contains(cover) { token = period.tokens[cover] }
      else if let first = period.tokens.first { token = first } else { return }
      opening?.cancel()
      let level = parent.kind
      guard parent.navigation.level == level else { return }
      parent.navigation.focusToken = token
      if level == .years { parent.navigation.level = .months; return }
      opening = Task { [weak self] in
        guard let self, let asset = await parent.library.preparePreviewWindow(containing: token), !Task.isCancelled,
          parent.navigation.level == level else { return }
        let token = asset.burstIdentifier.map { "burst:" + $0 } ?? asset.localIdentifier
        parent.navigation.focus(token); parent.navigation.level = .all
      }
    }
    /// The cover this level shows for the period containing a token. A year
    /// shows its rotating hero; a month shows the token's own cover when sampled.
    func flightSource(_ token: String) -> MacCoverFlightSource? {
      guard let fetch = parent.library.fetch, let raw = MacCalendarGrid.rawPosition(token, in: fetch) else { return nil }
      let date = fetch.object(at: raw).creationDate
      let granularity: Calendar.Component = parent.kind == .years ? .year : .month
      guard let item = periods.firstIndex(where: { period in
        guard let start = period.date, let date else { return false }
        return Calendar.current.isDate(date, equalTo: start, toGranularity: granularity)
      }), let cell = coverCell(item) else { return nil }
      let index = parent.kind == .years ? 0 : (periods[item].tokens.firstIndex(of: token) ?? 0)
      return visibleCover(cell, index)
    }
    /// Where the focus lands: the cover showing that asset, otherwise the cover
    /// of the period containing the focus token.
    func flightLanding(_ token: String, _ assetID: String) -> MacCoverFlightSource? {
      guard let collection else { return nil }
      for cell in collection.visibleItems().compactMap({ $0 as? MacCalendarCell }) {
        let count = parent.kind == .years ? 1 : cell.coverAssets.count
        if let index = (0..<count).first(where: { cell.coverView($0)?.asset?.localIdentifier == assetID }),
          let found = visibleCover(cell, index) { return found }
      }
      return flightSource(token)
    }
    /// A year card that can show the focus photo (one of its rotating month
    /// photos) switches to it, so the flight lands on the same picture.
    func presentFocus(_ assetID: String, _ image: NSImage?) {
      guard parent.kind == .years, let collection else { return }
      for cell in collection.visibleItems().compactMap({ $0 as? MacCalendarCell }) where cell.show(choice: assetID, image: image) { return }
    }
    /// The selected cover, otherwise the cover nearest the centre.
    func focusToken() -> String? {
      func token(_ cell: MacCalendarCell, _ index: Int) -> String? {
        let asset = cell.coverView(index)?.asset
          ?? (parent.kind == .years ? cell.heroAsset : (cell.coverAssets.indices.contains(index) ? cell.coverAssets[index] : nil))
        return asset.map { $0.burstIdentifier.map { "burst:" + $0 } ?? $0.localIdentifier }
      }
      if let selected = selectedCover, let cell = coverCell(selected.item), let found = token(cell, selected.cover) { return found }
      guard let collection else { return nil }
      if let focus = parent.navigation.focusToken, flightLanding(focus, focus)?.assetID == focus { return focus }
      let visible = collection.visibleRect, center = CGPoint(x: visible.midX, y: visible.midY)
      var best: (CGFloat, String)?
      for cell in collection.visibleItems().compactMap({ $0 as? MacCalendarCell }) {
        let count = parent.kind == .years ? 1 : cell.coverAssets.count
        for index in 0..<count {
          guard let view = cell.coverView(index), !view.isHidden, let found = token(cell, index) else { continue }
          let frame = view.convert(view.bounds, to: collection)
          let distance = hypot(frame.midX - center.x, frame.midY - center.y)
          if best.map({ distance < $0.0 }) ?? true { best = (distance, found) }
        }
      }
      return best?.1
    }
    private func visibleCover(_ cell: MacCalendarCell, _ index: Int) -> MacCoverFlightSource? {
      guard let scroll = collection?.enclosingScrollView, let view = cell.coverView(index), view.window != nil,
        let asset = view.asset else { return nil }
      guard view.convert(view.bounds, to: scroll).intersects(scroll.bounds), view.bounds.width > 1 else { return nil }
      return MacCoverFlightSource(rect: view.convert(view.bounds, to: nil), image: view.image, radius: 8,
        assetID: asset.localIdentifier, clip: MacCoverFlightSource.clip(of: scroll), window: view.window)
    }
    private var yearCache: [String: [PHAsset]] = [:]
    /// Real month representatives of a year, which its card rotates through.
    func yearChoices(_ period: LibraryCalendarPeriod) -> [PHAsset] {
      if let cached = yearCache[period.id] { return cached }
      guard let fetch = parent.library.fetch, let start = period.date else { return [] }
      let calendar = Calendar.current
      let assets = parent.navigation.months.compactMap { month -> PHAsset? in
        guard let date = month.date, calendar.isDate(date, equalTo: start, toGranularity: .year),
          let raw = month.covers.first, raw < fetch.count else { return nil }
        return fetch.object(at: raw)
      }
      yearCache[period.id] = assets
      return assets
    }
    private var lifeTimer: Timer?
    /// Years rotate covers while idle. Only the card nearest the centre moves.
    func startCoverLife() {
      guard lifeTimer == nil else { return }
      lifeTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, let collection = self.collection else { return }
          let idle = !self.userScrolledRecently && self.parent.navigation.level == self.parent.kind
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
          let all = collection.visibleItems().compactMap { $0 as? MacCalendarCell }
          // One player at a time; it stops when the person scrolls or leaves the level.
          if !idle { all.forEach { $0.stopVideo() }; return }
          let center = CGPoint(x: collection.visibleRect.midX, y: collection.visibleRect.midY)
          func nearest(_ cells: [MacCalendarCell]) -> MacCalendarCell? {
            cells.min { hypot($0.view.frame.midX - center.x, $0.view.frame.midY - center.y)
              < hypot($1.view.frame.midX - center.x, $1.view.frame.midY - center.y) }
          }
          if self.parent.kind == .years { nearest(all.filter { $0.hasChoices })?.rotate(); return }
          let playing = all.filter { $0.isPlayingVideo }
          playing.forEach { $0.stopVideo() }
          let next = nearest(all.filter { $0.hasVideoCover && !playing.contains($0) }) ?? nearest(playing)
          next?.playVideo()
        }
      }
    }
    private var lastUserScroll = Date.distantPast
    private var userScrolledRecently: Bool { Date().timeIntervalSince(lastUserScroll) < 2 }
    func stop() {
      opening?.cancel(); lifeTimer?.invalidate(); lifeTimer = nil
      if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
    }
  }
  static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) { coordinator.stop() }
}

@MainActor private final class MacCalendarCollection: NSCollectionView {
  /// A faded-out level layer must not take clicks meant for the level above it.
  override func hitTest(_ point: NSPoint) -> NSView? {
    (enclosingScrollView?.alphaValue ?? 1) < 0.05 ? nil : super.hitTest(point)
  }
  /// Single click selects a cover (outline); double click, Return or Space opens it.
  var select: ((IndexPath, CGPoint) -> Void)?
  var open: ((IndexPath, CGPoint) -> Void)?
  var openSelected: (() -> Void)?
  private var lastWidth: CGFloat = 0
  override func layout() {
    if lastWidth != bounds.width { lastWidth = bounds.width; collectionViewLayout?.invalidateLayout() }
    super.layout()
  }
  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    guard let path = indexPathForItem(at: point) else { return }
    if event.clickCount >= 2 { open?(path, point) } else { select?(path, point) }
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 36 || event.charactersIgnoringModifiers == " " { openSelected?(); return }
    super.keyDown(with: event)
  }
}

@MainActor private final class MacCalendarCell: NSCollectionViewItem {
  private let canvas = MacCalendarCover()
  private var requests: [PHImageRequestID] = []
  private weak var pipeline: ThumbnailPipeline?
  private var token = UUID()
  override func loadView() { view = canvas }
  /// The asset a cover currently shows; a tap and a video cover use it.
  func coverIndex(at point: CGPoint) -> Int? { canvas.coverIndex(at: canvas.convert(point, from: canvas.superview)) }
  func setSelectedCover(_ index: Int?) { canvas.setSelectedCover(index) }
  func setPin(_ value: CGFloat) { canvas.pin = value }
  private(set) var heroAsset: PHAsset?
  private(set) var coverAssets: [PHAsset] = []
  private var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private var playerLayer: AVPlayerLayer?
  private var videoRequest: PHImageRequestID = PHInvalidImageRequestID
  var isPlayingVideo: Bool { player != nil }
  var hasVideoCover: Bool { coverAssets.contains { $0.mediaType == .video } }
  /// A video cover plays muted and looping, from local media only, while idle.
  func playVideo() {
    guard player == nil, let index = coverAssets.firstIndex(where: { $0.mediaType == .video }),
      let host = canvas.images.indices.contains(index) ? canvas.images[index] : nil, !host.isHidden else { return }
    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = false
    options.deliveryMode = .fastFormat
    let expected = token
    videoRequest = PHImageManager.default().requestPlayerItem(forVideo: coverAssets[index], options: options) { [weak self] item, _ in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self, self.token == expected, self.player == nil, let item else { return }
          let queue = AVQueuePlayer()
          queue.isMuted = true
          self.looper = AVPlayerLooper(player: queue, templateItem: item)
          let layer = AVPlayerLayer(player: queue)
          layer.videoGravity = .resizeAspectFill
          layer.frame = host.bounds
          layer.cornerRadius = 8; layer.masksToBounds = true
          layer.opacity = 0
          host.wantsLayer = true
          host.layer?.insertSublayer(layer, at: 0)
          self.player = queue; self.playerLayer = layer
          queue.play()
          let fade = CABasicAnimation(keyPath: "opacity")
          fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.3
          layer.opacity = 1; layer.add(fade, forKey: "fade")
        }
      }
    }
  }
  func stopVideo() {
    if videoRequest != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(videoRequest); videoRequest = PHInvalidImageRequestID }
    player?.pause(); looper?.disableLooping()
    playerLayer?.removeFromSuperlayer()
    player = nil; looper = nil; playerLayer = nil
  }
  private var choices: [PHAsset] = []
  private var choiceIndex = 0
  var hasChoices: Bool { choices.count > 1 }
  var heroFrame: CGRect { canvas.images.first?.convert(canvas.images[0].bounds, to: nil) ?? .zero }
  var heroView: NSView? { canvas.images.first }
  func coverView(_ index: Int) -> MacCalendarImage? { canvas.images.indices.contains(index) ? canvas.images[index] : nil }
  /// Years rotate through real month representatives with a cross-fade.
  func rotate() {
    guard choices.count > 1, let pipeline else { return }
    choiceIndex = (choiceIndex + 1) % choices.count
    let asset = choices[choiceIndex]
    let expected = token
    pipeline.request(asset, pixels: 900) { [weak self] image, _ in
      guard let self, self.token == expected, let image else { return }
      let fade = CATransition(); fade.type = .fade; fade.duration = 0.6
      guard self.choices.indices.contains(self.choiceIndex), self.choices[self.choiceIndex] == asset else { return }
      self.canvas.images[0].layer?.add(fade, forKey: "rotate")
      self.canvas.images[0].show(image, of: asset)
      self.heroAsset = asset
    }
  }
  /// Shows one of the card's own month photos immediately, from pixels already
  /// on screen, then sharpens it.
  @discardableResult func show(choice assetID: String, image: NSImage?) -> Bool {
    guard let index = choices.firstIndex(where: { $0.localIdentifier == assetID }) else { return false }
    if canvas.images[0].asset?.localIdentifier == assetID { return true }
    let asset = choices[index]
    choiceIndex = index; heroAsset = asset
    if let image { canvas.images[0].show(image, of: asset) }
    let expected = token
    pipeline?.request(asset, pixels: 900) { [weak self] sharp, _ in
      guard let self, self.token == expected, let sharp, self.heroAsset == asset else { return }
      self.canvas.images[0].show(sharp, of: asset)
    }
    return true
  }
  func configure(period: LibraryCalendarPeriod, assets: [PHAsset], choices: [PHAsset] = [], kind: MacLibraryLevel, pipeline: ThumbnailPipeline,
    mirrored: Bool = false) {
    cancel(); self.pipeline = pipeline
    coverAssets = assets
    heroAsset = assets.first; self.choices = choices.isEmpty ? [] : choices; choiceIndex = 0
    if let first = assets.first, let at = self.choices.firstIndex(where: { $0.localIdentifier == first.localIdentifier }) { choiceIndex = at }
    canvas.kind = kind
    canvas.pin = 0
    canvas.mirrored = mirrored
    canvas.title.stringValue = period.title
    canvas.images.forEach { $0.image = nil; $0.asset = nil }
    for (index, label) in canvas.days.enumerated() {
      label.stringValue = kind == .months && index < assets.count
        ? (assets[index].creationDate?.formatted(.dateTime.day()) ?? "") : ""
    }
    canvas.count = assets.count; canvas.needsLayout = true
    view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
    view.setAccessibilityLabel(period.title)
    view.setAccessibilityIdentifier("library.period." + period.id)
    let expected = token
    for (index, asset) in assets.enumerated() {
      requests.append(pipeline.request(asset, pixels: index == 0 ? 900 : 360) { [weak self] image, _ in
        guard let self, self.token == expected, let image else { return }
        // A rotation may already show another month's photo in the hero.
        if index == 0, let hero = self.heroAsset, hero != asset { return }
        self.canvas.images[index].show(image, of: asset)
      })
    }
  }
  private func cancel() { stopVideo(); requests.forEach { pipeline?.cancel($0) }; requests.removeAll(); token = UUID() }
  override func prepareForReuse() { super.prepareForReuse(); cancel() }
}

/// Years are portrait cards with the year at top left. A month is a heading
/// above a four-by-two lattice: one hero two cells square beside smaller covers,
/// each labelled with its day number, as in Photos.
@MainActor private final class MacCalendarCover: NSView {
  static let gap: CGFloat = 8
  static let headingHeight: CGFloat = 40
  /// Six-column lattice: cell size follows the module width.
  static func cell(width: CGFloat) -> CGFloat { (width - 5 * gap) / 6 }
  /// Rows by sampled cover count: landscape card, portrait pair, hero beside two
  /// squares, wide hero over three squares, then hero with side column and a
  /// bottom wide card or two small cards.
  private static func rows(_ count: Int) -> Int {
    switch count { case ...1: return 3; case 2: return 4; case 3: return 4; case 4: return 5; default: return 6 }
  }
  static func monthHeight(width: CGFloat, count: Int) -> CGFloat {
    let unit = cell(width: width), rows = rows(count)
    return headingHeight + CGFloat(rows) * unit + CGFloat(rows - 1) * gap
  }
  var kind: MacLibraryLevel = .years { didSet { configureKind() } }
  /// A month heading stays at the top of the visible area while its module
  /// scrolls under it, on a material pill, then is pushed away by the next.
  private let pillBackground = NSVisualEffectView()
  var pin: CGFloat = 0 {
    didSet {
      guard pin != oldValue else { return }
      needsLayout = true
      let pinned = pin > 0.5
      if (pillBackground.alphaValue > 0.5) != pinned {
        NSAnimationContext.runAnimationGroup { $0.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
          pillBackground.animator().alphaValue = pinned ? 1 : 0 }
      }
    }
  }
  let title = NSTextField(labelWithString: "")
  let images = (0..<6).map { _ in MacCalendarImage() }
  let days = (0..<6).map { _ in NSTextField(labelWithString: "") }
  var count = 0
  /// Alternate months mirror their composition, as on iPhone.
  var mirrored = false
  override var isFlipped: Bool { true }
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect); wantsLayer = true
    for image in images {
      image.wantsLayer = true; image.layer?.cornerRadius = 8; image.layer?.masksToBounds = true
      image.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
      addSubview(image)
    }
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.65); shadow.shadowBlurRadius = 4
    for label in days {
      label.font = .systemFont(ofSize: 13, weight: .bold); label.textColor = .white; label.shadow = shadow
      label.lineBreakMode = .byClipping
      addSubview(label)
    }
    title.shadow = shadow
    pillBackground.material = .headerView; pillBackground.blendingMode = .withinWindow; pillBackground.state = .active
    pillBackground.wantsLayer = true; pillBackground.layer?.cornerRadius = 16; pillBackground.layer?.masksToBounds = true
    pillBackground.alphaValue = 0
    addSubview(pillBackground)
    addSubview(title)
    configureKind()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  private func configureKind() {
    if kind == .years {
      title.font = .systemFont(ofSize: 27, weight: .bold); title.textColor = .white
      title.shadow = { let s = NSShadow(); s.shadowColor = .black.withAlphaComponent(0.65); s.shadowBlurRadius = 5; return s }()
    } else {
      title.font = .systemFont(ofSize: 20, weight: .bold); title.textColor = .labelColor
      title.shadow = nil
    }
    needsLayout = true
  }
  /// Cells on the six-column lattice: (column, row, columns, rows).
  private func lattice(_ count: Int) -> [(Int, Int, Int, Int)] {
    var cells: [(Int, Int, Int, Int)]
    switch count {
    case 0: return []
    case 1: cells = [(0, 0, 6, 3)]
    case 2: cells = [(0, 0, 3, 4), (3, 0, 3, 4)]
    case 3: cells = [(0, 0, 4, 4), (4, 0, 2, 2), (4, 2, 2, 2)]
    case 4: cells = [(0, 0, 6, 3), (0, 3, 2, 2), (2, 3, 2, 2), (4, 3, 2, 2)]
    case 5: cells = [(0, 0, 4, 4), (4, 0, 2, 2), (4, 2, 2, 2), (0, 4, 4, 2), (4, 4, 2, 2)]
    default: cells = [(0, 0, 4, 4), (4, 0, 2, 2), (4, 2, 2, 2), (0, 4, 2, 2), (2, 4, 2, 2), (4, 4, 2, 2)]
    }
    guard mirrored, count >= 3, count != 4 else { return cells }
    return cells.map { (6 - $0.0 - $0.2, $0.1, $0.2, $0.3) }
  }
  override func layout() {
    super.layout()
    if kind == .years {
      for (i, image) in images.enumerated() {
        image.isHidden = i != 0 || count == 0
        image.frame = bounds
      }
      days.forEach { $0.isHidden = true }
      pillBackground.isHidden = true
      title.frame = CGRect(x: 14,y: 12,width: max(0,bounds.width-28),height: 34)
      return
    }
    let titleWidth = min(bounds.width - 28, ceil(title.intrinsicContentSize.width) + 4)
    let pinned = pin > 0.5
    pillBackground.isHidden = false
    pillBackground.frame = CGRect(x: pinned ? 8 : -14, y: 2 + pin, width: titleWidth + 28, height: 32)
    title.frame = CGRect(x: pillBackground.frame.minX + 14, y: pillBackground.frame.minY + 2, width: titleWidth, height: 28)
    let gap = Self.gap
    let unit = Self.cell(width: bounds.width)
    let top = Self.headingHeight
    let cells = lattice(min(count, 6))
    for (i, image) in images.enumerated() {
      guard i < cells.count else { image.isHidden = true; days[i].isHidden = true; continue }
      let (c, r, w, h) = cells[i]
      image.isHidden = false
      image.frame = CGRect(x: CGFloat(c) * (unit + gap), y: top + CGFloat(r) * (unit + gap),
        width: CGFloat(w) * unit + CGFloat(w - 1) * gap, height: CGFloat(h) * unit + CGFloat(h - 1) * gap)
      days[i].isHidden = false
      days[i].font = .systemFont(ofSize: i == 0 ? 17 : 13, weight: .bold)
      days[i].frame = CGRect(x: image.frame.minX + 10, y: image.frame.minY + 8, width: 60, height: 22)
    }
    for i in cells.count..<days.count { days[i].isHidden = true }
  }
  /// `point` arrives in the superview's coordinates.
  override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
  /// Which sampled cover lies under `point` (in this view's coordinates).
  func coverIndex(at point: CGPoint) -> Int? {
    images.indices.first { !images[$0].isHidden && images[$0].frame.contains(point) }
  }
  func setSelectedCover(_ index: Int?) {
    for (i, image) in images.enumerated() { image.outlined = i == index }
  }
}

@MainActor fileprivate final class MacCalendarImage: NSView {
  var image: NSImage? { didSet { needsDisplay = true } }
  /// The asset whose pixels `image` holds. Set together with `image`: a late
  /// request callback could otherwise leave the pixels and the identity apart,
  /// and a level flight would carry the wrong photo.
  var asset: PHAsset?
  func show(_ image: NSImage, of asset: PHAsset) { self.asset = asset; self.image = image }
  /// Accent outline on a selected cover, as Photos draws it.
  var outlined = false { didSet { outline.isHidden = !outlined } }
  private let outline: CALayer = {
    let layer = CALayer()
    layer.borderWidth = 3; layer.cornerRadius = 8; layer.isHidden = true
    layer.actions = ["borderColor": NSNull(), "hidden": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
    return layer
  }()
  override func layout() {
    super.layout()
    outline.frame = bounds
  }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if outline.superlayer == nil, let layer {
      outline.borderColor = NSColor.controlAccentColor.cgColor
      layer.addSublayer(outline)
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let image, image.size.width > 0, image.size.height > 0 else { return }
    let scale = max(bounds.width/image.size.width,bounds.height/image.size.height)
    let size = CGSize(width: image.size.width*scale,height: image.size.height*scale)
    NSGraphicsContext.saveGraphicsState(); bounds.clip()
    image.draw(in: CGRect(x: (bounds.width-size.width)/2,y: (bounds.height-size.height)/2,
      width: size.width,height: size.height),from: .zero,operation: .sourceOver,fraction: 1,
      respectFlipped: true,hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
  }
}


/// Gapless overview mosaic drawn as pooled layers: a Time Profiler capture of the
/// iPhone grid showed per-photo views dominating the main thread at these
/// densities, so no cells exist here, only positioned image layers for the
/// visible rows. The same drawing serves the settled grid and a stage face.
@MainActor final class MacDenseCanvas: NSView {
  var count = 0
  var pipeline: ThumbnailPipeline?
  var assetAt: ((Int) -> PHAsset?)?
  /// Key and date without faulting the asset, once the prefill has read them.
  var factAt: ((Int) -> MacThumbnailTables.Fact?)?
  private var layers: [Int: CALayer] = [:]
  private var requests: [Int: PHImageRequestID] = [:]
  private var pool: [CALayer] = []
  private static let actions: [String: CAAction] = [
    "contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "frame": NSNull(),
    "opacity": NSNull(), "hidden": NSNull(), "backgroundColor": NSNull(), "sublayers": NSNull(),
  ]
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect); wantsLayer = true; layer?.masksToBounds = true
    layer?.actions = Self.actions
    layerContentsRedrawPolicy = .never
  }
  // The canvas draws nothing itself; its tiles are sublayers.
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() {}
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  private func snap(_ value: CGFloat) -> CGFloat {
    let scale = window?.backingScaleFactor ?? 2
    return (value * scale).rounded() / scale
  }
  /// Fraction of drawn tiles that already show pixels.
  var loadedFraction: CGFloat {
    guard !layers.isEmpty else { return 1 }
    return CGFloat(layers.values.filter { $0.contents != nil }.count) / CGFloat(layers.count)
  }
  func index(at point: CGPoint, columns: Int, origin: CGPoint, pitch: CGFloat, leading: Int = 0) -> Int? {
    guard columns > 0, pitch > 0, point.x >= origin.x, point.y >= origin.y else { return nil }
    let col = Int((point.x - origin.x) / pitch), row = Int((point.y - origin.y) / pitch)
    guard col < columns else { return nil }
    let index = row * columns + col - leading
    return index >= 0 && index < count ? index : nil
  }
  func render(columns: Int, origin: CGPoint, pitch: CGFloat, visible: CGRect, leading: Int = 0, pinTop: CGFloat? = nil) {
    guard count > 0, columns > 0, pitch > 0.5 else { reset(); return }
    let scale = window?.backingScaleFactor ?? 2
    let rowStart = max(0, Int(floor((visible.minY - origin.y) / pitch)) - 1)
    let rowEnd = min((count - 1 + leading) / columns, Int(ceil((visible.maxY - origin.y) / pitch)) + 1)
    guard rowStart <= rowEnd else { reset(); return }
    let colStart = max(0, Int(floor((visible.minX - origin.x) / pitch)) - 1)
    let colEnd = min(columns - 1, Int(ceil((visible.maxX - origin.x) / pitch)) + 1)
    var keep = Set<Int>()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    if colStart <= colEnd {
      for row in rowStart...rowEnd {
        let y0 = snap(origin.y + CGFloat(row) * pitch), y1 = snap(origin.y + CGFloat(row + 1) * pitch)
        for col in colStart...colEnd {
          let index = row * columns + col - leading
          guard index >= 0, index < count else { continue }
          keep.insert(index)
          let x0 = snap(origin.x + CGFloat(col) * pitch), x1 = snap(origin.x + CGFloat(col + 1) * pitch)
          let layer: CALayer
          if let existing = layers[index] { layer = existing } else {
            layer = pool.popLast() ?? makeLayer()
            layer.contents = nil
            self.layer?.addSublayer(layer)
            layers[index] = layer
          }
          layer.frame = CGRect(x: x0, y: y0, width: max(0.5, x1 - x0), height: max(0.5, y1 - y0))
          if layer.contents == nil, requests[index] == nil, let pipeline {
            let pixels = max(64, (pitch * scale).rounded(.up))
            // A stored decoded thumbnail needs no request at all, and with the
            // prefill's key no asset either.
            let known = factAt?(index)
            let found = known == nil ? assetAt?(index) : nil
            guard let key = known?.key ?? found.map(MacThumbnailTables.key) else { continue }
            let stored = MacThumbnailTables.image(key: key, pixels: pitch * scale)
            if let stored { layer.contents = stored.image }
            if stored?.sharp != true, let asset = found ?? assetAt?(index) {
              let id = pipeline.request(asset, pixels: pixels, priority: .visible) { [weak self, weak layer] image, _ in
                guard let self, let layer, self.layers[index] === layer, let image else { return }
                CATransaction.begin(); CATransaction.setDisableActions(true)
                layer.contents = image
                CATransaction.commit()
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                  MacThumbnailTables.remember(asset, pixels: pitch * scale, image: cg)
                }
              }
              if id != PHInvalidImageRequestID { requests[index] = id }
            }
          }
        }
      }
    }
    for index in Array(layers.keys) where !keep.contains(index) {
      if let id = requests.removeValue(forKey: index) { pipeline?.cancel(id) }
      if let layer = layers.removeValue(forKey: index) {
        layer.removeFromSuperlayer(); layer.contents = nil
        if pool.count < 3000 { pool.append(layer) }
      }
    }
    renderPills(columns: columns, origin: origin, pitch: pitch, rows: rowStart...rowEnd, leading: leading,
      pin: pinTop ?? visible.minY + 4)
    CATransaction.commit()
  }
  // MARK: Period pills
  /// Overview mosaics carry light period pills, as on iPhone: a month pill with
  /// a quiet year in the month overview, the year alone in the yearly one. Each
  /// sits at the row where its period begins; the current one stays pinned at
  /// the top until the next pushes it away.
  private var pills: [String: CALayer] = [:]
  private static var pillImages: [String: CGImage] = [:]
  private static var titles: [String: String] = [:]
  private func periodKey(_ index: Int, yearly: Bool) -> (key: String, title: String)? {
    let date: Date?
    if let fact = factAt?(index) { date = fact.date } else {
      guard let asset = assetAt?(index) else { return nil }
      date = asset.creationDate
    }
    guard let date else {
      let unknown = NSLocalizedString("design_capture_unknown", comment: "")
      return ("?", unknown)
    }
    let parts = Calendar.current.dateComponents([.year, .month], from: date)
    let key = yearly ? "\(parts.year ?? 0)" : "\(parts.year ?? 0)-\(parts.month ?? 0)"
    if let title = Self.titles[key] { return (key, title) }
    let title = yearly ? date.formatted(.dateTime.year()) : date.formatted(.dateTime.year().month(.wide))
    Self.titles[key] = title
    return (key, title)
  }
  private func renderPills(columns: Int, origin: CGPoint, pitch: CGFloat, rows: ClosedRange<Int>, leading: Int, pin: CGFloat) {
    let yearly = columns >= (MacLibraryDensity.overview.last ?? 40)
    func lastItem(_ row: Int) -> Int { min(count - 1, (row + 1) * columns - 1 - leading) }
    func firstItem(_ row: Int) -> Int { max(0, row * columns - leading) }
    // Rows where a period begins, newest period of the row named.
    var starts: [(y: CGFloat, key: String, title: String)] = []
    var previous: String? = rows.lowerBound > 0 ? periodKey(lastItem(rows.lowerBound - 1), yearly: yearly)?.key : nil
    for row in rows {
      let first = firstItem(row), last = lastItem(row)
      guard first <= last, let head = periodKey(first, yearly: yearly), let tail = periodKey(last, yearly: yearly) else { continue }
      if head.key != previous || tail.key != head.key {
        starts.append((origin.y + CGFloat(row) * pitch + 6, tail.key, tail.title))
      }
      previous = tail.key
    }
    // The period already under way at the top is pinned there.
    var placed: [(y: CGFloat, key: String, title: String)] = []
    let topRow = max(rows.lowerBound, Int(floor((pin - origin.y) / pitch)))
    if let current = periodKey(max(0, firstItem(topRow)), yearly: yearly) {
      let next = starts.first { $0.y > pin + 1 && $0.key != current.key }
      let y = min(pin, (next?.y ?? .greatestFiniteMagnitude) - 40)
      placed.append((y, current.key, current.title))
    }
    // Pills never overlap: one beginning too close below the last is skipped.
    for start in starts where start.y > pin + 1 && start.key != placed.last?.key
      && start.y >= (placed.last?.y ?? -.greatestFiniteMagnitude) + 40 {
      placed.append(start)
    }
    var keep = Set<String>()
    let scale = window?.backingScaleFactor ?? 2
    for pill in placed {
      guard let image = Self.pillImage(pill.title, yearly: yearly, scale: scale) else { continue }
      keep.insert(pill.key)
      let layer: CALayer
      if let existing = pills[pill.key] { layer = existing } else {
        layer = CALayer(); layer.actions = Self.actions; layer.zPosition = 30
        self.layer?.addSublayer(layer); pills[pill.key] = layer
      }
      layer.contents = image; layer.contentsScale = scale
      layer.frame = CGRect(x: origin.x + 12, y: pill.y, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
    for key in Array(pills.keys) where !keep.contains(key) { pills.removeValue(forKey: key)?.removeFromSuperlayer() }
  }
  private static func pillImage(_ title: String, yearly: Bool, scale: CGFloat) -> CGImage? {
    let cacheKey = "\(yearly)|\(scale)|\(title)"
    if let cached = pillImages[cacheKey] { return cached }
    let text = NSMutableAttributedString(string: title, attributes: [
      .foregroundColor: NSColor.black, .font: NSFont.systemFont(ofSize: 15, weight: .semibold)])
    if !yearly, let year = title.range(of: "[0-9]{4}年?", options: .regularExpression) {
      text.addAttribute(.foregroundColor, value: NSColor.black.withAlphaComponent(0.5), range: NSRange(year, in: title))
    }
    let size = text.size()
    let pill = CGSize(width: ceil(size.width) + 20, height: 30)
    let image = NSImage(size: pill, flipped: false) { rect in
      NSColor.white.withAlphaComponent(0.88).setFill()
      NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
      text.draw(at: CGPoint(x: 10, y: (pill.height - size.height) / 2))
      return true
    }
    var rect = CGRect(origin: .zero, size: pill)
    let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
    if let cg { pillImages[cacheKey] = cg }
    return cg
  }
  private func makeLayer() -> CALayer {
    let layer = CALayer()
    layer.actions = Self.actions
    layer.contentsGravity = .resizeAspectFill
    layer.masksToBounds = true
    layer.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    return layer
  }
  func reset() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for (index, layer) in layers {
      if let id = requests.removeValue(forKey: index) { pipeline?.cancel(id) }
      layer.removeFromSuperlayer(); layer.contents = nil
    }
    layers.removeAll(); requests.removeAll()
    pills.values.forEach { $0.removeFromSuperlayer() }; pills.removeAll()
    CATransaction.commit()
  }
}

/// A transition tile is layers only. The stage resizes tiles every frame; a cell
/// view there re-rasterized its SF Symbol and text badges on each frame, which
/// held the main thread for most of a zoom step. Here the content is laid out
/// once at the reference size and scaled by the GPU through `sublayerTransform`.
@MainActor private final class MacZoomMediaTile: NSView {
  private(set) var displayedImage: NSImage?
  private let content = CALayer()
  private let photo = CALayer()
  private let durationLayer = CATextLayer()
  private let mediaLayer = CALayer()
  private let outline = CALayer()
  private var reference: CGFloat = 1
  private var fitted = false
  private var aspect: CGFloat = 1
  private weak var pipeline: ThumbnailPipeline?
  private var request = PHInvalidImageRequestID
  private static var symbols: [String: CGImage] = [:]
  private static let still: [String: CAAction] = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(),
    "frame": NSNull(), "hidden": NSNull(), "transform": NSNull(), "sublayerTransform": NSNull(), "opacity": NSNull()]
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .never
    for item in [content, photo, durationLayer, mediaLayer, outline] { item.actions = Self.still }
    layer?.actions = Self.still
    layer?.masksToBounds = true
    layer?.addSublayer(content)
    content.anchorPoint = .zero
    photo.contentsGravity = .resizeAspectFill; photo.masksToBounds = true
    photo.backgroundColor = NSColor(DuckColors.subtle).cgColor
    content.addSublayer(photo)
    durationLayer.fontSize = 12; durationLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    durationLayer.foregroundColor = .white; durationLayer.alignmentMode = .center
    durationLayer.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
    durationLayer.cornerRadius = 5; durationLayer.isHidden = true
    content.addSublayer(durationLayer)
    mediaLayer.contentsGravity = .resizeAspect; mediaLayer.isHidden = true
    content.addSublayer(mediaLayer)
    outline.borderWidth = 3; outline.borderColor = NSColor.controlAccentColor.cgColor; outline.isHidden = true
    content.addSublayer(outline)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override var isFlipped: Bool { false }
  func configure(_ asset: PHAsset, side: CGFloat, pixels: CGFloat, pipeline: ThumbnailPipeline,
    originalAspect: Bool, selected: Bool, scale: CGFloat) {
    reference = max(1, side); fitted = originalAspect
    aspect = asset.pixelHeight > 0 ? CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight) : 1
    self.pipeline = pipeline
    for item in [content, photo, durationLayer, mediaLayer, outline] { item.contentsScale = scale }
    durationLayer.string = asset.mediaType == .video ? videoDurationLabel(asset.duration) : nil
    durationLayer.isHidden = asset.mediaType != .video
    let symbol = asset.burstIdentifier != nil ? "square.stack" : asset.mediaSubtypes.contains(.photoLive) ? "livephoto" : nil
    mediaLayer.contents = symbol.flatMap { Self.symbol($0, scale: scale) }
    mediaLayer.isHidden = symbol == nil
    outline.isHidden = !selected
    arrange()
    if let stored = MacThumbnailTables.placeholder(asset) { photo.contents = stored }
    request = pipeline.request(asset, pixels: pixels, contentMode: .aspectFill) { [weak self] image, _ in
      guard let self, let image else { return }
      self.show(image)
    }
  }
  func show(_ image: NSImage) {
    displayedImage = image
    photo.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
  }
  func cancel() { pipeline?.cancel(request); request = PHInvalidImageRequestID }
  private static func symbol(_ name: String, scale: CGFloat) -> CGImage? {
    if let cached = symbols[name] { return cached }
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold).applying(.init(paletteColors: [.white]))) else { return nil }
    var rect = CGRect(origin: .zero, size: base.size)
    let image = base.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
    symbols[name] = image
    return image
  }
  /// Content is laid out once at the reference size.
  private func arrange() {
    let b = CGRect(x: 0, y: 0, width: reference, height: reference)
    content.bounds = b
    var f = b
    if fitted {
      let inset = b.insetBy(dx: b.width * 0.055, dy: b.height * 0.055)
      if aspect >= 1 { let h = inset.width / aspect; f = CGRect(x: inset.minX, y: inset.midY - h / 2, width: inset.width, height: h) }
      else { let w = inset.height * aspect; f = CGRect(x: inset.midX - w / 2, y: inset.minY, width: w, height: inset.height) }
      photo.cornerRadius = b.width * 0.035; outline.cornerRadius = photo.cornerRadius
      layer?.backgroundColor = NSColor.clear.cgColor; photo.backgroundColor = NSColor.clear.cgColor
    }
    photo.frame = f; outline.frame = f
    let width = max(42, (durationLayer.preferredFrameSize().width) + 12)
    durationLayer.frame = CGRect(x: f.maxX - width - 7, y: f.minY + 7, width: width, height: 18)
    mediaLayer.frame = CGRect(x: f.minX + 7, y: f.minY + 7, width: 18, height: 18)
  }
  /// Per frame: only a transform changes, so nothing is redrawn.
  override func layout() {
    super.layout()
    let k = bounds.width / reference
    CATransaction.begin(); CATransaction.setDisableActions(true)
    content.position = .zero
    content.transform = CATransform3DMakeScale(k, bounds.height / reference, 1)
    CATransaction.commit()
  }
}

/// One coherent lattice per density. Every face places the same anchor asset at
/// the same in-tile fraction under the shared focus, so faces align at equal
/// pitch and wrapped rows never interpolate through each other. Faces crossfade;
/// the native collection owns settled browsing and selection.
@MainActor final class MacGridZoomStage: NSView {
  var count: Int
  private(set) var anchor: Int
  private(set) var fraction: CGPoint
  /// Displayed lattice pitch (cell plus gap) and the viewport point that holds
  /// the anchor's focal fraction.
  var pitch: CGFloat
  var focus: CGPoint
  private(set) var shown: Int
  var makeTile: ((Int,CGFloat) -> NSView)?
  var releaseTile: ((NSView) -> Void)?
  var referenceSide: (Int) -> CGFloat = { _ in 1 }
  var denseAsset: ((Int) -> PHAsset?)?
  var denseFact: ((Int) -> MacThumbnailTables.Fact?)?
  var thumbnails: ThumbnailPipeline?
  private func faceGap(_ columns: Int) -> CGFloat { MacLibraryDensity.isDense(columns) ? 0 : 2 }
  private final class Face: NSView {
    let columns: Int
    /// Empty slots before the first photo in this density.
    var leading = 0
    var canvas: MacDenseCanvas?
    var tiles: [String: (Int,NSView)] = [:]
    var weight: CGFloat = 0
    override var isFlipped: Bool { true }
    init(columns: Int) { self.columns = columns; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }
  private var faces: [Int: Face] = [:]
  private var order: [Int] = []
  private var blend: (from: [Int: CGFloat], target: Int, start: CFTimeInterval, duration: CFTimeInterval, requested: CFTimeInterval)?
  /// Outgoing faces stay opaque until the shown face has most of its pixels,
  /// bounded so cloud-only media cannot hold a crossfade indefinitely.
  static let pixelWait: CFTimeInterval = 0.15
  /// A face fades in over this long when it first becomes the previewed density.
  static let fadeDuration: CFTimeInterval = 0.22
  override var isFlipped: Bool { true }
  var isBlending: Bool { blend != nil }
  init(count: Int,anchor: Int,fraction: CGPoint,columns: Int,pitch: CGFloat,focus: CGPoint) {
    self.count = count; self.anchor = anchor; self.fraction = fraction
    self.pitch = pitch; self.focus = focus; shown = columns
    super.init(frame: .zero); wantsLayer = true; layer?.masksToBounds = true
    layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  func ensureFace(_ columns: Int,opacity: CGFloat,leading: Int = 0) {
    guard faces[columns] == nil else { return }
    let face = Face(columns: columns)
    face.leading = leading
    face.weight = opacity; face.alphaValue = opacity
    addSubview(face); faces[columns] = face; order.append(columns)
    render()
  }
  /// Moves the shared focus to a viewport point without moving any pixel, and
  /// adopts the tile under it as the anchor on the shown density.
  func reanchor(to point: CGPoint) {
    guard faces[shown] != nil else { return }
    let columns = shown, side = max(1,pitch-faceGap(shown))
    let origin = lattice(columns: columns,side: side)
    let lead = faces[shown]?.leading ?? 0
    let column = min(columns-1,max(0,Int(floor((point.x-origin.x)/pitch))))
    let row = max(0,Int(floor((point.y-origin.y)/pitch)))
    let index = min(max(0,count-1),max(0,row*columns+column-lead))
    let cell = CGPoint(x: origin.x+CGFloat((index+lead)%columns)*pitch,y: origin.y+CGFloat((index+lead)/columns)*pitch)
    fraction = CGPoint(x: min(1,max(0,(point.x-cell.x)/side)),y: min(1,max(0,(point.y-cell.y)/side)))
    anchor = index; focus = point
    render()
  }
  private func lattice(columns: Int,side: CGFloat) -> CGPoint {
    let slot = anchor+(faces[columns]?.leading ?? 0)
    return CGPoint(x: focus.x-CGFloat(slot%columns)*pitch-fraction.x*side,
      y: focus.y-CGFloat(slot/columns)*pitch-fraction.y*side)
  }
  func show(_ columns: Int,animated: Bool,at now: CFTimeInterval = CACurrentMediaTime()) {
    guard faces[columns] != nil else { return }
    advanceBlend(to: now)
    guard animated else {
      shown = columns; blend = nil
      for face in faces.values { face.weight = face.columns == columns ? 1 : 0 }
      applyWeights(); prune(); render(); return
    }
    guard columns != shown else { return }
    shown = columns
    let from = faces.mapValues(\.weight)
    blend = (from,columns,now,max(0.05,Self.fadeDuration*Double(1-from[columns,default: 0])),now)
  }
  /// Fraction of a face's tiles that already show pixels.
  private func loaded(_ face: Face) -> CGFloat {
    if let canvas = face.canvas { return canvas.loadedFraction }
    guard !face.tiles.isEmpty else { return 1 }
    let ready = face.tiles.values.reduce(0) { $0 + (($1.1 as? MacZoomMediaTile)?.displayedImage != nil ? 1 : 0) }
    return CGFloat(ready) / CGFloat(face.tiles.count)
  }
  func advanceBlend(to now: CFTimeInterval) {
    guard var b = blend else { return }
    if let target = faces[b.target], loaded(target) < 0.8, now - b.requested < Self.pixelWait {
      // The incoming face is still blank: holding the crossfade shows pixels
      // instead of a flash of empty tiles.
      b.start = now; blend = b
      for face in faces.values { face.weight = b.from[face.columns, default: 0] }
      applyWeights()
      return
    }
    let t = CGFloat(min(1,max(0,(now-b.start)/b.duration)))
    for face in faces.values {
      face.weight = b.from[face.columns,default: 0]*(1-t)+(face.columns == b.target ? t : 0)
    }
    if t >= 1 { blend = nil }
    applyWeights()
    if blend == nil { prune() }
  }
  /// A release finishes a held crossfade with the settle instead of holding a
  /// partially blended pose for the rest of its long fade.
  func hurryBlend(within limit: CFTimeInterval,at now: CFTimeInterval = CACurrentMediaTime()) {
    advanceBlend(to: now)
    guard var b = blend else { return }
    let t = min(1,max(0,(now-b.start)/b.duration)), remaining = (1-t)*b.duration
    guard remaining > limit else { b.requested = now - Self.pixelWait; blend = b; return }
    b.duration = b.duration*limit/remaining
    b.start = now-t*b.duration
    b.requested = now - Self.pixelWait
    blend = b
  }
  private func applyWeights() {
    var above: CGFloat = 0
    for columns in order.reversed() {
      guard let face = faces[columns] else { continue }
      face.alphaValue = min(1,max(0,face.weight/max(0.000001,1-above)))
      above += face.weight
    }
  }
  private func prune() {
    guard blend == nil else { return }
    for (columns,face) in faces where columns != shown && face.weight <= 0.001 {
      release(face); face.removeFromSuperview()
      faces.removeValue(forKey: columns); order.removeAll { $0 == columns }
    }
  }
  private func release(_ face: Face) {
    face.canvas?.reset(); face.canvas?.removeFromSuperview(); face.canvas = nil
    for (_,view) in face.tiles.values { releaseTile?(view); view.removeFromSuperview() }
    face.tiles.removeAll()
  }
  func render() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for face in faces.values { face.frame = bounds; populate(face) }
    CATransaction.commit()
  }
  private func snap(_ value: CGFloat) -> CGFloat {
    let scale = window?.backingScaleFactor ?? 2
    return (value * scale).rounded() / scale
  }
  private func populate(_ face: Face) {
    let gap = faceGap(face.columns), columns = face.columns
    let side = max(1,pitch-gap)
    let origin = lattice(columns: columns,side: side)
    if MacLibraryDensity.isDense(columns) {
      // Overview face: pooled image layers, no per-photo views.
      let canvas: MacDenseCanvas
      if let existing = face.canvas { canvas = existing } else {
        canvas = MacDenseCanvas(frame: bounds); face.addSubview(canvas); face.canvas = canvas
      }
      canvas.frame = bounds
      canvas.count = count
      canvas.pipeline = thumbnails
      canvas.assetAt = denseAsset
      canvas.factAt = denseFact
      canvas.render(columns: columns, origin: origin, pitch: pitch, visible: bounds, leading: face.leading)
      return
    }
    let reference = max(1,referenceSide(columns))
    let rowStart = Int(floor(-origin.y/pitch))-1, rowEnd = Int(ceil((bounds.height-origin.y)/pitch))+1
    // Rows extend past their resting width while scaled down; each extra slot
    // reads its chronological neighbor, so no row is stretched or blank.
    let colStart = Int(floor(-origin.x/pitch))-1, colEnd = Int(ceil((bounds.width-origin.x)/pitch))+1
    var keep = Set<String>()
    for row in rowStart...max(rowStart,rowEnd) {
      for col in colStart...max(colStart,colEnd) {
        let index = row*columns+col-face.leading
        guard index >= 0, index < count else { continue }
        let key = "\(row):\(col)"; keep.insert(key)
        let tile: NSView
        if let old = face.tiles[key], old.0 == index { tile = old.1 }
        else {
          if let old = face.tiles.removeValue(forKey: key) { releaseTile?(old.1); old.1.removeFromSuperview() }
          tile = makeTile?(index,reference) ?? NSView()
          face.addSubview(tile); face.tiles[key] = (index,tile)
        }
        // Edges snap to device pixels from the lattice, so every gap in a frame
        // has one width and tiles never shimmer while the pitch animates.
        let x0 = snap(origin.x+CGFloat(col)*pitch), y0 = snap(origin.y+CGFloat(row)*pitch)
        let x1 = snap(origin.x+CGFloat(col+1)*pitch)-gap, y1 = snap(origin.y+CGFloat(row+1)*pitch)-gap
        let frame = CGRect(x: x0,y: y0,width: max(1,x1-x0),height: max(1,y1-y0))
        if tile.frame != frame { tile.frame = frame; tile.needsLayout = true }
      }
    }
    for key in Array(face.tiles.keys) where !keep.contains(key) {
      if let old = face.tiles.removeValue(forKey: key) { releaseTile?(old.1); old.1.removeFromSuperview() }
    }
  }
  func tile(at index: Int) -> NSView? {
    faces[shown]?.tiles.values.first { $0.0 == index }?.1
      ?? faces.values.lazy.compactMap { $0.tiles.values.first { $0.0 == index }?.1 }.first
  }
  var visibleTileCount: Int { faces.values.reduce(0) { $0+$1.tiles.count } }
  func stop() {
    for face in faces.values { release(face); face.removeFromSuperview() }
    faces.removeAll(); order.removeAll(); blend = nil
  }
}

/// Level layers cross-fade and move on one curve, as Photos does in about a
/// quarter of a second: a coarser layer zooms past the viewer, a finer layer
/// recedes, and the incoming one settles from the opposite side. Model values
/// are set immediately so repeated update passes do not restart a running move.
@MainActor enum MacLevelFade {
  private static func rank(_ level: MacLibraryLevel) -> Int { level == .years ? 0 : level == .months ? 1 : 2 }
  static func apply(_ view: NSView, layer level: MacLibraryLevel, current: MacLibraryLevel) {
    let visible = level == current
    let alpha: CGFloat = visible ? 1 : 0
    let scale: CGFloat = visible ? 1 : rank(level) < rank(current) ? 1.12 : 0.92
    view.wantsLayer = true
    guard let layer = view.layer else { return }
    let to = transform(layer, scale: scale)
    let unchanged = abs(view.alphaValue - alpha) <= 0.001 && CATransform3DEqualToTransform(layer.transform, to)
    guard !unchanged else { return }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      view.alphaValue = alpha; layer.transform = to; return
    }
    let from = layer.presentation()?.transform ?? layer.transform
    layer.transform = to
    let move = CABasicAnimation(keyPath: "transform")
    move.fromValue = NSValue(caTransform3D: from); move.toValue = NSValue(caTransform3D: to)
    move.duration = 0.25; move.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    layer.add(move, forKey: "levelTransform")
    // Opacity animates in Core Animation. An AppKit animator with implicit
    // animation re-ran view layout on the main thread for every frame.
    let fromOpacity = layer.presentation()?.opacity ?? Float(view.alphaValue)
    view.alphaValue = alpha
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = fromOpacity; fade.toValue = Float(alpha)
    fade.duration = 0.25; fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    layer.add(fade, forKey: "levelOpacity")
  }
  /// Scales about the layer's centre whatever its anchor point is.
  private static func transform(_ layer: CALayer, scale: CGFloat) -> CATransform3D {
    guard scale != 1 else { return CATransform3DIdentity }
    let size = layer.bounds.size
    let anchor = CGPoint(x: layer.anchorPoint.x * size.width, y: layer.anchorPoint.y * size.height)
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    var t = CATransform3DMakeTranslation(center.x - anchor.x, center.y - anchor.y, 0)
    t = CATransform3DScale(t, scale, scale, 1)
    return CATransform3DTranslate(t, anchor.x - center.x, anchor.y - center.y, 0)
  }
}






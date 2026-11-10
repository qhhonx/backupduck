import AppKit
import AVFoundation
import Photos
import SwiftUI

struct MacMediaGrid: NSViewRepresentable {
  var source: any MacGridSource
  @ObservedObject var navigation: MacLibraryNavigation
  @ObservedObject var networkPolicy = PreviewNetworkPolicy.shared
  var preparationRevision: String = ""
  var queueRevision: Int64
  var receiverID: String?
  var columns: Int
  var selecting = true
  var readOnly = false
  /// A bounded summary uses the same selection and activation, with outer scrolling.
  var embeddedPreview = false
  var initialLoadingIndicator = false
  var active = true
  var sharedSize: MacGridSize?
  /// The overview table prefill is app-wide and keyed by one fetch: only the
  /// library grid may start it. An album grid reads the tables but would cancel
  /// the library's pass and make it start over when the album closes.
  var prefillsTables = true
  var reducedMotionOverride: Bool?
  var preview: (String) -> Void = { _ in }
  var enterSelection: () -> Void = {}
  var resize: (Int) -> Void = { _ in }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let layout = LibraryTimelineLayout(mode: .all, target: 135)
    // The first layout must already use the chosen column count; a second pass
    // would change the content height under a restored offset.
    layout.requestedColumns = columns
    layout.columns = columns
    layout.denseThreshold = MacLibraryDensity.denseThreshold
    let collection = LibraryCollectionView()
    collection.collectionViewLayout = layout
    collection.autoresizingMask = [.width]
    collection.backgroundColors = [.clear]
    collection.isSelectable = !readOnly
    collection.allowsMultipleSelection = !readOnly
    let canvas = MacDenseCanvas(frame: .zero)
    canvas.autoresizingMask = [.width, .height]
    canvas.isHidden = true
    collection.addSubview(canvas)
    context.coordinator.denseCanvas = canvas
    collection.activateOverview = { [weak coordinator = context.coordinator] point in
      coordinator?.activateOverview(at: point) ?? false
    }
    collection.denseHit = { [weak coordinator = context.coordinator] point in coordinator?.denseIndex(at: point) }
    collection.drill = { [weak coordinator = context.coordinator] index in coordinator?.drillDown(from: index) }
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    context.coordinator.installDataSource(collection)
    collection.delegate = context.coordinator
    collection.toggleSelection = { [weak coordinator = context.coordinator] path in
      coordinator?.toggleSelection(at: path)
    }
    collection.enterSelection = { [weak coordinator = context.coordinator] path in coordinator?.beginSelection(at: path) }
    collection.preview = { [weak coordinator = context.coordinator] path in
      guard let coordinator, let id = coordinator.identifier(at: path.item) else { return }
      coordinator.parent.preview(id)
    }
    let press = NSPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
    press.minimumPressDuration = 0.4
    press.delaysPrimaryMouseButtonEvents = true
    press.isEnabled = !readOnly && !selecting && !MacLibraryDensity.isDense(columns)
    collection.addGestureRecognizer(press)
    let magnify = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.magnify(_:)))
    if !embeddedPreview { collection.addGestureRecognizer(magnify) }
    let scroll = LibraryScrollView()
    scroll.hasVerticalScroller = !embeddedPreview
    scroll.embeddedPreview = embeddedPreview
    scroll.drawsBackground = false
    scroll.documentView = collection
    if initialLoadingIndicator {
      let indicator = NSProgressIndicator()
      indicator.style = .spinning; indicator.controlSize = .small
      indicator.startAnimation(nil)
      let label = NSTextField(labelWithString: NSLocalizedString("folders_counting", comment: ""))
      let loading = NSStackView(views: [indicator, label])
      loading.orientation = .vertical; loading.alignment = .centerX; loading.spacing = DuckSpacing.small
      loading.translatesAutoresizingMaskIntoConstraints = false
      scroll.addSubview(loading)
      NSLayoutConstraint.activate([
        loading.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
        loading.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
      ])
      context.coordinator.initialLoadingView = loading
    }
    scroll.contentView.postsBoundsChangedNotifications = true
    context.coordinator.collection = collection
    context.coordinator.bindPreviewSource()
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
    if !active { c.parent.source.stopPreheating() }
    c.parent = self
    c.bindPreviewSource()
    guard let collection = c.collection,
      let layout = collection.collectionViewLayout as? LibraryTimelineLayout
    else { return }
    collection.isSelectable = !readOnly
    for press in collection.gestureRecognizers.compactMap({ $0 as? NSPressGestureRecognizer }) {
      // A recognizer with no available action must not consume a photo click.
      press.isEnabled = !readOnly && !selecting && !MacLibraryDensity.isDense(columns)
    }
    scroll.hasVerticalScroller = !embeddedPreview
    (scroll as? LibraryScrollView)?.embeddedPreview = embeddedPreview
    // Level layers stay mounted and cross-fade in AppKit: a SwiftUI opacity swap
    // cut between levels and showed a blank page on first use.
    scroll.setAccessibilityHidden(navigation.level != .all)
    MacLevelFade.apply(scroll,layer: .all,current: navigation.level)
    // The workspace owns compositing and hit testing for retained destinations.
    // A second, queued isHidden change would reveal the workspace before its
    // native collection, producing an empty frame on every return. Keep the
    // mounted viewport ready; only accessibility and active work change here.
    if c.appliedActive != active {
      c.appliedActive = active
      DispatchQueue.main.async { [weak collection, weak c] in
        guard let c, c.parent.active == active else { return }
        collection?.setAccessibilityHidden(!active)
        if active {
          collection?.layoutSubtreeIfNeeded()
          c.scrolled()
        }
      }
    }
    for path in collection.indexPathsForVisibleItems() {
      (collection.item(at: path) as? PhotoCell)?.setSelectionVisible(selecting)
    }
    let resolvedColumns = sharedSize?.resolve(columns, width: scroll.contentSize.width,
      stops: source.zoomStops, active: active && navigation.level == .all) ?? columns
    c.viewportResized(layout: layout)
    if !c.magnifying { c.syncDensity(columns: resolvedColumns, layout: layout) }
    c.applyItems(scroll: scroll, layout: layout)
    if source.preservesViewportDuringLiveUpdates { c.updateFooter() }
    if active, layout.isDense, source.fetchResult.opening, let source = source as? any MacDenseGridSource {
      Task { await source.completeOpening() }
    }
    if c.networkAllowed != networkPolicy.allowed {
      c.networkAllowed = networkPolicy.allowed; c.refreshVisibleImages()
    }
    if c.contentGeneration != source.contentRevision {
      c.contentGeneration = source.contentRevision
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
      if navigation.level == .all { c.scrollToNewest() }
    }
    if c.originalAspect != navigation.originalAspect {
      c.originalAspect = navigation.originalAspect; c.refreshVisibleImages()
    }
    if c.appliedSelection != source.selection {
      c.applyingSelection = true
      collection.selectionIndexPaths = c.selectedPaths()
      c.appliedSelection = source.selection
      c.applyingSelection = false
    }
    c.updateFooter()
    if prefillsTables { source.prefill() }
  }
  static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
    coordinator.stopLayoutAnimation()
    coordinator.removeZoomStage()
    coordinator.rememberScroll()
    coordinator.refresh.cancel()
    coordinator.parent.source.stopPreheating()
    if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
    if let observer = coordinator.frameObserver { NotificationCenter.default.removeObserver(observer) }
    coordinator.parent.source.previewPoster = nil
    coordinator.parent.source.previewFrame = nil
    coordinator.parent.navigation.cellFrame = nil
  }
  @MainActor final class Coordinator: NSObject, NSCollectionViewDelegate
  {
    var networkAllowed = false
    var originalAspect = false
    var focusRevision = 0
    var magnifying = false
    var appliedActive: Bool?
    private var appliedColumns: Int?
    private var lastViewportWidth: CGFloat?
    private var resizingViewport = false
    /// True while the viewport rests at the newest edge (the bottom). Older pages
    /// and reloads then keep it there instead of preserving a stale item.
    var pinnedToNewest = true
    var newestRevision = 0
    /// Returns to the newest edge, easing instead of jumping.
    func scrollToNewest() {
      guard let collection, let scroll = collection.enclosingScrollView else { return }
      prepareForScrolling()
      (scroll as? LibraryScrollView)?.endScrollInput()
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
    var denseCanvas: MacDenseCanvas? {
      didSet { denseCanvas?.onDisplay = { [weak self] in self?.scheduleNativeAdoption() } }
    }
    /// Empty slots before the first photo in the settled grid, so a focal photo
    /// keeps its column when the density changes (as on iPhone).
    var leading = 0
    private var gestureLeading: [Int: Int] = [:]
    private var settleLeading = 0
    private var pinsShortGrid = false
    /// Ordinary faces use their final row composition throughout the transition.
    /// The stage moves the focal photo to that slot without an adoption-time reflow.
    private func phase(for columns: Int) -> Int {
      if !MacLibraryDensity.isDense(columns) || pinsShortGrid { return 0 }
      if let cached = gestureLeading[columns] { return cached }
      if keepsNewest {
        let value = (columns - count % columns) % columns
        gestureLeading[columns] = value
        return value
      }
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
      canvas.pipeline = denseSource?.thumbnails
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
    /// Input belongs to the visible stage until the native collection adopts it.
    /// Reusing the old native density here would replay the same overview step.
    func activateOverview(at point: CGPoint) -> Bool {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return false }
      if let stage = zoomStage {
        guard MacLibraryDensity.isDense(stage.shown) else {
          prepareForScrolling()
          return false
        }
        let location = stage.convert(point, from: collection)
        rebuildStops(layout)
        guard let target = overviewTarget(from: stage.shown) else { return true }
        stage.freeze()
        guard let hit = stage.overviewPhoto(at: location), identifier(at: hit.index) != nil else {
          // A not-yet-materialized tile cannot hand input to the covered grid.
          // Resume this face rather than leaving its animation frozen.
          forcedAnchor = false
          animateLayout(columns: stage.shown)
          return true
        }
        stage.reanchor(to: location)
        anchor = stage.anchor; anchorFraction = stage.fraction.y; anchorFractionX = stage.fraction.x
        anchorY = stage.focus.y
        keepsTop = false; keepsNewest = false; pinsShortGrid = false
        forcedAnchor = false
        parent.resize(target)
        // animateLayout retains this stage and its shown photo pose. It must
        // not reconstruct an entry face from the still-hidden native geometry.
        animateLayout(columns: target)
        return true
      }
      guard let index = denseIndex(at: point) else { return false }
      drillDown(from: index)
      return true
    }
    private func overviewTarget(from columns: Int) -> Int? {
      let overviews = columnStops.filter(MacLibraryDensity.isDense)
      guard let ordinary = columnStops.last(where: { !MacLibraryDensity.isDense($0) }),
        let index = overviews.indices.min(by: { abs(overviews[$0] - columns) < abs(overviews[$1] - columns) }) else { return nil }
      return index == 0 ? ordinary : overviews[index - 1]
    }
    /// A click on a settled overview steps toward the grid around that photo.
    func drillDown(from index: Int) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        let scroll = collection.enclosingScrollView else { return }
      guard layout.isDense, identifier(at: index) != nil else { return }
      // Resolve from this viewport's current stops, including a resized overview.
      // A click must not depend on a previous pinch having initialized the stops.
      rebuildStops(layout)
      guard let target = overviewTarget(from: layout.columns) else { return }
      let frame = layout.frame(at: index)
      anchor = index; anchorFraction = 0.5; anchorFractionX = 0.5
      anchorY = frame.midY - scroll.contentView.bounds.minY
      keepsTop = false
      parent.resize(target)
      forcedAnchor = true
      animateLayout(columns: target)
    }
    var forcedAnchor = false
    /// Item to reveal once layout is current. A visible return target retains
    /// its position; an offscreen target needs only the nearest edge revealed.
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
      guard !clip.bounds.contains(frame) else { return }
      let maximum = max(0, settledContentHeight - clip.bounds.height)
      let y = frame.minY < clip.bounds.minY ? frame.minY : frame.maxY - clip.bounds.height
      clip.scroll(to: CGPoint(x: 0, y: min(maximum, max(0, y))))
      scroll.reflectScrolledClipView(clip)
      pinnedToNewest = false
      rememberScroll()
    }
    var animationTarget: (LibraryViewMode, CGFloat)?
    private var layoutGeneration = 0
    private struct NativeAdoption {
      let ownership: Int
      let membership: Int
      let stage: MacGridZoomStage?
    }
    private var pendingAdoption: NativeAdoption?
    private var adoptionCheckGeneration: Int?
    private var checkingAdoption = false
    private var anchor: Int?
    private var anchorFraction: CGFloat = 0
    private var anchorY: CGFloat = 0
    private var keepsTop = false
    private var keepsNewest = false
    var parent: MacMediaGrid
    weak var initialLoadingView: NSView?
    weak var collection: NSCollectionView? {
      didSet {
        (collection as? LibraryCollectionView)?.didLayout = { [weak self] in self?.scheduleNativeAdoption() }
        if let scroll = collection?.enclosingScrollView as? LibraryScrollView {
          scroll.willScroll = { [weak self] in self?.prepareForScrolling() }
          scroll.didScroll = { [weak self] in self?.scrolledFromInput() }
          if parent.source.preservesViewportDuringLiveUpdates {
            scroll.userScrollEnded = { [weak self, weak scroll] in
              guard let self, let scroll, let layout = self.collection?.collectionViewLayout as? LibraryTimelineLayout else { return }
              self.applyItems(scroll: scroll, layout: layout)
            }
          }
          scroll.viewportReleased = { [weak self] in self?.sourceViewportReleased() }
        }
      }
    }
    var observer: NSObjectProtocol?
    var frameObserver: NSObjectProtocol?
    let refresh = LibraryRefreshScheduler()
    var restoring = false
    var applyingSelection = false
    var appliedSelection: Set<String>?
    var count = 0
    var generation = -1
    var contextID: String?
    private var measuredHeaderWidth: CGFloat = 0
    private var appliedLiveSource: (any MacGridSource)?
    var ids: [String] = []
    var positions: [String: Int] = [:]
    var dataSource: NSCollectionViewDiffableDataSource<Int, String>?
    private var membershipCover: NSImageView?
    private func coverMembership(in scroll: NSScrollView) {
      membershipCover?.removeFromSuperview(); membershipCover = nil
      guard !reducedMotion, let bitmap = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else { return }
      scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
      let image = NSImage(size: scroll.bounds.size); image.addRepresentation(bitmap)
      let cover = NSImageView(frame: scroll.bounds); cover.image = image
      cover.imageScaling = .scaleAxesIndependently
      cover.autoresizingMask = [.width, .height]
      scroll.addSubview(cover); membershipCover = cover
    }
    private func revealMembership() {
      guard let cover = membershipCover else { return }
      membershipCover = nil
      NSAnimationContext.runAnimationGroup { context in
        context.duration = reducedMotion ? 0 : 0.2
        context.timingFunction = CAMediaTimingFunction(name: .linear)
        cover.animator().alphaValue = 0
      } completionHandler: { cover.removeFromSuperview() }
    }
    var preparationRevision = ""
    var contentGeneration = ""
    var statusRevision: Int64 = -2
    var receiverID: String?
    var visibleIdentifiers: [IndexPath: String] = [:]
    init(_ parent: MacMediaGrid) { self.parent = parent }
    func installDataSource(_ collection: NSCollectionView) {
      for kind in LibraryTimelineLayout.headerKinds {
        collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: kind, withIdentifier: .init("timeline"))
      }
      let data = NSCollectionViewDiffableDataSource<Int, String>(collectionView: collection) { [weak self] view, path, id in
        let cell = view.makeItem(withIdentifier: .init("photo"), for: path) as! PhotoCell
        self?.configure(cell, id: id)
        return cell
      }
      data.supplementaryViewProvider = { [weak self] view, kind, path in
        self?.makeHeader(view, kind: kind, at: path)
      }
      dataSource = data
    }
    private var awaitingOpeningExpansion = false
    private var showingOpening = false
    func applyItems(scroll: NSScrollView, layout: LibraryTimelineLayout) {
      // Never adopt old rows under a new filter identity.
      guard parent.source.membershipReady, width() > 120 else {
        if !parent.source.membershipReady { scrolled() }
        return
      }
      measuredHeaderWidth = width()
      let result = parent.source.fetchResult
      let next = result.identifiers
      let changedContext = contextID != parent.source.contextID
      let liveUpdates = parent.source.preservesViewportDuringLiveUpdates
      let nativeScroll = scroll as? LibraryScrollView
      if liveUpdates, !changedContext, nativeScroll?.isUserScrolling == true, ids != next { return }
      let scrollRevision = nativeScroll?.userScrollRevision
      let expandingOpening = showingOpening && !result.opening && !changedContext
      if expandingOpening, zoomStage != nil {
        awaitingOpeningExpansion = true
        return
      }
      awaitingOpeningExpansion = false
      showingOpening = result.opening
      guard ids != next || changedContext else {
        let heights = parent.source.headerHeights(width: width())
        let folders = parent.source.folderHeaders(width: width())
        if layout.groups != parent.source.groups || layout.flowHeaders != parent.source.flowHeaders || layout.headerHeights != heights
          || layout.folders != folders || layout.dateIDs != parent.source.dateIDs {
          layout.groups = parent.source.groups; layout.flowHeaders = parent.source.flowHeaders; layout.headerHeights = heights
          layout.folders = folders; layout.dateIDs = parent.source.dateIDs
          layout.revision += 1; layout.invalidateLayout()
          collection?.layoutSubtreeIfNeeded()
          if liveUpdates { refreshVisibleHeaders(); scrolled() }
        }
        if liveUpdates { appliedLiveSource = parent.source }
        else {
          refreshVisibleHeaders(); refreshVisibleImages(); scrolled()
        }
        return
      }
      if changedContext && contextID != nil { coverMembership(in: scroll) }
      if !changedContext { rememberScroll() }
      stopLayoutAnimation(); removeZoomStage(); magnifying = false
      let first = contextID == nil
      let retained = parent.source.scroll
      let offset = retained.offset
      var anchor = retained.anchor, inset = retained.inset
      if changedContext { pinnedToNewest = parent.source.startsAtEnd && anchor == nil }
      let nextPositions = result.positions ?? Dictionary(uniqueKeysWithValues: next.enumerated().map { ($0.element, $0.offset) })
      if liveUpdates, !changedContext, !pinnedToNewest, let previous = appliedLiveSource,
        let retainedID = anchor, nextPositions[retainedID] == nil || previous.date(retainedID) != parent.source.date(retainedID) {
        // A status change can move the anchor record to the newest end. Keep
        // another visible row in place instead of following that record.
        anchor = nil
        if let span = visibleRange(),
          let index = (span.first...span.last).first(where: {
            let id = ids[$0]
            return nextPositions[id] != nil && previous.date(id) == parent.source.date(id)
          }) {
          anchor = ids[index]
          inset = scroll.contentView.bounds.minY - layout.frame(at: index).minY
        }
      }
      appliedLiveSource = liveUpdates ? parent.source : nil
      contextID = parent.source.contextID
      var animates = false
      if !liveUpdates, parent.active, !first, !changedContext, !expandingOpening, !reducedMotion, abs(ids.count - next.count) <= 64 {
        let removals = ids.lazy.filter { nextPositions[$0] == nil }.prefix(65).count
        let insertions = next.lazy.filter { self.positions[$0] == nil }.prefix(65 - min(removals, 65)).count
        animates = (1...64).contains(removals + insertions)
      }
      let previousIDs = ids
      ids = next; positions = nextPositions
      (collection as? LibraryCollectionView)?.remapSelectionAnchors(from: previousIDs, to: positions, reset: changedContext)
      count = next.count; generation += 1; appliedSelection = nil
      layout.revision += 1
      layout.groups = parent.source.groups
      layout.flowHeaders = parent.source.flowHeaders
      layout.headerHeights = parent.source.headerHeights(width: width())
      layout.folders = parent.source.folderHeaders(width: width()); layout.dateIDs = parent.source.dateIDs
      restoring = true; applyingSelection = true
      var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
      snapshot.appendSections([0]); snapshot.appendItems(next, toSection: 0)
      let expected = generation
      dataSource?.apply(snapshot, animatingDifferences: animates) { [weak self, weak scroll] in
        guard let self, self.generation == expected, let scroll, let collection = self.collection else { return }
        collection.needsLayout = true; collection.layoutSubtreeIfNeeded(); self.ensureDocumentHeight()
        let maximum = max(0, self.settledContentHeight - scroll.contentView.bounds.height)
        var target = offset
        if self.pinnedToNewest { target.y = maximum }
        else if let index = self.displayIndex(of: anchor) { target.y = layout.frame(at: index).minY + inset }
        target.y = min(maximum, max(0, target.y))
        if !liveUpdates || changedContext || (scroll as? LibraryScrollView)?.userScrollRevision == scrollRevision {
          scroll.contentView.scroll(to: target); scroll.reflectScrolledClipView(scroll.contentView)
        }
        self.restoring = false; self.applyingSelection = false
        self.applyPendingFocus(); self.scrolled()
        self.revealMembership()
        self.initialLoadingView?.removeFromSuperview()
      }
    }
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
    private var settleColumns = 0
    private var finalOffset: CGFloat = 0
    /// Row count and newest-edge state when the settle's offset was chosen. The
    /// whole library can finish loading mid-settle; the offset is then re-derived
    /// instead of applying one computed for the shorter document.
    private var settleCount = 0
    private var settleAtNewest = false
    private var startOffset: CGFloat = 0
    private var reducedMotion: Bool {
      parent.reducedMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    func stopLayoutAnimation() {
      layoutGeneration &+= 1
      pendingAdoption = nil; adoptionCheckGeneration = nil
      (collection?.enclosingScrollView as? LibraryScrollView)?.endScrollInput()
      zoomStage?.freeze(); settle = nil; animationTarget = nil; restoring = false
    }
    /// Scrolling takes ownership before AppKit moves the clip view. Commit the
    /// requested density and its anchor, retaining displayed pixels, so the
    /// viewport never scrolls beneath a stage while native browsing is hidden.
    func prepareForScrolling() {
      guard let stage = zoomStage, let collection else { return }
      CATransaction.begin(); CATransaction.setDisableActions(true)
      defer { CATransaction.commit() }
      stage.freeze()
      magnifying = false; pinch = nil; direction = nil; boundary = nil; samples.removeAll()
      if animationTarget != nil {
        completeStage(forScrolling: true)
      } else if pendingAdoption != nil {
        collection.needsLayout = true; collection.layoutSubtreeIfNeeded()
        updateDense(); retainStagePixels()
        stopLayoutAnimation(); removeZoomStage()
      } else {
        // A wheel can also take over direct magnification before release.
        let columns = stage.shown
        parent.resize(columns)
        finishStage(columns: columns, size: itemSize(forColumns: columns), cancelled: false, animated: false)
      }
    }
    private func scrolledFromInput() {
      if let scroll = collection?.enclosingScrollView,
        !parent.source.preservesViewportDuringLiveUpdates
          || abs(scroll.contentView.bounds.minY - parent.source.scroll.offset.y) > 0.5 {
        pinnedToNewest = scroll.contentView.bounds.maxY >= settledContentHeight - 2
      }
      // AppKit may apply a wheel after scrollWheel returns. Populate its actual
      // new bounds synchronously, before that native movement can be displayed.
      scrolled()
    }
    private func sourceViewportReleased() {
      guard let collection, let scroll = collection.enclosingScrollView else { return }
      // Discard layout requests made while the viewer owned the source. Its
      // actual retained edge, not a deferred bottom restore, resumes browsing.
      pinnedToNewest = scroll.contentView.bounds.maxY >= settledContentHeight - 2
      rememberScroll()
    }
    /// A layout pass changed the document height. A viewport resting at the
    /// newest edge stays there until the person scrolls away.
    func contentResized() {
      defer { scrolled() }
      if let layout = collection?.collectionViewLayout as? LibraryTimelineLayout {
        viewportResized(layout: layout)
      }
      // The first update can run before the grid has a width (a sheet's first
      // pass), when the requested column count cannot be applied yet.
      if appliedColumns == nil, width() > 120, let layout = collection?.collectionViewLayout as? LibraryTimelineLayout {
        let columns = parent.sharedSize?.resolve(parent.columns, width: width(),
          stops: parent.source.zoomStops, active: parent.active && parent.navigation.level == .all) ?? parent.columns
        syncDensity(columns: columns, layout: layout)
      }
      // A recreated page can receive its first update before AppKit supplies
      // the viewport width. Adopt membership and header metrics only at the
      // real width, and refresh them whenever that native width changes.
      if width() > 120, let collection, let scroll = collection.enclosingScrollView,
        let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        contextID == nil || measuredHeaderWidth != width() {
        applyItems(scroll: scroll, layout: layout)
      }
      guard pinnedToNewest, zoomStage == nil, !restoring, let collection, let scroll = collection.enclosingScrollView,
        (scroll as? LibraryScrollView)?.isUserScrolling != true else { return }
      let clip = scroll.contentView
      var proposed = clip.bounds
      proposed.origin = CGPoint(x: 0, y: max(0, settledContentHeight - proposed.height))
      // AppKit owns the document frame here. Setting it in response to its
      // own resize notification can trigger another resize and scroll.
      let target = clip.constrainBoundsRect(proposed).origin
      guard target.y > clip.bounds.minY + 2 else { return }
      clip.scroll(to: target)
      scroll.reflectScrolledClipView(clip)
    }
    /// Window resizing changes geometry, not the person's zoom preference.
    /// Stop a running zoom before rebuilding its now-stale viewport geometry.
    func viewportResized(layout: LibraryTimelineLayout) {
      let currentWidth = width()
      guard currentWidth > 120, !resizingViewport else { return }
      let previous = lastViewportWidth
      lastViewportWidth = currentWidth
      guard let previous, abs(previous - currentWidth) > 0.5,
        let collection, let scroll = collection.enclosingScrollView, let columns = appliedColumns else { return }
      resizingViewport = true
      defer { resizingViewport = false }
      let saved = parent.source.scroll
      let savedAnchor = saved.anchor, savedInset = saved.inset
      let atNewest = pinnedToNewest
      if zoomStage != nil {
        stopLayoutAnimation(); removeZoomStage(); magnifying = false
      }
      layout.requestedColumns = columns
      layout.target = itemSize(forColumns: columns)
      layout.leadingSlots = leading
      // The geometry cache is keyed by the previous viewport until prepare
      // observes the new width. Size the document first, then invalidate that
      // cache before adopting and using a frame to restore the anchor.
      ensureDocumentHeight()
      layout.prepare()
      layout.adopt(mode: .all, columns: columns)
      collection.needsLayout = true
      collection.layoutSubtreeIfNeeded()
      ensureDocumentHeight()
      let offset: CGFloat
      if atNewest { offset = max(0, settledContentHeight - viewportHeight()) }
      else if let index = displayIndex(of: savedAnchor) { offset = layout.frame(at: index).minY + savedInset }
      else { offset = scroll.contentView.bounds.minY }
      placeOffset(offset)
    }
    func removeZoomStage() {
      layoutGeneration &+= 1
      pendingAdoption = nil; adoptionCheckGeneration = nil
      let stage = zoomStage
      zoomStage = nil
      CATransaction.begin(); CATransaction.setDisableActions(true)
      stage?.detachFooter()
      updateFooter()
      stage?.stop(); stage?.removeFromSuperview()
      collection?.alphaValue = 1
      CATransaction.commit()
      if awaitingOpeningExpansion {
        awaitingOpeningExpansion = false
        DispatchQueue.main.async { [weak self] in
          guard let self, let collection = self.collection, let scroll = collection.enclosingScrollView,
            let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
          self.applyItems(scroll: scroll, layout: layout)
        }
      }
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
      return LibraryTimelineGeometry.cellSide(width: width(), columns: columns, inset: inset, gap: gap,
        fillsWidth: MacLibraryDensity.isDense(columns)) + gap
    }
    private func contentHeight(_ columns: Int,leading: Int? = nil) -> CGFloat {
      if parent.embeddedPreview { return viewportHeight() }
      if !parent.source.groups.isEmpty {
        return MacGridGeometry.make(count: count, groups: parent.source.groups, columns: columns, width: width(), headerHeights: parent.source.headerHeights(width: width()), folders: parent.source.folderHeaders(width: width()), dateIDs: parent.source.dateIDs, flowHeaders: parent.source.flowHeaders).height + footerHeight
      }
      let lead = leading ?? self.leading
      let pitch = naturalPitch(columns), slots = count+lead, rows = (slots+columns-1)/columns
      let side = pitch-gap(columns)
      let last = slots%columns == 0 ? pitch : side
      return 4+CGFloat(max(0,rows-1))*pitch+last+16+footerHeight
    }
    private var footerHeight: CGFloat = MacGridFooter.minimumHeight
    private var footerTextHeight: CGFloat = 20
    private var footerWidth: CGFloat = 0
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
      let label = NSTextField(wrappingLabelWithString: "")
      label.font = .preferredFont(forTextStyle: .caption1); label.textColor = .secondaryLabelColor
      label.alignment = .center; label.maximumNumberOfLines = 0
      return label
    }()
    private var footerKey = ""
    private var liveFooterText: String?
    private var liveFooterNotes: [String] = []
    // Items are presented oldest first (newest at the bottom, as in Photos). The
    // library model indexes newest first, so every display index is mirrored
    // against the number of items the collection currently holds.
    private var denseSource: (any MacDenseGridSource)? { parent.source as? any MacDenseGridSource }
    func asset(at item: Int) -> PHAsset? { identifier(at: item).flatMap { denseSource?.asset($0) } }
    func date(at item: Int) -> Date? { identifier(at: item).flatMap { parent.source.date($0) } }
    func fact(at item: Int) -> MacThumbnailTables.Fact? { identifier(at: item).flatMap { denseSource?.fact($0) } }
    func identifier(at item: Int) -> String? { ids.indices.contains(item) ? ids[item] : nil }
    func bindPreviewSource() {
      parent.source.previewPoster = { [weak self] id in
        self?.flightCell { $0.assetID == id || $0.presentationID == id }?.image
      }
      parent.source.previewFrame = { [weak self] id in
        self?.flightCell { $0.assetID == id || $0.presentationID == id }?.rect
      }
    }
    /// A visible cell as a flight endpoint, in window coordinates.
    func flightCell(_ match: (PhotoCell) -> Bool) -> MacCoverFlightSource? {
      guard let collection, let scroll = collection.enclosingScrollView,
        let cell = collection.visibleItems().compactMap({ $0 as? PhotoCell }).first(where: match),
        let id = cell.assetID, let window = cell.view.window else { return nil }
      let frame = cell.photoRect
      guard cell.view.convert(frame, to: scroll).intersects(scroll.bounds) else { return nil }
      // A summary's small viewport is a source slot, not the transition canvas.
      // Keep flights inside the enclosing page, including on the return trip.
      let pageScroll = parent.embeddedPreview ? scroll.superview?.enclosingScrollView : nil
      let clip = MacCoverFlightSource.clip(of: pageScroll ?? scroll)
      return MacCoverFlightSource(rect: cell.view.convert(frame, to: nil), image: cell.displayedImage,
        radius: cell.photoCornerRadius, assetID: id, clip: clip, window: window,
        sourceViewport: scroll as? LibraryScrollView, fullAspectRatio: cell.fullAspectRatio)
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
      identifier.flatMap { positions[$0] }
    }
    func selectedPaths() -> Set<IndexPath> {
      Set(parent.source.selection.compactMap { displayIndex(of: $0) }.map { IndexPath(item: $0, section: 0) })
    }
    /// One collection summary stays in document flow and travels with the same
    /// native label during zoom. Counts never occupy the window subtitle.
    func updateFooter() {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      if parent.embeddedPreview { layout.footerHeight = 0; footer.isHidden = true; return }
      let liveUpdates = parent.source.preservesViewportDuringLiveUpdates
      let key = liveUpdates ? "" : "\(ObjectIdentifier(parent.source))|\(parent.source.contextID)|\(parent.source.contentRevision)|\(count)"
      let width = max(1, collection.bounds.width)
      let total = liveUpdates ? parent.source.footer : nil
      let notes = liveUpdates ? parent.source.footerNotes : []
      let contentChanged = liveUpdates ? total != liveFooterText || notes != liveFooterNotes : key != footerKey
      if contentChanged || abs(footerWidth - width) > 0.5 {
        footerKey = key; footerWidth = width
        liveFooterText = total; liveFooterNotes = notes
        let text = MacGridFooter.attributed(total: total ?? parent.source.footer, notes: liveUpdates ? notes : parent.source.footerNotes)
        footer.attributedStringValue = text
        footerTextHeight = MacGridFooter.textHeight(text, width: width)
        footerHeight = MacGridFooter.height(text, width: width)
      }
      if layout.footerHeight != footerHeight {
        layout.footerHeight = footerHeight; layout.invalidateLayout()
      }
      footer.isHidden = count == 0 || footer.stringValue.isEmpty
      footer.frame.size.height = footerTextHeight
      // Preserve the existing stage's geometry and clipping owner.
      if zoomStage?.ownsFooter(footer) == true { return }
      if footer.superview !== collection { collection.addSubview(footer) }
      let height = layout.collectionViewContentSize.height
      let frame = CGRect(x: 0, y: max(0, height - footerHeight + MacGridFooter.topInset),
        width: width, height: footerTextHeight)
      if footer.frame != frame { footer.frame = frame }
    }
    /// Item size whose column count is exactly `columns`.
    private func itemSize(forColumns columns: Int) -> CGFloat {
      max(4,(width()-inset(columns)*2)/CGFloat(columns)-gap(columns)-0.01)
    }
    /// Applies the requested column count from the toolbar or a restored state.
    func syncDensity(columns requested: Int, layout: LibraryTimelineLayout) {
      guard width() > 120 else { return }
      if zoomStage != nil {
        // Native toolbar updates must reach the running stage too. Waiting for
        // adoption discards rapid input while the toolbar already shows it.
        if settleColumns != requested {
          appliedColumns = requested
          animateLayout(columns: requested)
        }
        return
      }
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
      let usable = parent.source.zoomStops.filter { naturalPitch($0) >= 8 }
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
      if !parent.source.groups.isEmpty {
        let frames = MacGridGeometry.make(count: count, groups: parent.source.groups, columns: columns, width: width(), headerHeights: parent.source.headerHeights(width: width()), folders: parent.source.folderHeaders(width: width()), dateIDs: parent.source.dateIDs, flowHeaders: parent.source.flowHeaders).items
        if let anchor, frames.indices.contains(anchor) {
          let frame = frames[anchor]
          return CGPoint(x: frame.minX + anchorFractionX * frame.width, y: frame.minY + anchorFraction * frame.height)
        }
      }
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
        columns: layout.columns,pitch: frame.width+gap(layout.columns),focus: focus)
      stage.frame = scroll.contentView.frame; stage.autoresizingMask = [.width,.height]
      stage.densePinTop = scroll.contentInsets.top + 6
      // The stage occupies the clip view's frame and starts at bounds zero.
      // Express the native document pin line in those same viewport coordinates.
      stage.groupedPinTop = collection.visibleRect.minY + scroll.contentInsets.top - scroll.contentView.bounds.minY
      stage.referenceSide = { [weak self] columns in (self?.naturalPitch(columns) ?? 3)-(self?.gap(columns) ?? 2) }
      stage.denseAsset = { [weak self] index in self?.asset(at: index) }
      stage.denseFact = { [weak self] index in self?.fact(at: index) }
      stage.thumbnails = denseSource?.thumbnails
      var pixels = denseCanvas?.displayedImages ?? [:]
      for item in collection.visibleItems().compactMap({ $0 as? PhotoCell }) {
        if let index = collection.indexPath(for: item)?.item, let image = item.displayedImage { pixels[index] = image }
      }
      stage.seedImages = pixels
      if !parent.source.groups.isEmpty {
        let count = count, groups = parent.source.groups, width = width()
        let heights = parent.source.headerHeights(width: width)
        let folders = parent.source.folderHeaders(width: width), dateIDs = parent.source.dateIDs
        let flowHeaders = parent.source.flowHeaders
        stage.groupedIdentity = { [source = parent.source] index in source.folderIdentity(at: index) }
        stage.groupedRevision = parent.source.contentRevision
        stage.groupedIntroduction = { [source = parent.source] index in source.introduction(at: index) }
        // All faces and the shared captions read the same immutable snapshot.
        // Rebuilding the full item geometry per caption frame defeats paging.
        var geometries: [Int: LibraryTimelineGeometry] = [:]
        stage.groupedGeometry = { columns in
          if let cached = geometries[columns] { return cached }
          let geometry = MacGridGeometry.make(count: count, groups: groups, columns: columns, width: width, headerHeights: heights, folders: folders, dateIDs: dateIDs, flowHeaders: flowHeaders)
          geometries[columns] = geometry
          return geometry
        }
      }
      stage.makeTile = { [weak self] index, side in
        guard let self, let id = self.identifier(at: index) else { return NSView() }
        return self.parent.source.zoomTile(id, side: side, scale: collection.window?.backingScaleFactor ?? 2,
          originalAspect: self.parent.navigation.originalAspect)
      }
      stage.releaseTile = { ($0 as? MacZoomMediaTile)?.cancel(); ($0 as? MacSourceZoomTile)?.cancel() }
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
      if !footer.stringValue.isEmpty, !footer.isHidden {
        stage.attachFooter(footer, columns: columnStops) { [weak self, weak stage] columns in
          guard let self else { return nil }
          let leading = self.phase(for: columns)
          let point = stage?.contentFocus(columns: columns)
            ?? self.anchorContentPoint(columns: columns, leading: leading)
          let y: CGFloat
          if let geometry = stage?.groupedGeometry?(columns) { y = geometry.height + MacGridFooter.topInset }
          else { y = self.contentHeight(columns, leading: leading) - self.footerHeight + MacGridFooter.topInset }
          return (point, y, leading)
        }
      }
      stage.render()
      startOffset = scroll.contentView.bounds.minY
      collection.alphaValue = 0.001
    }
    private func captureAnchor(_ point: CGPoint? = nil) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout, let scroll = collection.enclosingScrollView else { return }
      let largest = parent.source.zoomStops.filter { !MacLibraryDensity.isDense($0) }.min() ?? 3
      pinsShortGrid = parent.source.groups.isEmpty && count > 0
        && contentHeight(largest, leading: 0) <= viewportHeight()
      keepsNewest = point == nil && pinnedToNewest && !pinsShortGrid
      if pinsShortGrid {
        anchor = 0; anchorFraction = 0; anchorFractionX = 0
        anchorY = layout.frame(at: 0).minY - scroll.contentView.bounds.minY
        keepsTop = true
        return
      }
      if keepsNewest, count > 0 {
        // Retaining the newest edge uses the last photo's real bottom as the
        // shared focus. Every density then keeps its last row above the totals.
        anchor = count - 1; anchorFraction = 1; anchorFractionX = 0.5
        anchorY = layout.frame(at: count - 1).maxY - scroll.contentView.bounds.minY
        keepsTop = false
        return
      }
      let wasAtTop = point == nil && !pinnedToNewest && scroll.contentView.bounds.minY <= 1
      if wasAtTop, count > 0 {
        // A toolbar zoom that retains the top edge must use that same edge as
        // its photo anchor. A middle-row anchor separates the outgoing and
        // incoming first rows beneath a stationary section caption.
        anchor = 0; anchorFraction = 0; anchorFractionX = 0
        anchorY = layout.frame(at: 0).minY - scroll.contentView.bounds.minY
        keepsTop = true
        return
      }
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
        // A toolbar anchor can land in the blank area below a short grid.
        // Its screen point must use the same clamped fraction as the stage.
        anchorY = frame.minY + anchorFraction * frame.height - scroll.contentView.bounds.minY
      }
      keepsTop = wasAtTop
    }
    private func placeOffset(_ offset: CGFloat) {
      guard let collection, let scroll = collection.enclosingScrollView else { return }
      (scroll as? LibraryScrollView)?.endScrollInput()
      collection.needsLayout = true; collection.layoutSubtreeIfNeeded()
      let limit = max(0,(collection.collectionViewLayout?.collectionViewContentSize.height ?? 0)-scroll.contentView.bounds.height)
      scroll.contentView.scroll(to: CGPoint(x: 0,y: min(limit,max(0,offset)))); scroll.reflectScrolledClipView(scroll.contentView)
      if let layout = collection.collectionViewLayout as? LibraryTimelineLayout {
        if !layout.groups.isEmpty {
          // Adoption first lays out at the previous scroll position. Requery
          // pinned captions at the final viewport before releasing its cover.
          let expected = layout.layoutAttributesForElements(in: collection.visibleRect)
          let context = NSCollectionViewLayoutInvalidationContext()
          for kind in LibraryTimelineLayout.headerKinds {
            var paths = Set(collection.indexPathsForVisibleSupplementaryElements(ofKind: kind))
            paths.formUnion(expected.compactMap { $0.representedElementKind == kind ? $0.indexPath : nil })
            if !paths.isEmpty { context.invalidateSupplementaryElements(ofKind: kind, at: paths) }
          }
          layout.invalidateLayout(with: context)
          collection.needsLayout = true
        }
        refreshVisibleHeaders()
      }
    }
    /// Slider and menu changes settle through the same stage as a pinch.
    func animateLayout(columns: Int) {
      guard collection != nil else { return }
      let retainsStage = zoomStage != nil && !forcedAnchor
      stopLayoutAnimation()
      if !retainsStage {
        removeZoomStage()
        if forcedAnchor { forcedAnchor = false; keepsNewest = false } else { captureAnchor() }
        if !reducedMotion { beginStage() }
      }
      restoring = true
      finishStage(columns: columns, size: itemSize(forColumns: columns), cancelled: false,
        velocity: retainsStage ? zoomStage?.frozenPitchVelocity : 0)
    }
    private func finishStage(columns: Int,size: CGFloat,cancelled: Bool,velocity: CGFloat? = nil, animated: Bool = true) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        let scroll = collection.enclosingScrollView else { return }
      animationTarget = (.all,size)
      settleColumns = columns
      settleLeading = MacLibraryDensity.isDense(columns) && zoomStage == nil ? leading : phase(for: columns)
      zoomStage?.ensureFace(columns, opacity: 0, leading: settleLeading)
      let natural = naturalPitch(columns)
      let focusInContent = zoomStage?.contentFocus(columns: columns)
        ?? anchorContentPoint(columns: columns, leading: settleLeading)
      let maximumOffset = max(0, contentHeight(columns, leading: settleLeading) - scroll.contentSize.height)
      let offset = cancelled ? startOffset : keepsTop ? 0 : keepsNewest ? maximumOffset : GridZoom.offset(
        focusInContent: focusInContent.y,screenFocus: zoomStage?.focus.y ?? anchorY,
        contentHeight: contentHeight(columns,leading: settleLeading),viewportHeight: scroll.contentSize.height)
      finalOffset = offset
      settleCount = count
      // A short document fits the viewport and reads as "at the top", so the
      // newest-edge state the zoom started from decides.
      settleAtNewest = maximumOffset <= 0.5 ? pinnedToNewest : !cancelled && (pinnedToNewest || (!keepsTop
        && offset >= maximumOffset - 2))
      guard let stage = zoomStage, !reducedMotion, animated else {
        completeStage(forScrolling: !animated); return
      }
      stage.show(columns,animated: true)
      stage.hurryBlend(within: GridZoom.releaseFadeDuration)
      let now = CACurrentMediaTime()
      settle = GridZoom.Settle(start: now,pitch: stage.pitch,focus: stage.focus,
        velocity: velocity ?? GridZoom.Settle.velocity(of: samples),targetPitch: natural,
        targetFocus: CGPoint(x: focusInContent.x,y: focusInContent.y-offset))
      if let settle { stage.settle(with: settle) { [weak self] in self?.completeStage() } }
    }
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
    private func completeStage(forScrolling: Bool = false) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        let target = animationTarget else { stopLayoutAnimation(); removeZoomStage(); return }
      settle = nil
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
      placeOffset(finalOffset)
      if forScrolling { collection.needsLayout = true; collection.layoutSubtreeIfNeeded() }
      refreshVisibleImages(); updateDense()
      pinnedToNewest = settledContentHeight <= viewportHeight() + 0.5 ? settleAtNewest
        : finalOffset >= max(0, settledContentHeight - viewportHeight()) - 2
      retainStagePixels()
      let stage = zoomStage
      collection.alphaValue = 1
      // Keep the final stage above the collection while AppKit materializes
      // the target viewport. Native layout/display events own the handoff.
      stopLayoutAnimation()
      if forScrolling {
        // Explicit input starts native browsing now, rather than allowing an
        // obsolete stage/adoption callback to restore its pre-scroll offset.
        removeZoomStage()
        scrolled()
        return
      }
      pendingAdoption = NativeAdoption(ownership: layoutGeneration, membership: generation, stage: stage)
      collection.needsLayout = true
      scheduleNativeAdoption()
      scrolled()
      scheduleBenchmark()
    }
    private func retainStagePixels() {
      guard let collection, let stage = zoomStage else { return }
      for item in collection.visibleItems().compactMap({ $0 as? PhotoCell }) {
        if let index = collection.indexPath(for: item)?.item,
          let image = stage.displayedImage(at: index) { item.retainDisplayedImage(image) }
      }
      if (collection.collectionViewLayout as? LibraryTimelineLayout)?.isDense == true, let canvas = denseCanvas {
        stage.retainDensePixels(in: canvas)
      }
    }
    /// A layout/display event requests one check. An incomplete native layout
    /// waits for its next real event rather than polling the run loop.
    func scheduleNativeAdoption() {
      guard !checkingAdoption, let pending = pendingAdoption,
        adoptionCheckGeneration != pending.ownership else { return }
      let ownership = pending.ownership
      adoptionCheckGeneration = ownership
      DispatchQueue.main.async { [weak self] in
        guard let self, self.adoptionCheckGeneration == ownership,
          self.pendingAdoption?.ownership == ownership, self.layoutGeneration == ownership else { return }
        self.adoptionCheckGeneration = nil
        self.adoptNativeIfReady()
      }
    }
    private func adoptNativeIfReady() {
      guard !checkingAdoption, let pending = pendingAdoption,
        pending.ownership == layoutGeneration, pending.membership == generation,
        pending.stage === zoomStage, let collection,
        let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      checkingAdoption = true
      defer { checkingAdoption = false }
      let viewport = collection.visibleRect
      let tolerance = 1 / (collection.window?.backingScaleFactor ?? 2)
      func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
          && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
      }
      func attached(_ view: NSView, frame: CGRect) -> Bool {
        view.isDescendant(of: collection) && !view.isHidden && view.alphaValue > 0
          && matches(view.convert(view.bounds, to: collection), frame)
      }
      var cells: [(Int, PhotoCell)] = []
      var captions: [NSView] = []
      if layout.isDense {
        guard let canvas = denseCanvas, attached(canvas, frame: collection.bounds) else { return }
      } else {
        for attributes in layout.layoutAttributesForElements(in: viewport)
          where attributes.frame.intersects(viewport) && attributes.frame.width > 0 && attributes.frame.height > 0 {
          if attributes.representedElementCategory == .item {
            guard let path = attributes.indexPath,
              let identifier = dataSource?.itemIdentifier(for: path),
              let cell = collection.item(at: path) as? PhotoCell,
              cell.presentationID == identifier, attached(cell.view, frame: attributes.frame) else { return }
            cells.append((path.item, cell))
          } else if attributes.representedElementCategory == .supplementaryView,
            let kind = attributes.representedElementKind, LibraryTimelineLayout.headerKinds.contains(kind) {
            guard let path = attributes.indexPath, let expected = layout.caption(kind: kind, at: path.item),
              let header = collection.supplementaryView(forElementKind: kind, at: path) as? MacGridSectionHeader,
              attached(header, frame: attributes.frame),
              header.isReady(for: expected, revision: parent.source.contentRevision) else { return }
            captions.append(header)
          }
        }
      }
      // Late materialized cells receive the same displayed pixels immediately.
      // Missing thumbnails never become a second loading gate.
      CATransaction.begin(); CATransaction.setDisableActions(true)
      defer { CATransaction.commit() }
      if layout.isDense, let canvas = denseCanvas {
        updateDense()
        if let stage = pending.stage, !stage.retainDensePixels(in: canvas) { return }
      } else {
        for caption in captions { caption.layoutSubtreeIfNeeded() }
        for (index, cell) in cells {
          cell.view.layoutSubtreeIfNeeded(); cell.viewDidLayout()
          if let image = pending.stage?.displayedImage(at: index) {
            cell.retainDisplayedImage(image)
            guard cell.hasPhotoContents else { return }
          }
        }
      }
      pendingAdoption = nil
      removeZoomStage()
      updateDense()
      updateVisibleDate()
      if layout.columns != parent.columns { syncDensity(columns: parent.columns, layout: layout) }
    }
    @objc func magnify(_ recognizer: NSMagnificationGestureRecognizer) {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout,
        let scroll = collection.enclosingScrollView else { return }
      switch recognizer.state {
      case .began:
        layoutGeneration &+= 1
        let interrupted = zoomStage != nil && (settle != nil || pendingAdoption != nil)
        pendingAdoption = nil; adoptionCheckGeneration = nil
        let location = recognizer.location(in: collection)
        let startColumns: Int
        if interrupted, let stage = zoomStage {
          // Take over the running settle in place: re-anchor on the new pointer
          // without moving any pixel, from the density the release had chosen.
          stage.freeze(); settle = nil; animationTarget = nil
          startColumns = settleColumns
          startOffset = finalOffset
          gestureLeading[settleColumns] = settleLeading
          if !pinsShortGrid {
            stage.reanchor(to: CGPoint(x: location.x,y: location.y-scroll.contentView.bounds.minY))
          }
          anchor = stage.anchor; anchorFraction = stage.fraction.y; anchorFractionX = stage.fraction.x
          anchorY = stage.focus.y
        } else {
          stopLayoutAnimation(); removeZoomStage()
          captureAnchor(location)
          startColumns = layout.columns
          beginStage()
        }
        keepsTop = pinsShortGrid
        keepsNewest = false
        magnifying = true; restoring = true
        guard let stage = zoomStage else { magnifying = false; restoring = false; return }
        samples = []
        pinch = GridZoom.Pinch(startDistance: 1,startPitch: stage.pitch,deadZone: 0)
        direction = GridZoom.Direction(startIndex: stopIndex(startColumns),startPitch: stage.pitch)
        let natural = naturalPitch(stage.shown)
        let shownLeading = gestureLeading[stage.shown] ?? leading
        let content = stage.contentFocus(columns: stage.shown)
          ?? anchorContentPoint(columns: stage.shown, leading: shownLeading)
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
        stage.trackBlend(at: now)
        stage.focus.y = pinsShortGrid ? 4 : boundary.focusY(pitch: pitch,viewportBottom: viewportHeight(),viewportTop: 0)
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
    func makeHeader(_ collectionView: NSCollectionView, kind: String, at indexPath: IndexPath) -> (NSView & NSCollectionViewElement)? {
      guard let layout = collectionView.collectionViewLayout as? LibraryTimelineLayout,
        let caption = layout.caption(kind: kind, at: indexPath.item) else { return nil }
      let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: .init("timeline"), for: indexPath) as! MacGridSectionHeader
      configureHeader(header, caption: caption)
      return header
    }
    private func configureHeader(_ header: MacGridSectionHeader, caption: MacTimelineCaption) {
      // Content-only updates can lay out a retained header without laying out
      // its collection. The coalesced owner ignores this event during a check.
      header.onLayout = { [weak self] in self?.scheduleNativeAdoption() }
      let content: AnyView?
      switch caption.id.kind {
      case .folder: content = parent.source.folderIdentity(at: caption.firstItem)
      case .summary: content = parent.source.introduction(at: caption.firstItem)
      case .date: content = caption.parent == nil ? parent.source.introduction(at: caption.firstItem) : nil
      }
      header.configure(caption: caption, content: content, revision: parent.source.contentRevision)
    }
    func configure(_ cell: PhotoCell, id: String) {
      parent.source.configure(cell, id: id, pixels: cellSide * (collection?.window?.backingScaleFactor ?? 2),
        originalAspect: parent.navigation.originalAspect)
      cell.setSelectionVisible(parent.selecting)
    }
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
      forRepresentedObjectAt indexPath: IndexPath) {
      if let cell = item as? PhotoCell, let id = dataSource?.itemIdentifier(for: indexPath) { configure(cell, id: id) }
      scrolled()
      scheduleNativeAdoption()
    }
    func collectionView(_ collectionView: NSCollectionView, willDisplaySupplementaryView view: NSView,
      forElementKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) {
      scheduleNativeAdoption()
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
      guard !applyingSelection, !parent.readOnly, parent.selecting else { return }
      let ids = paths.compactMap { identifier(at: $0.item) }
      if selected { parent.source.selection.formUnion(ids) }
      else { parent.source.selection.subtract(ids) }
      appliedSelection = parent.source.selection
    }
    @objc func longPress(_ recognizer: NSPressGestureRecognizer) {
      guard recognizer.state == .began, !parent.readOnly, !parent.selecting, let collection,
        let path = collection.indexPathForItem(at: recognizer.location(in: collection)) else { return }
      beginSelection(at: path)
    }
    func beginSelection(at path: IndexPath) {
      guard !parent.readOnly, let collection, let id = identifier(at: path.item) else { return }
      parent.source.selection.insert(id)
      applyingSelection = true
      collection.isSelectable = true
      collection.selectionIndexPaths = selectedPaths()
      appliedSelection = parent.source.selection
      applyingSelection = false
      parent.enterSelection()
    }
    func toggleSelection(at path: IndexPath) {
      guard !parent.readOnly, parent.selecting, let collection, let id = identifier(at: path.item) else { return }
      if parent.source.selection.contains(id) { parent.source.selection.remove(id) }
      else { parent.source.selection.insert(id) }
      applyingSelection = true
      collection.selectionIndexPaths = selectedPaths()
      appliedSelection = parent.source.selection
      applyingSelection = false
    }
    func refreshVisibleHeaders() {
      guard let collection, let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      for kind in LibraryTimelineLayout.headerKinds {
        for path in collection.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
          if let header = collection.supplementaryView(forElementKind: kind, at: path) as? MacGridSectionHeader,
            let caption = layout.caption(kind: kind, at: path.item) { configureHeader(header, caption: caption) }
        }
      }
    }
    func refreshVisibleImages() {
      guard let collection else { return }
      for path in collection.indexPathsForVisibleItems() {
        if let item = collection.item(at: path) as? PhotoCell, let id = dataSource?.itemIdentifier(for: path) { configure(item, id: id) }
      }
    }
    func scrolled() { scrolled(event: NSApp.currentEvent) }
    func scrolled(event: NSEvent?) {
      updateFooter()
      updateDense()
      guard !restoring else { return }
      if parent.active, parent.source.membershipReady, count > 0,
        let collection, let scroll = collection.enclosingScrollView, zoomStage == nil {
        let clip = scroll.contentView, height = settledContentHeight
        let previous = parent.source.scroll.offset
        let moved = abs(clip.bounds.minY - previous.y) > 0.5 || abs(clip.bounds.minX - previous.x) > 0.5
        let types: Set<NSEvent.EventType> = [.scrollWheel, .leftMouseDragged, .keyDown, .magnify, .swipe, .leftMouseDown, .smartMagnify]
        // A selection or viewer update can lay out a grid during the same
        // mouse event. Only an actual browse movement changes its edge intent;
        // an empty source must not acquire a newest-edge pin while loading.
        if moved, let event, types.contains(event.type) {
          pinnedToNewest = clip.bounds.maxY >= height - 2
        }
      }
      rememberScroll()
      scheduleVisibleDate()
      refresh.schedule { [weak self] in
        guard let self, !Task.isCancelled, let collection = self.collection else { return }
        let parent = self.parent
        guard parent.active, parent.navigation.level == .all else { return }
        self.rememberScroll()
        let paths = collection.indexPathsForVisibleItems().sorted()
        guard parent.source.membershipReady, let span = self.visibleRange() else { return }
        let first = span.first, last = span.last
        parent.source.didDisplay(self.ids[first...last])
        let dense = self.layoutDense
        if !dense {
          let range = max(0, first - 24)..<min(self.count, last + 49)
          var candidates = Array(self.ids[first...last])
          candidates.append(contentsOf: self.ids[(last + 1)..<range.upperBound])
          candidates.append(contentsOf: self.ids[range.lowerBound..<first].reversed())
          parent.source.preheat(candidates, pixels: cellSide * (collection.window?.backingScaleFactor ?? 2))
        } else { parent.source.stopPreheating() }
        guard !dense else { return }
        let cells = paths.compactMap { collection.item(at: $0) as? PhotoCell }
        await parent.source.refreshMarks(cells, receiver: parent.receiverID,
          revision: "\(parent.queueRevision)|\(parent.preparationRevision)")
      }
    }
    private var dateUpdateScheduled = false
    private func scheduleVisibleDate() {
      guard !dateUpdateScheduled else { return }
      dateUpdateScheduled = true
      // Publish outside a representable update, but independently of deferred
      // rendition preheating and backup-mark refresh.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.dateUpdateScheduled = false
        self.updateVisibleDate()
      }
    }
    func updateVisibleDate() {
      guard parent.navigation.level == .all, zoomStage == nil else { return }
      guard parent.source.membershipReady, contextID == parent.source.contextID,
        !layoutDense, let collection, let scroll = collection.enclosingScrollView,
        let layout = collection.collectionViewLayout else {
        parent.navigation.visibleDate = ""; return
      }
      // Native layout is ready before AppKit materializes visible cells. The
      // clip bounds also retain their viewport while this source is inactive.
      let viewport = scroll.contentView.bounds
      let candidates = (layout.layoutAttributesForElements(in: viewport) ?? []).compactMap { attributes -> (index: Int, frame: CGRect)? in
        guard attributes.representedElementCategory == .item,
          let path = attributes.indexPath, ids.indices.contains(path.item) else { return nil }
        return (path.item, attributes.frame)
      }
      let row = MacGridDateRange.topRow(in: viewport, items: candidates)
      parent.navigation.visibleDate = MacGridDateRange.title(dates: row.compactMap { date(at: $0) })
    }
    func rememberScroll() {
      guard !restoring, contextID == parent.source.contextID, let collection,
        let scroll = collection.enclosingScrollView,
        let layout = collection.collectionViewLayout as? LibraryTimelineLayout else { return }
      // AppKit can report the previous visible items while a resized layout is
      // being adopted. Resolve the anchor from current geometry instead.
      let range = LibraryMotion.visibleRange(count: count, in: collection.visibleRect) { layout.frame(at: $0) }
      guard let first = range.first, let id = identifier(at: first) else { return }
      let frame = layout.frame(at: first)
      guard
        frame.intersects(collection.visibleRect) else { return }
      parent.source.scroll.offset = scroll.contentView.bounds.origin
      parent.source.scroll.anchor = id
      parent.source.scroll.inset = scroll.contentView.bounds.origin.y - frame.minY
      parent.source.saveScroll()
    }

  }
}

@MainActor class LibraryCollectionView: NSCollectionView {
  var didLayout: (() -> Void)?
  override func layout() { super.layout(); didLayout?() }
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
    guard isSelectable else { return }
    let extend = !event.modifierFlags.intersection([.command, .shift]).isEmpty
    let base = extend ? selectionIndexPaths : []
    if !extend, !selectionIndexPaths.isEmpty {
      let old = selectionIndexPaths
      deselectItems(at: old); delegate?.collectionView?(self, didDeselectItemsAt: old)
    }
    let band = MacMarqueeView(frame: .zero)
    addSubview(band)
    defer {
      band.removeFromSuperview()
      keyAnchor = selectionIndexPaths.min(); keyCursor = selectionIndexPaths.max()
    }
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
  var activateOverview: ((CGPoint) -> Bool)?
  var denseHit: ((CGPoint) -> Int?)?
  var drill: ((Int) -> Void)?
  var toggleSelection: ((IndexPath) -> Void)?
  var preview: ((IndexPath) -> Void)?
  var enterSelection: ((IndexPath) -> Void)?

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    // The presentation owner resolves the shown face before native selection.
    if let activateOverview {
      if activateOverview(point) { return }
    } else if let index = denseHit?(point) {
      // AppKit increments clickCount across rapid presses. Each press on an
      // overview is still activation; it is never an ordinary double-click.
      drill?(index); return
    }
    if event.clickCount == 2,
      let path = indexPathForItem(at: point) { preview?(path); return }
    let path = indexPathForItem(at: point)
    if event.clickCount == 1, path == nil { marquee(from: point, with: event); return }
    if event.modifierFlags.contains(.shift), let path, isSelectable {
      extendSelection(to: path, additive: event.modifierFlags.contains(.command)); return
    }
    // AppKit retains ordinary click and Command-toggle behavior; their result
    // establishes the same anchor used by Shift-click and every arrow key.
    super.mouseDown(with: event)
    keyAnchor = path.flatMap { selectionIndexPaths.contains($0) ? $0 : nil }
    keyCursor = keyAnchor
  }
  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " || event.keyCode == 36 {
      if !event.isARepeat, let path = selectionIndexPaths.sorted().first { preview?(path) }
      return
    }
    if event.keyCode == 53 { applySelection([]); keyAnchor = nil; keyCursor = nil; return }
    if (123...126).contains(event.keyCode), arrowStep(event.keyCode, extend: event.modifierFlags.contains(.shift)) { return }
    super.keyDown(with: event)
  }
  private var keyAnchor: IndexPath?, keyCursor: IndexPath?
  func remapSelectionAnchors(from ids: [String], to positions: [String: Int], reset: Bool) {
    func mapped(_ path: IndexPath?) -> IndexPath? {
      guard !reset, let path, ids.indices.contains(path.item), let item = positions[ids[path.item]] else { return nil }
      return IndexPath(item: item, section: 0)
    }
    keyAnchor = mapped(keyAnchor); keyCursor = mapped(keyCursor)
  }
  private func applySelection(_ target: Set<IndexPath>) {
    let selected = selectionIndexPaths
    let removed = selected.subtracting(target), added = target.subtracting(selected)
    if !removed.isEmpty { deselectItems(at: removed); delegate?.collectionView?(self, didDeselectItemsAt: removed) }
    if !added.isEmpty { selectItems(at: added, scrollPosition: []); delegate?.collectionView?(self, didSelectItemsAt: added) }
  }
  func extendSelection(to next: IndexPath, additive: Bool = false) {
    let selected = selectionIndexPaths
    let anchor = keyAnchor.flatMap { selected.contains($0) ? $0 : nil }
      ?? keyCursor.flatMap { selected.contains($0) ? $0 : nil } ?? selected.min() ?? next
    let (first, last) = anchor < next ? (anchor, next) : (next, anchor)
    guard first.section >= 0, last.section < numberOfSections else { return }
    var range = Set<IndexPath>()
    // Selection follows item order, independently of mounted cells, row wraps
    // and date headings. Rubber-band dragging remains spatial.
    for section in first.section...last.section {
      let count = numberOfItems(inSection: section)
      let lower = section == first.section ? first.item : 0
      let upper = section == last.section ? last.item : count - 1
      guard lower >= 0, upper < count, lower <= upper else { continue }
      for item in lower...upper { range.insert(IndexPath(item: item, section: section)) }
    }
    applySelection(additive ? selected.union(range) : range)
    keyAnchor = anchor; keyCursor = next
  }
  /// Left/Right follow item order, including row wraps. Shift keeps the fixed
  /// anchor while the keyboard cursor grows or contracts a contiguous range.
  private func arrowStep(_ key: UInt16, extend: Bool) -> Bool {
    guard isSelectable else { return false }
    let count = numberOfSections > 0 ? numberOfItems(inSection: 0) : 0
    guard count > 0 else { return false }
    let selected = selectionIndexPaths
    let step = key == 124 || key == 125 ? 1 : -1
    let cursor = keyCursor.flatMap { selected.contains($0) ? $0 : nil } ?? (step > 0 ? selected.max() : selected.min())
    guard let cursor else { return false }
    var next = IndexPath(item: min(count - 1, max(0, cursor.item + step)), section: 0)
    if key == 125 || key == 126, let layout = collectionViewLayout as? LibraryTimelineLayout {
      let origin = layout.frame(at: cursor.item)
      let candidates = (max(0, cursor.item - layout.columns * 2)...min(count - 1, cursor.item + layout.columns * 2))
        .filter { step > 0 ? layout.frame(at: $0).minY > origin.minY + 0.5 : layout.frame(at: $0).minY < origin.minY - 0.5 }
      if let row = candidates.map({ layout.frame(at: $0).minY }).min(by: { abs($0 - origin.minY) < abs($1 - origin.minY) }),
        let item = candidates.filter({ abs(layout.frame(at: $0).minY - row) < 0.5 })
          .min(by: { abs(layout.frame(at: $0).midX - origin.midX) < abs(layout.frame(at: $1).midX - origin.midX) }) {
        next = IndexPath(item: item, section: 0)
      } else { next = cursor }
    }
    if extend { extendSelection(to: next) }
    else { applySelection([next]); keyAnchor = next; keyCursor = next }
    scrollToItems(at: [next], scrollPosition: [.nearestHorizontalEdge, .nearestVerticalEdge])
    return true
  }
}

private final class MacMarqueeView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = DuckSelection.fillNSColor.cgColor
    layer?.borderColor = DuckSelection.borderNSColor.cgColor
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
  var tint: NSColor = DuckMedia.onMediaNSColor { didSet { if tint != oldValue { refresh() } } }
  var scale: CGFloat = 2 { didSet { if scale != oldValue { refresh() } } }
  private let glyph = CALayer()
  private static var cache: [String: CGImage] = [:]
  static let still: [String: CAAction] = [
    "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "hidden": NSNull(),
    "contentsScale": NSNull(), "backgroundColor": NSNull(), "cornerRadius": NSNull(),
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
  var readingGlyphLayer: CALayer { glyph }
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
      .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: weight), .foregroundColor: DuckMedia.onMediaNSColor,
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

/// Marks keep their native glyph size inside the currently visible photo.
/// Only their lower reading edge follows a footer; photo geometry is unchanged.
@MainActor enum MacGridReadingMarks {
  struct Mark {
    let layer: CALayer
    var frame: CGRect
    var glyphWidth: CGFloat = 0
    var trailing = false
  }
  struct Pose {
    let layer: CALayer
    let frame: CGRect
    let opacity: Float
  }
  struct Correction {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let opacity: Float
  }
  static func poses(_ marks: [Mark], photo: CGRect, tile: CGRect, visible: CGRect?) -> [Pose] {
    guard let visible else { return marks.map { Pose(layer: $0.layer, frame: $0.frame, opacity: 1) } }
    // Tiles and their layer contents use upward local coordinates inside the
    // downward viewport. Convert the photo-only boundary once into that space.
    let local = CGRect(x: visible.minX - tile.minX, y: tile.maxY - visible.maxY,
      width: visible.width, height: visible.height)
    let area = photo.intersection(local).intersection(CGRect(origin: .zero, size: tile.size))
    return marks.map { mark in
      var frame = mark.frame
      let glyphWidth = max(frame.width, mark.glyphWidth)
      let glyphRect = CGRect(x: frame.midX - glyphWidth / 2, y: frame.minY, width: glyphWidth, height: frame.height)
      if area == photo, CGRect(origin: .zero, size: tile.size).contains(glyphRect) {
        return Pose(layer: mark.layer, frame: frame, opacity: 1)
      }
      let room = area.height - frame.height
      let padding = min(7, max(0, room / 2))
      // Keep following the same edge even when no room remains. A hidden
      // sample must not send a still-fading glyph back across the photograph.
      let lowerEdge = max(photo.minY, local.minY)
      frame.origin.y = max(frame.minY, lowerEdge + padding)
      if room >= 0 { frame.origin.y = min(area.maxY - frame.height - padding, frame.minY) }
      // Fade the whole plate before its glyph can reach a hard clipping edge.
      // The small reserve also covers subpixel spring/keyframe quantization.
      let horizontal = min(frame.midX - glyphWidth / 2 - area.minX, area.maxX - frame.midX - glyphWidth / 2)
      let verticalOpacity = min(1, max(0, (room - 4) / max(1, frame.height - 4)))
      let horizontalOpacity = min(1, max(0, (horizontal - 1) / 2))
      return Pose(layer: mark.layer, frame: frame, opacity: Float(min(verticalOpacity, horizontalOpacity)))
    }
  }
  static func hosted(_ poses: [Pose], tile: CGRect, visible: CGRect, height: CGFloat) -> [Pose] {
    poses.map { pose in
      var rect = CGRect(x: tile.minX + pose.frame.minX, y: height - tile.maxY + pose.frame.minY,
        width: pose.frame.width, height: pose.frame.height)
      let glyphWidth = max(rect.width, (pose.layer as? MacTextBadgeLayer)?.textWidth ?? 0)
      // Photos stop 30 pt before totals; whole reading marks may use 22 pt of
      // that quiet space while retaining an 8 pt gap above the totals.
      let edge = min(height, max(0, visible.maxY + 30 - DuckSpacing.xSmall))
      let lowerY = height - edge
      let fits = edge >= rect.height && visible.width >= glyphWidth
      rect.origin.y = min(height - rect.height, max(lowerY, rect.minY))
      let overhang = (glyphWidth - rect.width) / 2
      rect.origin.x = max(visible.minX + overhang, min(visible.maxX - rect.width - overhang, rect.minX))
      return Pose(layer: pose.layer, frame: rect, opacity: fits ? pose.opacity : 0)
    }
  }
  static func corrected(_ poses: [Pose], corrections: [ObjectIdentifier: Correction], weight: CGFloat,
    visible: CGRect, height: CGFloat) -> [Pose] {
    let shifted = poses.map { pose -> Pose in
      guard let c = corrections[ObjectIdentifier(pose.layer)] else { return pose }
      return Pose(layer: pose.layer, frame: CGRect(x: pose.frame.minX + c.x * weight,
        y: pose.frame.minY + c.y * weight, width: max(1, pose.frame.width + c.width * weight), height: pose.frame.height),
        opacity: min(1, max(0, pose.opacity + c.opacity * Float(weight))))
    }
    // Corrections are only carried for an interrupted release, and every
    // rendered glyph must continue to obey the same viewport reading bounds.
    return shifted.map { pose in
      let edge = min(height, max(0, visible.maxY + 30 - DuckSpacing.xSmall))
      let glyphWidth = max(pose.frame.width, (pose.layer as? MacTextBadgeLayer)?.textWidth ?? 0)
      let overhang = (glyphWidth - pose.frame.width) / 2
      var frame = pose.frame
      frame.origin.y = min(height - frame.height, max(height - edge, frame.minY))
      frame.origin.x = max(visible.minX + overhang, min(visible.maxX - frame.width - overhang, frame.minX))
      return Pose(layer: pose.layer, frame: frame, opacity: pose.opacity)
    }
  }
  static func value(_ animation: CAKeyframeAnimation, at progress: CGFloat) -> CGFloat? {
    guard let values = animation.values as? [NSNumber], !values.isEmpty else { return nil }
    let p = min(1, max(0, progress))
    let times = animation.keyTimes?.map { CGFloat(truncating: $0) }
      ?? values.indices.map { CGFloat($0) / CGFloat(max(1, values.count - 1)) }
    guard let end = times.firstIndex(where: { $0 >= p }) else { return CGFloat(truncating: values.last!) }
    if end == 0 { return CGFloat(truncating: values[0]) }
    let a = end - 1, t = (p - times[a]) / max(0.000001, times[end] - times[a])
    return CGFloat(truncating: values[a]) * (1 - t) + CGFloat(truncating: values[end]) * t
  }
  static func snapshot(_ layers: [CALayer], at progress: CGFloat) -> [Pose] {
    layers.compactMap { layer in
      guard let opacity = layer.animation(forKey: "zoom.readingOpacity") as? CAKeyframeAnimation,
        let alpha = value(opacity, at: progress) else { return nil }
      @MainActor func scalar(_ key: String) -> CGFloat {
        if let move = layer.animation(forKey: "zoom." + key) as? CAKeyframeAnimation,
          let result = value(move, at: progress) { return result }
        return CGFloat((layer.value(forKeyPath: key) as? NSNumber)?.doubleValue ?? 0)
      }
      let width = scalar("bounds.size.width"), h = layer.bounds.height
      return Pose(layer: layer, frame: CGRect(x: scalar("position.x") - width * layer.anchorPoint.x,
        y: scalar("position.y") - h * layer.anchorPoint.y, width: width, height: h), opacity: Float(alpha))
    }
  }
  static func apply(_ poses: [Pose]) {
    for pose in poses {
      pose.layer.frame = pose.frame; pose.layer.opacity = pose.opacity
      if let text = pose.layer as? MacTextBadgeLayer { text.setNeedsLayout(); text.layoutIfNeeded() }
    }
  }
  static func remove(from layers: [CALayer]) {
    for layer in layers {
      for key in ["zoom.readingOpacity", "zoom.position.x", "zoom.position.y", "zoom.bounds.size.width",
        "zoom.velocity.position.x", "zoom.velocity.position.y"] { layer.removeAnimation(forKey: key) }
      if let glyph = (layer as? MacTextBadgeLayer)?.readingGlyphLayer {
        glyph.removeAnimation(forKey: "zoom.readingGlyph.position.x")
        glyph.removeAnimation(forKey: "zoom.readingGlyph.bounds.size.width")
      }
    }
  }
  static func animate(_ samples: [[Pose]], start: CFTimeInterval, duration: CFTimeInterval,
    batch: MacGridAnimationBatch?) {
    guard let first = samples.first else { return }
    for (index, initial) in first.enumerated() {
      let layer = initial.layer
      for (key, name, values) in [
        ("position.x", "zoom.position.x", samples.map { NSNumber(value: Double($0[index].frame.minX + $0[index].frame.width * layer.anchorPoint.x)) }),
        ("position.y", "zoom.position.y", samples.map { NSNumber(value: Double($0[index].frame.minY + $0[index].frame.height * layer.anchorPoint.y)) }),
        ("bounds.size.width", "zoom.bounds.size.width", samples.map { NSNumber(value: Double($0[index].frame.width)) }),
        ("opacity", "zoom.readingOpacity", samples.map { NSNumber(value: $0[index].opacity) }),
      ] {
        let move = CAKeyframeAnimation(keyPath: key)
        move.values = values; move.duration = duration; move.calculationMode = .linear
        move.beginTime = layer.convertTime(start, from: nil)
        MacGridAnimationBatch.schedule(move, on: layer, key: name, batch: batch)
      }
      if let glyph = (layer as? MacTextBadgeLayer)?.readingGlyphLayer {
        for (key, values) in [
          ("position.x", samples.map { NSNumber(value: Double($0[index].frame.width * glyph.anchorPoint.x)) }),
          ("bounds.size.width", samples.map { NSNumber(value: Double($0[index].frame.width)) }),
        ] {
          let move = CAKeyframeAnimation(keyPath: key)
          move.values = values; move.duration = duration; move.calculationMode = .linear
          move.beginTime = glyph.convertTime(start, from: nil)
          MacGridAnimationBatch.schedule(move, on: glyph, key: "zoom.readingGlyph." + key, batch: batch)
        }
      }
    }
  }
}

@MainActor protocol MacGridReadingTile: AnyObject {
  var readingMarkLayers: [CALayer] { get }
  func setReadingRect(_ visible: CGRect?)
  func setReadingHost(_ host: NSView?)
  func readingMarkPoses(in frame: CGRect, visible: CGRect?) -> [MacGridReadingMarks.Pose]
}

@MainActor final class PhotoCell: NSCollectionViewItem {
  private var cancelImageRequest: (() -> Void)?
  private var token = UUID()
  private var imageKey = ""
  private(set) var assetID: String?
  private(set) var presentationID: String?
  private let photoLayer = CALayer()
  var hasPhotoContents: Bool { photoLayer.contents != nil }
  private(set) var displayedImage: NSImage?
  var onDisplay: (() -> Void)?
  private let media = MacBadgeLayer()
  private let status = MacBadgeLayer()
  private let cloud = MacBadgeLayer()
  private var selectionVisible = true
  private var statusState: String?
  private var configuredFolderPhoto: FolderPhoto?
  private let burstCount = MacTextBadgeLayer(weight: .medium, fill: DuckMedia.scrimBurstNSColor, radius: 4)
  private let duration = MacTextBadgeLayer(weight: .semibold, fill: DuckMedia.scrimDurationNSColor, radius: 5)
  private var zoomReadingRect: CGRect?
  private weak var zoomReadingHost: NSView?
  var zoomReadingFrame: CGRect?
  var zoomReadingLayers: [CALayer] { [media, burstCount, duration, cloud, status] }
  func setZoomReadingHost(_ host: NSView?) {
    guard zoomReadingHost !== host else { return }
    CATransaction.begin(); CATransaction.setDisableActions(true)
    if host == nil { MacGridReadingMarks.remove(from: zoomReadingLayers) }
    zoomReadingHost = host
    for layer in zoomReadingLayers {
      layer.removeFromSuperlayer(); (host?.layer ?? view.layer)?.addSublayer(layer)
    }
    viewDidLayout()
    CATransaction.commit()
  }
  func setZoomReadingRect(_ visible: CGRect?, frame: CGRect) {
    zoomReadingRect = visible; zoomReadingFrame = frame
    if visible == nil { MacGridReadingMarks.remove(from: zoomReadingLayers) }
    viewDidLayout()
  }
  func zoomReadingPoses(in frame: CGRect, visible: CGRect?) -> [MacGridReadingMarks.Pose] {
    let f = photoFrame(in: CGRect(origin: .zero, size: frame.size))
    let durationWidth = max(1, min(f.width - 16, max(42, duration.textWidth + 12)))
    return MacGridReadingMarks.poses([
      .init(layer: media, frame: CGRect(x: f.minX + 7, y: f.minY + 7, width: 18, height: 18)),
      .init(layer: burstCount, frame: CGRect(x: f.minX + 28, y: f.minY + 7, width: 36, height: 18), glyphWidth: burstCount.textWidth),
      .init(layer: duration, frame: CGRect(x: f.maxX - durationWidth - 7, y: f.minY + 7, width: durationWidth, height: 18), glyphWidth: duration.textWidth, trailing: true),
      .init(layer: cloud, frame: CGRect(x: f.minX + 8, y: f.minY + 8, width: 24, height: 24)),
      .init(layer: status, frame: CGRect(x: f.maxX - 32, y: f.minY + 8, width: 24, height: 24)),
    ], photo: f, tile: frame, visible: visible)
  }
  /// Hover help for the visible status and burst badges, as tooltip rectangles
  /// on the cell's one view.
  private var statusTip: String?
  private var burstTip: String?
  private var groupDescription = ""
  override func loadView() {
    view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = DuckRole.mediaPlaceholderNSColor.cgColor
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
    // design/library.md § Tile marks: white glyphs with a soft shadow, no circles.
    for badge in [media, status, cloud] {
      view.layer?.addSublayer(badge)
      badge.shadowColor = DuckMedia.shadowCGColor
      badge.shadowOpacity = 0.45
      badge.shadowRadius = 2
      badge.shadowOffset = CGSize(width: 0, height: -0.5)
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
    CATransaction.begin(); CATransaction.setDisableActions(true)
    let scale = view.window?.backingScaleFactor ?? 2
    for badge in [media, status, cloud] { badge.scale = scale }
    burstCount.scale = scale; duration.scale = scale
    let frame = zoomReadingFrame ?? view.frame
    let poses = zoomReadingPoses(in: frame, visible: zoomReadingRect)
    if let host = zoomReadingHost {
      MacGridReadingMarks.apply(MacGridReadingMarks.hosted(poses, tile: frame,
        visible: zoomReadingRect ?? host.bounds, height: host.bounds.height))
    } else { MacGridReadingMarks.apply(poses) }
    selectionOutline.frame = photoFrame()
    CATransaction.commit()
    updateTips()
  }
  override var isSelected: Bool {
    didSet {
      view.layer?.borderWidth = 0
      view.layer?.borderColor = NSColor.controlAccentColor.cgColor
      updateSelectionMark()
      status.isHidden = (selectionVisible && isSelected) || status.symbol == nil
    }
  }
  func configure(_ asset: PHAsset, pipeline: ThumbnailPipeline, pixels: CGFloat, originalAspect: Bool = false, identifier: String? = nil) {
    presentationID = identifier ?? asset.localIdentifier
    let key =
      "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))|\(pipeline.size(pixels).width)|\(PreviewNetworkPolicy.shared.allowed)|\(pipeline.epoch)|\(originalAspect)"
    guard imageKey != key else { return }
    let sameAsset = assetID == asset.localIdentifier
    cancel()
    assetID = asset.localIdentifier
    imageKey = key
    if !sameAsset {
      displayedImage = nil
      photoLayer.contents = nil
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
    requestImage(.library(asset, pipeline: pipeline, pixels: pixels, originalAspect: originalAspect)) { [weak self] image, inCloud in
      self?.cloud.symbol = "icloud"
      self?.cloud.isHidden = image != nil || !inCloud
    }
  }
  func setPresentationID(_ id: String) { presentationID = id }
  func configureUnavailable(id: String, label: String, video: Bool) {
    if assetID != id {
      cancel(); assetID = id; presentationID = id; imageKey = "unavailable|" + id
      displayedImage = nil; photoLayer.contents = nil; fitted = false
      media.symbol = video ? "video.fill" : "photo"; media.isHidden = false
      cloud.isHidden = true; duration.isHidden = true; burstCount.isHidden = true
      view.layer?.backgroundColor = DuckRole.mediaPlaceholderNSColor.cgColor
    }
    view.setAccessibilityLabel(label); view.needsLayout = true
  }
  /// Folder browsing reuses the library cell, V5 marks, selection and cancellation.
  func configureFolder(_ photo: FolderPhoto, source: FolderSource, pixels: CGFloat, synthetic: NSImage? = nil) {
    let key = "folder|\(photo.id)|\(photo.revision)|\(pixels)"
    guard imageKey != key || configuredFolderPhoto != photo else { return }
    if imageKey != key {
      let sameFile = presentationID == photo.id && imageKey.hasPrefix("folder|\(photo.id)|\(photo.revision)|")
      cancel(); imageKey = key; assetID = photo.source_id; presentationID = photo.id
      fitted = false
      if !sameFile { displayedImage = nil; photoLayer.contents = nil }
      media.symbol = photo.media_type.hasPrefix("video/") ? "video.fill" : nil
      media.isHidden = media.symbol == nil; cloud.isHidden = true
      duration.isHidden = true; burstCount.isHidden = true
      if let synthetic { retainDisplayedImage(synthetic) }
      else {
        requestImage(.folder(photo, source: source, pixels: pixels)) { [weak self] image, _ in
          // A missing file (an ejected card) retries on the next configure.
          if image == nil { self?.imageKey = "" }
        }
      }
    }
    configuredFolderPhoto = photo
    setSelectionVisible(true)
    setState(photo.backup == "sending" ? "sending" : photo.backup == "saving" ? "saving" : photo.backup == "needs_you" ? "needs_you" : nil)
    let statusKey = photo.backup == "saved" ? "folders_photo_saved" : photo.backup == "saving" ? "folders_photo_saving" : photo.backup == "sending" ? "folders_photo_sending" : photo.backup == "needs_you" ? "folders_photo_needs_you" : "folders_photo_not_backed_up"
    statusTip = NSLocalizedString(statusKey, comment: ""); view.setAccessibilityValue(statusTip); updateTips()
    view.alphaValue = 1
    view.setAccessibilityLabel(photo.relative + ". " + photo.date.formatted(date: .abbreviated, time: .shortened))
    view.needsLayout = true
  }
  func requestImage(_ request: MacGridImageRequest, delivered: @escaping MacGridImageRequest.Delivery) {
    if photoLayer.contents == nil { photoLayer.contents = request.placeholder() }
    let expected = token
    cancelImageRequest = request.request { [weak self] image, inCloud in
      guard let self, self.token == expected else { return }
      if let image { self.retainDisplayedImage(image) }
      delivered(image, inCloud)
    }
  }
  private var fitted = false
  private var assetAspect: CGFloat = 1
  /// The rectangle the photo occupies in the cell: the whole cell, or the
  /// aspect-fit rectangle in original-aspect mode.
  private func photoFrame(in bounds: CGRect? = nil) -> CGRect {
    var b = bounds ?? view.bounds
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
  var fullAspectRatio: CGFloat? {
    if imageKey.hasPrefix("folder|") {
      return displayedImage.map { $0.size.width / max(1, $0.size.height) }
    }
    return assetAspect
  }
  var photoCornerRadius: CGFloat { photoRadius() }
  private func photoRadius() -> CGFloat { fitted ? max(2, view.bounds.width * 0.035) : 0 }
  private func applyPhotoFrame(animated: Bool) {
    let target = photoFrame()
    view.layer?.backgroundColor = fitted ? NSColor.clear.cgColor : DuckRole.mediaPlaceholderNSColor.cgColor
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
    MacCoverFlightSource.install(image.cgImage(forProposedRect: nil,context: nil,hints: nil), on: photoLayer)
    onDisplay?()
  }
  func setGroup(count: Int?, state: String?) {
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
    status.symbol = libraryTileSymbol(state)
    status.tint = DuckMedia.onMediaNSColor
    status.backgroundColor = nil
    status.shadowColor = DuckMedia.shadowCGColor
    status.shadowOpacity = 0.45
    status.shadowRadius = 2
    status.shadowOffset = CGSize(width: 0, height: -0.5)
    let detail = groupDescription + NSLocalizedString(libraryTileAccessibilityKey(state), comment: "")
    view.setAccessibilityValue(detail)
    status.isHidden = (selectionVisible && isSelected) || state == nil || status.symbol == nil
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
    guard selectionVisible != value else { return }
    selectionVisible = value
    view.layer?.borderWidth = 0
    status.isHidden = (value && isSelected) || statusState == nil || status.symbol == nil
    updateTips()
    updateSelectionMark()
  }
  /// Selection is an accent outline around the photo, as in Photos: no check
  /// mark and no dimming. Rebuilding layer state on every SwiftUI update pass
  /// was a measurable hot spot, so only changes are applied.
  private func updateSelectionMark() {
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
    cancelImageRequest?()
    cancelImageRequest = nil
    token = UUID()
    imageKey = ""
    configuredFolderPhoto = nil
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    cancel()
    setZoomReadingHost(nil)
    zoomReadingRect = nil; zoomReadingFrame = nil
    MacGridReadingMarks.remove(from: zoomReadingLayers)
    for layer in zoomReadingLayers { layer.opacity = 1 }
    photoLayer.contents = nil
    assetID = nil
    displayedImage = nil
    presentationID = nil
  }
}

/// A viewer owns the source offset until its return starts. Native sizing can
/// continue, but layout and focus requests cannot scroll the departing grid.
@MainActor final class MacGridClipView: NSClipView {
  private var held: (id: UUID, origin: CGPoint, released: () -> Void)?
  func retainViewport(released: @escaping () -> Void) -> MacGridViewportHold {
    let id = UUID()
    held = (id, bounds.origin, released)
    return MacGridViewportHold(clip: self, id: id)
  }
  func releaseViewport(_ id: UUID) {
    guard let held, held.id == id else { return }
    self.held = nil
    held.released()
  }
  override var bounds: NSRect {
    get { super.bounds }
    set {
      var next = newValue
      if let held { next.origin = held.origin }
      super.bounds = next
    }
  }
  override func setBoundsOrigin(_ newOrigin: NSPoint) {
    super.setBoundsOrigin(held?.origin ?? newOrigin)
  }
  override func scroll(to newOrigin: NSPoint) {
    super.scroll(to: held?.origin ?? newOrigin)
  }
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var next = super.constrainBoundsRect(proposedBounds)
    if let held { next.origin = held.origin }
    return next
  }
}

@MainActor final class MacGridViewportHold {
  private weak var clip: MacGridClipView?
  private let id: UUID
  init(clip: MacGridClipView, id: UUID) { self.clip = clip; self.id = id }
  func release() { clip?.releaseViewport(id); clip = nil }
  deinit {
    let id = id
    Task { @MainActor [weak clip] in clip?.releaseViewport(id) }
  }
}

@MainActor final class LibraryScrollView: NSScrollView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    contentView = MacGridClipView(frame: contentView.frame)
  }
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    contentView = MacGridClipView(frame: contentView.frame)
  }
  func retainViewport() -> MacGridViewportHold? {
    (contentView as? MacGridClipView)?.retainViewport { [weak self] in self?.viewportReleased?() }
  }
  var viewportReleased: (() -> Void)?
  var restoreScroll: ((LibraryScrollView) -> Void)?
  var willScroll: (() -> Void)?
  var didScroll: (() -> Void)?
  private var scrollInputOwnsViewport = false
  var userScrollEnded: (() -> Void)?
  private var scrollIdleTask: Task<Void, Never>?
  private var lastScrollInput = TimeInterval.zero
  private(set) var userScrollRevision = 0
  var isUserScrolling: Bool { scrollIdleTask != nil }
  private var notifyingScroll = false
  var embeddedPreview = false
  func endScrollInput() { scrollInputOwnsViewport = false }
  override func scrollWheel(with event: NSEvent) {
    if embeddedPreview { nextResponder?.scrollWheel(with: event) }
    else {
      let moves = event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0
      if moves {
        willScroll?(); scrollInputOwnsViewport = true
        if userScrollEnded != nil { noteUserScroll() }
      }
      super.scrollWheel(with: event)
    }
  }
  private func noteUserScroll() {
    userScrollRevision &+= 1
    lastScrollInput = ProcessInfo.processInfo.systemUptime
    guard scrollIdleTask == nil else { return }
    scrollIdleTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(150))
        guard let self, !Task.isCancelled else { return }
        if ProcessInfo.processInfo.systemUptime - self.lastScrollInput >= 0.15 {
          self.scrollIdleTask = nil
          self.scrollInputOwnsViewport = false
          self.userScrollEnded?()
          return
        }
      }
    }
  }
  override func reflectScrolledClipView(_ clipView: NSClipView) {
    super.reflectScrolledClipView(clipView)
    guard clipView === contentView, scrollInputOwnsViewport, !notifyingScroll else { return }
    notifyingScroll = true
    defer { notifyingScroll = false }
    didScroll?()
  }
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
    let flow = MacCalendarFlowLayout(kind: kind)
    let collection = MacCalendarCollection()
    collection.collectionViewLayout = flow; collection.backgroundColors = [.clear]
    collection.register(MacCalendarCell.self, forItemWithIdentifier: .init("period"))
    collection.dataSource = context.coordinator; collection.delegate = context.coordinator
    collection.isSelectable = true; collection.allowsMultipleSelection = false
    collection.select = { [weak c = context.coordinator] path, point in c?.select(path.item, at: point) }
    collection.open = { [weak c = context.coordinator] path, point in c?.open(path.item, at: point) }
    collection.openSelected = { [weak c = context.coordinator] in c?.openSelected() }
    let scroll = MacCalendarScrollView()
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
    let sourcePeriods = kind == .years ? navigation.years : navigation.months
    var fingerprint = Hasher()
    for period in sourcePeriods {
      fingerprint.combine(period.id)
      fingerprint.combine(period.covers)
      fingerprint.combine(period.tokens)
    }
    let key = "\(kind.rawValue)|\(library.generation)|\(fingerprint.finalize())"
    let active = navigation.level == kind
    let newest = c.newestRevision != navigation.newestRevision
    let focused = c.focusRevision != navigation.focusRevision && navigation.focusLevel == kind
      && navigation.focusToken != nil
    scroll.setAccessibilityHidden(!active)
    MacLevelFade.apply(scroll,layer: kind,current: navigation.level)
    c.startCoverLife()
    guard let collection = c.collection else { return }
    if c.viewGeneration != library.viewGeneration {
      c.viewGeneration = library.viewGeneration; c.initializedPosition = false
    }
    if c.key != key {
      let periods = Array(sourcePeriods.reversed())
        .map { kind == .months ? Self.chronologicalMonth($0) : $0 }
      c.key = key; c.periods = periods; c.positioning = true
      c.clearYearChoices()
      // AppKit may ask the delegate for item sizes during reload. Use the
      // viewport's actual width before it measures the new calendar covers.
      if scroll.contentSize.width > 120 {
        collection.setFrameSize(CGSize(width: scroll.contentSize.width, height: collection.frame.height))
      }
      collection.reloadData()
      collection.collectionViewLayout?.invalidateLayout()
      collection.layoutSubtreeIfNeeded()
      c.positioning = false
    }
    if active, !c.wasActive {
      // AppKit may defer visible-cell creation for the retained transparent
      // level. Activation owns a native visible-region layout even without a
      // new membership or navigation request.
      collection.needsLayout = true
      collection.layoutSubtreeIfNeeded()
    }
    if active, !navigation.indexing, !c.periods.isEmpty, !c.initializedPosition || newest || focused {
      c.positioning = true
      collection.layoutSubtreeIfNeeded()
      place(scroll,c, newest: newest)
      c.initializedPosition = true
      c.positioning = false
    }
    if !active || !navigation.indexing { c.newestRevision = navigation.newestRevision }
    if (active && !navigation.indexing) || navigation.focusLevel != kind || navigation.focusToken == nil {
      c.focusRevision = navigation.focusRevision
    }
    c.wasActive = active
  }
  /// Keep sampled covers and their drill-down tokens together when reversing
  /// PhotoKit's newest-first index into the calendar's reading order.
  static func chronologicalMonth(_ period: LibraryCalendarPeriod) -> LibraryCalendarPeriod {
    let ordered = zip(period.covers, period.tokens).sorted { $0.0 > $1.0 }
    var result = period
    result.covers = ordered.map(\.0); result.tokens = ordered.map(\.1)
    return result
  }
  static func monthCoverSlots(count: Int, mirrored: Bool) -> [(Int, Int, Int, Int)] {
    MacCalendarCover.lattice(count, mirrored: mirrored)
  }
  /// Explicit navigation is applied by the collection's next native layout.
  /// Resize and later layout passes never replay an old navigation request.
  private func place(_ scroll: NSScrollView,_ c: Coordinator, newest: Bool = false) {
    guard let collection = c.collection as? MacCalendarCollection else { return }
    c.userScrolled = false
    var target: Int?
    if !newest, let token = navigation.focusToken, let raw = Self.rawPosition(token, in: library.fetch),
      let fetch = library.fetch {
      let date = fetch.object(at: raw).creationDate
      let granularity: Calendar.Component = kind == .years ? .year : .month
      target = c.periods.firstIndex { period in
        guard let start = period.date, let date else { return period.date == nil && date == nil }
        return Calendar.current.isDate(date, equalTo: start, toGranularity: granularity)
      }
    }
    collection.place(target)
  }
  fileprivate static func rawPosition(_ token: String, in fetch: PHFetchResult<PHAsset>?) -> Int? {
    guard let fetch else { return nil }
    let result: PHFetchResult<PHAsset>
    guard BackupEnvironment.usesPhotoLibrary else {
      var position: Int?
      fetch.enumerateObjects { asset, index, stop in
        if asset.localIdentifier == token { position = index; stop.pointee = true }
      }
      return position
    }
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
    var newestRevision = 0
    var focusRevision = 0
    var viewGeneration = -1
    var initializedPosition = false
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
      guard let collection, (collection as? MacCalendarCollection)?.restoringViewport != true,
        !collection.inLiveResize else { return }
      let types: Set<NSEvent.EventType> = [.scrollWheel, .leftMouseDragged, .keyDown, .swipe, .leftMouseDown]
      if let type = NSApp.currentEvent?.type, types.contains(type) {
        userScrolled = true; lastUserScroll = Date()
        collection.visibleItems().forEach { ($0 as? MacCalendarCell)?.stopVideo() }
      }
      guard !positioning, parent.navigation.level == parent.kind else { return }
      let center = CGPoint(x: collection.visibleRect.midX,y: collection.visibleRect.midY)
      let path = collection.indexPathsForVisibleItems().min { a,b in
        guard let left = collection.collectionViewLayout?.layoutAttributesForItem(at: a)?.frame,
          let right = collection.collectionViewLayout?.layoutAttributesForItem(at: b)?.frame else { return a < b }
        return hypot(left.midX-center.x,left.midY-center.y) < hypot(right.midX-center.x,right.midY-center.y)
      }
      guard let path, periods.indices.contains(path.item), let token = periods[path.item].tokens.first else { return }
      if parent.navigation.focusToken != token { parent.navigation.focusToken = token }
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
      let covers = periods.indices.contains(indexPath.item) ? periods[indexPath.item].covers.count : 1
      return MacCalendarMetrics.itemSize(kind: parent.kind, width: collectionView.bounds.width, covers: covers)
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
      if level == .years {
        parent.navigation.focus(token, at: .months); parent.navigation.level = .months
        return
      }
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
    func clearYearChoices() { yearCache.removeAll() }
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
          let idle = !collection.inLiveResize && !self.userScrolledRecently && self.parent.navigation.level == self.parent.kind
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

/// Cover dimensions are a reading scale, independent of the photo grid density.
@MainActor enum MacCalendarMetrics {
  static let inset: CGFloat = 28
  static let gap: CGFloat = 12
  static let maximumYearWidth: CGFloat = 240
  static let maximumMonthWidth: CGFloat = 760
  static func itemSize(kind: MacLibraryLevel, width: CGFloat, covers: Int) -> NSSize {
    let content = max(1, width - inset * 2)
    if kind == .years {
      let columns = max(1, Int(ceil((content + gap) / (maximumYearWidth + gap))))
      let side = max(1, floor((content - CGFloat(columns - 1) * gap) / CGFloat(columns)))
      return NSSize(width: side, height: round(side * 1.25))
    }
    let module = min(content, maximumMonthWidth)
    return NSSize(width: module, height: max(1, MacCalendarCover.monthHeight(width: module, count: covers)))
  }
}

@MainActor final class MacCalendarFlowLayout: NSCollectionViewFlowLayout {
  let kind: MacLibraryLevel
  init(kind: MacLibraryLevel) {
    self.kind = kind
    super.init()
    minimumInteritemSpacing = MacCalendarMetrics.gap; minimumLineSpacing = 20
    sectionInset = NSEdgeInsets(top: 16, left: MacCalendarMetrics.inset, bottom: 28, right: MacCalendarMetrics.inset)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func prepare() {
    if let collectionView {
      let side = kind == .months
        ? max(MacCalendarMetrics.inset, (collectionView.bounds.width - MacCalendarMetrics.maximumMonthWidth) / 2)
        : MacCalendarMetrics.inset
      if sectionInset.left != side || sectionInset.right != side {
        sectionInset = NSEdgeInsets(top: 16, left: side, bottom: 28, right: side)
      }
    }
    super.prepare()
  }
}

/// Calendar owns its viewport reflow. The ordinary-grid scroll view's generic
/// visible-cell fallback must not race the calendar's native layout anchor.
@MainActor final class MacCalendarScrollView: NSScrollView {
  override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.05 ? nil : super.hitTest(point) }
  override func layout() {
    super.layout()
    guard let collection = documentView as? MacCalendarCollection, contentSize.width > 120 else { return }
    if collection.frame.width != contentSize.width {
      collection.setFrameSize(NSSize(width: contentSize.width, height: collection.frame.height))
    }
    collection.layoutSubtreeIfNeeded()
  }
}

@MainActor final class MacCalendarCollection: NSCollectionView {
  /// A faded-out level layer must not take clicks meant for the level above it.
  override func hitTest(_ point: NSPoint) -> NSView? {
    (enclosingScrollView?.alphaValue ?? 1) < 0.05 ? nil : super.hitTest(point)
  }
  var select: ((IndexPath, CGPoint) -> Void)?
  var open: ((IndexPath, CGPoint) -> Void)?
  var openSelected: (() -> Void)?
  private struct Anchor {
    let path: IndexPath
    let fraction: CGFloat
    let newest: Bool
  }
  private enum Position { case newest, item(Int) }
  private var resizeAnchor: Anchor?
  private var liveResizeAnchor: Anchor?
  private var pendingPosition: Position?
  private(set) var restoringViewport = false
  private var layingOut = false

  private func captureAnchor() -> Anchor? {
    guard let scroll = enclosingScrollView, let layout = collectionViewLayout,
      bounds.width > 120 else { return nil }
    let visible = scroll.contentView.bounds
    let candidates = (layout.layoutAttributesForElements(in: visible) ?? [])
      .filter { $0.representedElementCategory == .item && $0.frame.maxY > visible.minY }
    guard let item = candidates.min(by: {
      $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
    }), let path = item.indexPath else { return nil }
    let maximum = max(0, layout.collectionViewContentSize.height - visible.height)
    return Anchor(path: path, fraction: (visible.minY - item.frame.minY) / max(1, item.frame.height),
      newest: maximum > 0 && abs(visible.minY - maximum) <= 2)
  }
  override func viewWillStartLiveResize() {
    liveResizeAnchor = captureAnchor()
    visibleItems().forEach { ($0 as? MacCalendarCell)?.stopVideo() }
    super.viewWillStartLiveResize()
  }
  override func viewDidEndLiveResize() {
    super.viewDidEndLiveResize()
    layoutSubtreeIfNeeded()
    liveResizeAnchor = nil
  }
  override func setFrameSize(_ newSize: NSSize) {
    let changingWidth = abs(newSize.width - frame.width) > 0.5
    if changingWidth, resizeAnchor == nil {
      resizeAnchor = liveResizeAnchor ?? captureAnchor()
    }
    super.setFrameSize(newSize)
    if changingWidth { collectionViewLayout?.invalidateLayout(); needsLayout = true }
  }
  func place(_ item: Int?) {
    pendingPosition = item.map(Position.item) ?? .newest
    resizeAnchor = nil; liveResizeAnchor = nil
    needsLayout = true
    layoutSubtreeIfNeeded()
  }
  override func layout() {
    guard !layingOut else { return }
    layingOut = true; restoringViewport = true
    defer { layingOut = false; restoringViewport = false }
    super.layout()
    guard let scroll = enclosingScrollView, let layout = collectionViewLayout,
      bounds.width > 120, scroll.contentSize.height > 0 else { return }
    let height = max(scroll.contentSize.height, layout.collectionViewContentSize.height)
    if abs(frame.height - height) > 0.5 { super.setFrameSize(NSSize(width: frame.width, height: height)) }
    let maximum = max(0, layout.collectionViewContentSize.height - scroll.contentSize.height)
    var y: CGFloat?
    if let pendingPosition {
      switch pendingPosition {
      case .newest: y = maximum
      case let .item(index):
        y = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)).map {
          $0.frame.midY - scroll.contentSize.height / 2
        }
      }
      if y != nil { self.pendingPosition = nil }
    } else if let anchor = resizeAnchor {
      if anchor.newest { y = maximum }
      else {
        y = layout.layoutAttributesForItem(at: anchor.path).map { $0.frame.minY + anchor.fraction * $0.frame.height }
      }
    }
    resizeAnchor = nil
    if let y {
      let origin = CGPoint(x: 0, y: min(maximum, max(0, y)))
      if abs(scroll.contentView.bounds.minY - origin.y) > 0.5 {
        scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView)
        // The first AppKit pass materialized the previous viewport. Its clip
        // notification occurs inside our layout, so merely marking this view
        // dirty can be consumed by that same pass. Adopt the final viewport
        // now, before returning, with one native materialization pass.
        needsLayout = true
        super.layout()
      }
    }
  }
  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    guard let path = indexPathForItem(at: point) else { return }
    if event.clickCount >= 2 { open?(path, point) } else { select?(path, point) }
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 36 || event.charactersIgnoringModifiers == " " {
      if !event.isARepeat { openSelected?() }
      return
    }
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
    guard BackupEnvironment.usesPhotoLibrary else { return }
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
    let title = period.date.map {
      MacGridDateRange.periodTitle($0, period: kind == .years ? .year : .monthAndYear)
    } ?? period.title
    canvas.title.stringValue = title
    canvas.images.forEach { $0.image = nil; $0.asset = nil }
    for (index, label) in canvas.days.enumerated() {
      label.stringValue = kind == .months && index < assets.count
        ? (assets[index].creationDate?.formatted(.dateTime.day()) ?? "") : ""
    }
    canvas.count = assets.count; canvas.needsLayout = true
    view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
    view.setAccessibilityLabel(title)
    view.setAccessibilityIdentifier("library.period." + period.id)
    let expected = token
    let slots = MacCalendarGrid.monthCoverSlots(count: assets.count, mirrored: mirrored)
    let heroIndex = kind == .years ? 0 : (slots.indices.max { slots[$0].2 * slots[$0].3 < slots[$1].2 * slots[$1].3 } ?? 0)
    for (index, asset) in assets.enumerated() {
      requests.append(pipeline.request(asset, pixels: index == heroIndex ? 900 : 360) { [weak self] image, _ in
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
  private let pillBackground = MacTimelineReadingSurface(frame: .zero)
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
    let shadow = NSShadow(); shadow.shadowColor = DuckMedia.scrimTextShadowNSColor; shadow.shadowBlurRadius = 4
    for label in days {
      label.font = .systemFont(ofSize: 13, weight: .bold); label.textColor = DuckMedia.onMediaNSColor; label.shadow = shadow
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
      title.font = .systemFont(ofSize: 27, weight: .bold); title.textColor = DuckMedia.onMediaNSColor
      title.shadow = { let s = NSShadow(); s.shadowColor = DuckMedia.scrimTextShadowNSColor; s.shadowBlurRadius = 5; return s }()
    } else {
      title.font = .systemFont(ofSize: 20, weight: .bold); title.textColor = .labelColor
      title.shadow = nil
    }
    needsLayout = true
  }
  /// Cells on the six-column lattice: (column, row, columns, rows).
  static func lattice(_ count: Int, mirrored: Bool) -> [(Int, Int, Int, Int)] {
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
    if mirrored, count >= 3, count != 4 { cells = cells.map { (6 - $0.0 - $0.2, $0.1, $0.2, $0.3) } }
    return cells.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
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
    let cells = Self.lattice(min(count, 6), mirrored: mirrored)
    for (i, image) in images.enumerated() {
      guard i < cells.count else { image.isHidden = true; days[i].isHidden = true; continue }
      let (c, r, w, h) = cells[i]
      image.isHidden = false
      image.frame = CGRect(x: CGFloat(c) * (unit + gap), y: top + CGFloat(r) * (unit + gap),
        width: CGFloat(w) * unit + CGFloat(w - 1) * gap, height: CGFloat(h) * unit + CGFloat(h - 1) * gap)
      days[i].isHidden = false
      days[i].font = .systemFont(ofSize: w > 2 && h > 2 ? 17 : 13, weight: .bold)
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
  /// A chronological photo can appear in more than one slot while a stage
  /// face is narrower than the viewport. Geometry belongs to the slot;
  /// rendition requests and content keys still belong to the asset index.
  private struct Slot: Hashable {
    let row: Int
    let column: Int
    let index: Int
  }
  private struct Request {
    let token = UUID()
    var id = PHInvalidImageRequestID
  }
  private var layers: [Slot: CALayer] = [:]
  private var slotsByIndex: [Int: [Slot]] = [:]
  private var requests: [Int: Request] = [:]
  private var pool: [CALayer] = []
  var onDisplay: (() -> Void)?
  private var zoomColumns = 1, zoomLeading = 0
  private var zoomPin: CGFloat = 4
  private var tileKeys: [Int: String] = [:]
  /// Photos scale together; period text stays in the canvas at native size.
  private let zoomPhotos = CALayer()
  private let photoClip = CALayer()
  private let periodReading = CALayer()
  private var photoBottom: CGFloat?
  var photoContentLayer: CALayer { zoomPhotos }
  var photoClippingLayer: CALayer { photoClip }
  var periodReadingLayer: CALayer { periodReading }
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
    zoomPhotos.anchorPoint = .zero; zoomPhotos.actions = Self.actions
    photoClip.anchorPoint = .zero; photoClip.actions = Self.actions
    layer?.addSublayer(photoClip); photoClip.addSublayer(zoomPhotos)
    periodReading.anchorPoint = .zero; periodReading.actions = Self.actions
    layer?.addSublayer(periodReading)
  }
  // The canvas draws nothing itself; its tiles are sublayers.
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() {}
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  /// The content boundary stays in viewport coordinates while the mosaic's
  /// photo-only child scales. Reading pills remain siblings of this container.
  func setPhotoBottom(_ bottom: CGFloat?) {
    photoBottom = bottom
    if bottom == nil { photoClip.removeAnimation(forKey: "zoom.footerClip") }
    CATransaction.begin(); CATransaction.setDisableActions(true)
    photoClip.position = .zero
    photoClip.bounds = CGRect(x: 0, y: 0, width: bounds.width,
      height: min(bounds.height, max(0, bottom ?? bounds.height)))
    photoClip.masksToBounds = bottom != nil
    CATransaction.commit()
  }
  private func snap(_ value: CGFloat) -> CGFloat {
    let scale = window?.backingScaleFactor ?? 2
    return (value * scale).rounded() / scale
  }
  /// Fraction of drawn tiles that already show pixels.
  var loadedFraction: CGFloat {
    let visible = bounds.intersection(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
      height: max(0, (photoBottom ?? bounds.maxY) - bounds.minY)))
    let drawn = layers.values.filter { $0.frame.intersects(visible) }
    guard !drawn.isEmpty else { return 1 }
    return CGFloat(drawn.filter { $0.contents != nil }.count) / CGFloat(drawn.count)
  }
  var displayedImages: [Int: NSImage] {
    layers.reduce(into: [:]) { result, item in
      guard let contents = item.value.contents else { return }
      let cg = contents as! CGImage
      result[item.key.index] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
  }
  /// Input takeover resolves the actual shown copy, including columns beside
  /// the native row, rather than clamping the point to a different photo.
  func displayedTile(at point: CGPoint, visible: CGRect) -> (index: Int, frame: CGRect)? {
    func distance(_ rect: CGRect) -> CGFloat {
      let rect = rect.intersection(visible)
      return hypot(max(max(rect.minX - point.x, 0), point.x - rect.maxX),
        max(max(rect.minY - point.y, 0), point.y - rect.maxY))
    }
    guard let tile = layers.filter({ !$0.value.frame.intersection(visible).isEmpty }).min(by: {
      distance($0.value.frame) < distance($1.value.frame)
    }) else { return nil }
    return (tile.key.index, tile.value.frame)
  }
  func index(at point: CGPoint, columns: Int, origin: CGPoint, pitch: CGFloat, leading: Int = 0) -> Int? {
    guard columns > 0, pitch > 0, point.x >= origin.x, point.y >= origin.y else { return nil }
    let col = Int((point.x - origin.x) / pitch), row = Int((point.y - origin.y) / pitch)
    guard col < columns else { return nil }
    let index = row * columns + col - leading
    return index >= 0 && index < count ? index : nil
  }
  func render(columns: Int, origin: CGPoint, pitch: CGFloat, visible: CGRect, leading: Int = 0,
    pinTop: CGFloat? = nil, extendsRows: Bool = false) {
    guard count > 0, columns > 0, pitch > 0.5 else { reset(); return }
    zoomColumns = columns; zoomLeading = leading
    zoomPin = pinTop ?? visible.minY + 4
    let scale = window?.backingScaleFactor ?? 2
    let rowStart = max(0, Int(floor((visible.minY - origin.y) / pitch)) - 1)
    let rowEnd = min((count - 1 + leading) / columns, Int(ceil((visible.maxY - origin.y) / pitch)) + 1)
    guard rowStart <= rowEnd else { reset(); return }
    let firstColumn = Int(floor((visible.minX - origin.x) / pitch)) - 1
    let lastColumn = Int(ceil((visible.maxX - origin.x) / pitch)) + 1
    let colStart = extendsRows ? firstColumn : max(0, firstColumn)
    let colEnd = extendsRows ? lastColumn : min(columns - 1, lastColumn)
    var keep = Set<Slot>(), nextSlots: [Int: [Slot]] = [:]
    // Retain pixels even when the old slot leaves coverage and a different
    // chronological copy of the same asset enters it in this event.
    var retained: [Int: Any] = [:]
    for (slot, layer) in layers { if let image = layer.contents { retained[slot.index] = image } }
    CATransaction.begin(); CATransaction.setDisableActions(true)
    // Give the photo container a real display extent before it enters the
    // native collection. Its zero anchor keeps tile coordinates unchanged.
    periodReading.frame = bounds
    zoomPhotos.bounds = CGRect(origin: .zero, size: bounds.size)
    zoomPhotos.position = .zero
    setPhotoBottom(photoBottom)
    if colStart <= colEnd {
      for row in rowStart...rowEnd {
        let y0 = snap(origin.y + CGFloat(row) * pitch), y1 = snap(origin.y + CGFloat(row + 1) * pitch)
        for col in colStart...colEnd {
          let index = row * columns + col - leading
          guard index >= 0, index < count else { continue }
          let slot = Slot(row: row, column: col, index: index)
          keep.insert(slot); nextSlots[index, default: []].append(slot)
          let x0 = snap(origin.x + CGFloat(col) * pitch), x1 = snap(origin.x + CGFloat(col + 1) * pitch)
          let layer: CALayer
          if let existing = layers[slot] { layer = existing } else {
            layer = pool.popLast() ?? makeLayer()
            layer.contents = retained[index]
            zoomPhotos.addSublayer(layer)
            layers[slot] = layer
          }
          layer.frame = CGRect(x: x0, y: y0, width: max(0.5, x1 - x0), height: max(0.5, y1 - y0))
        }
      }
    }
    for slot in Array(layers.keys) where !keep.contains(slot) {
      if let layer = layers.removeValue(forKey: slot) {
        layer.removeFromSuperlayer(); layer.contents = nil
        if pool.count < 3000 { pool.append(layer) }
      }
    }
    slotsByIndex = nextSlots
    for index in Set(tileKeys.keys).union(requests.keys) where nextSlots[index] == nil {
      cancelRequest(at: index); tileKeys.removeValue(forKey: index)
    }
    for (index, slots) in nextSlots {
      let known = factAt?(index)
      let found = known == nil && tileKeys[index] == nil ? assetAt?(index) : nil
      guard let key = known?.key ?? tileKeys[index] ?? found.map(MacThumbnailTables.key) else { continue }
      if let previous = tileKeys[index], previous != key {
        cancelRequest(at: index)
        for slot in slots { layers[slot]?.contents = nil }
      }
      tileKeys[index] = key
      guard slots.contains(where: { layers[$0]?.contents == nil }), requests[index] == nil, let pipeline else { continue }
      let pixels = max(64, (pitch * scale).rounded(.up))
      let stored = MacThumbnailTables.image(key: key, pixels: pitch * scale)
      if let stored { for slot in slots where layers[slot]?.contents == nil { layers[slot]?.contents = stored.image } }
      if stored?.sharp != true, let asset = found ?? assetAt?(index) {
        let request = Request(); requests[index] = request
        let id = pipeline.request(asset, pixels: pixels, priority: .visible) { [weak self] image, _ in
          guard let self, self.requests[index]?.token == request.token, self.tileKeys[index] == key,
            let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
          CATransaction.begin(); CATransaction.setDisableActions(true)
          for slot in self.slotsByIndex[index] ?? [] { self.layers[slot]?.contents = cg }
          CATransaction.commit()
          self.onDisplay?()
          MacThumbnailTables.remember(asset, pixels: pitch * scale, image: cg)
        }
        if requests[index]?.token == request.token {
          if id == PHInvalidImageRequestID { requests.removeValue(forKey: index) }
          else { requests[index]?.id = id }
        } else if id != PHInvalidImageRequestID { pipeline.cancel(id) }
      }
    }
    renderPills(columns: columns, origin: origin, pitch: pitch, rows: rowStart...rowEnd, leading: leading,
      pin: zoomPin)
    CATransaction.commit()
  }
  private func cancelRequest(at index: Int) {
    if let request = requests.removeValue(forKey: index), request.id != PHInvalidImageRequestID {
      pipeline?.cancel(request.id)
    }
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
    let cacheKey = "\(Calendar.current.identifier)|\(Calendar.current.timeZone.identifier)|\(MacGridDateRange.applicationLocale.identifier)|\(key)"
    if let title = Self.titles[cacheKey] { return (key, title) }
    let title = MacGridDateRange.periodTitle(date, period: yearly ? .year : .monthAndYear)
    Self.titles[cacheKey] = title
    return (key, title)
  }
  private func pillPlacements(columns: Int, origin: CGPoint, pitch: CGFloat, rows: ClosedRange<Int>, leading: Int, pin: CGFloat) -> [(y: CGFloat, key: String, title: String)] {
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
    return placed
  }
  private func renderPills(columns: Int, origin: CGPoint, pitch: CGFloat, rows: ClosedRange<Int>, leading: Int, pin: CGFloat) {
    let placed = pillPlacements(columns: columns, origin: origin, pitch: pitch, rows: rows, leading: leading, pin: pin)
    let yearly = columns >= (MacLibraryDensity.overview.last ?? 40)
    var keep = Set<String>()
    let scale = window?.backingScaleFactor ?? 2
    for pill in placed {
      guard let image = Self.pillImage(pill.title, yearly: yearly, scale: scale) else { continue }
      keep.insert(pill.key)
      let layer: CALayer
      if let existing = pills[pill.key] { layer = existing } else {
        layer = CALayer(); layer.actions = Self.actions; layer.zPosition = 30
        periodReading.addSublayer(layer); pills[pill.key] = layer
      }
      layer.contents = image; layer.contentsScale = scale
      // Reading alignment belongs to the viewport, not the moving photo lattice.
      layer.frame = CGRect(x: bounds.minX + 12, y: pill.y, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
    for key in Array(pills.keys) where !keep.contains(key) { pills.removeValue(forKey: key)?.removeFromSuperlayer() }
  }
  /// The gapless lattice scales on one photo-only layer. Quantized target
  /// rectangles remain unchanged; period labels live outside this transform.
  func animateZoom(_ model: GridZoom.Settle, duration: CFTimeInterval, batch: MacGridAnimationBatch? = nil,
    origin: (CGFloat, CGPoint) -> CGPoint) {
    func frame(_ slot: Slot, _ p: CGFloat, _ f: CGPoint, snapped: Bool = true) -> CGRect {
      let o = origin(p, f)
      let x = o.x + CGFloat(slot.column) * p, y = o.y + CGFloat(slot.row) * p
      let s: (CGFloat) -> CGFloat = snapped ? snap : { $0 }
      return CGRect(x: s(x), y: s(y), width: s(x + p) - s(x), height: s(y + p) - s(y))
    }
    let ratio = model.pitch / model.targetPitch
    if let (index, tile) = layers.first {
      let from = frame(index, model.pitch, model.focus)
      let translation = CGPoint(x: from.minX - tile.frame.minX * ratio, y: from.minY - tile.frame.minY * ratio)
      // Quantized natural pitches have uniform edges. A fractional gesture
      // release can alternate tile widths; scaling those would move pixels at
      // takeover. Keep tile springs for that nonuniform case.
      let uniform = layers.allSatisfy { index, tile in
        let expected = frame(index, model.pitch, model.focus), target = tile.frame
        return abs(expected.minX - (translation.x + target.minX * ratio)) < 0.000001
          && abs(expected.minY - (translation.y + target.minY * ratio)) < 0.000001
          && abs(expected.width - target.width * ratio) < 0.000001
          && abs(expected.height - target.height * ratio) < 0.000001
      }
      if uniform {
        let base = frame(index, model.pitch, model.focus, snapped: false)
        let unit = frame(index, model.pitch + 1, model.focus, snapped: false)
        MacGridSpring.animateUniform(zoomPhotos, from: translation,
          derivative: CGPoint(x: unit.minX - base.minX - tile.frame.minX / model.targetPitch,
            y: unit.minY - base.minY - tile.frame.minY / model.targetPitch), model: model, duration: duration, batch: batch)
      } else {
        for (index, tile) in layers {
          let base = frame(index, model.pitch, model.focus, snapped: false)
          let unit = frame(index, model.pitch + 1, model.focus, snapped: false)
          MacGridSpring.animate(tile, from: frame(index, model.pitch, model.focus), to: tile.frame,
            derivative: CGRect(x: unit.minX - base.minX, y: unit.minY - base.minY,
              width: unit.width - base.width, height: unit.height - base.height), model: model, duration: duration, batch: batch)
        }
      }
    }
    var samples: [[String: CGPoint]] = [], titles: [String: String] = [:]
    for k in 0...72 {
      let pose = model.state(at: model.start + duration * Double(k) / 72)
      let o = origin(pose.pitch, pose.focus)
      let first = max(0, Int(floor(-o.y / pose.pitch)) - 1)
      let last = min((count - 1 + zoomLeading) / zoomColumns, Int(ceil((bounds.height - o.y) / pose.pitch)) + 1)
      var positions: [String: CGPoint] = [:]
      if first <= last {
        for pill in pillPlacements(columns: zoomColumns, origin: o, pitch: pose.pitch, rows: first...last, leading: zoomLeading, pin: zoomPin) {
          titles[pill.key] = pill.title; positions[pill.key] = CGPoint(x: bounds.minX + 12, y: pill.y)
        }
      }
      samples.append(positions)
    }
    let scale = window?.backingScaleFactor ?? 2
    for (key, title) in titles {
      guard let image = Self.pillImage(title, yearly: zoomColumns >= (MacLibraryDensity.overview.last ?? 40), scale: scale),
        let first = samples.lazy.compactMap({ $0[key] }).first else { continue }
      let layer: CALayer
      if let existing = pills[key] { layer = existing }
      else {
        layer = CALayer(); layer.actions = Self.actions; layer.zPosition = 30
        periodReading.addSublayer(layer); pills[key] = layer
      }
      layer.contents = image; layer.contentsScale = scale
      let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
      layer.frame = CGRect(origin: samples.last?[key] ?? first, size: size)
      layer.opacity = samples.last?[key] == nil ? 0 : 1
      let move = CAKeyframeAnimation(keyPath: "position")
      move.values = samples.map { NSValue(point: CGPoint(x: ($0[key] ?? first).x + size.width * layer.anchorPoint.x,
        y: ($0[key] ?? first).y + size.height * layer.anchorPoint.y)) }
      move.duration = duration; move.calculationMode = .linear
      move.beginTime = layer.convertTime(model.start, from: nil)
      MacGridAnimationBatch.schedule(move, on: layer, key: "zoom.pill", batch: batch)
      let visible = CAKeyframeAnimation(keyPath: "opacity")
      visible.values = samples.map { NSNumber(value: $0[key] == nil ? 0 : 1) }
      visible.duration = duration; visible.calculationMode = .discrete
      visible.beginTime = layer.convertTime(model.start, from: nil)
      MacGridAnimationBatch.schedule(visible, on: layer, key: "zoom.visibility", batch: batch)
    }
  }
  /// The destination mosaic keeps already displayed pixels while its own
  /// rendition requests finish, just as ordinary collection cells do.
  @discardableResult func retainDisplayedPixels(from other: MacDenseCanvas) -> Bool {
    guard count == other.count, zoomColumns == other.zoomColumns, zoomLeading == other.zoomLeading else { return false }
    var pixels: [Int: Any] = [:]
    for (slot, tile) in other.layers { if let image = tile.contents { pixels[slot.index] = image } }
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for (slot, tile) in layers where tile.contents == nil {
      if let key = tileKeys[slot.index], other.tileKeys[slot.index] == key { tile.contents = pixels[slot.index] }
    }
    let retained = layers.allSatisfy { slot, tile in
      guard tile.frame.intersects(visibleRect), pixels[slot.index] != nil else { return true }
      // A newer native rendition is authoritative; a changed content key
      // must not make an obsolete stage image a loading requirement.
      return tile.contents != nil || tileKeys[slot.index] != other.tileKeys[slot.index]
    }
    CATransaction.commit()
    return retained
  }
  func removeZoomAnimations() {
    MacGridSpring.remove(from: zoomPhotos)
    photoClip.removeAnimation(forKey: "zoom.footerClip")
    for layer in pills.values { layer.removeAnimation(forKey: "zoom.pill"); layer.removeAnimation(forKey: "zoom.visibility"); layer.opacity = 1 }
  }
  private static func pillImage(_ title: String, yearly: Bool, scale: CGFloat) -> CGImage? {
    let cacheKey = "\(yearly)|\(scale)|\(title)"
    if let cached = pillImages[cacheKey] { return cached }
    let text = NSMutableAttributedString(string: title, attributes: [
      .foregroundColor: DuckMedia.labelTextNSColor, .font: NSFont.systemFont(ofSize: 15, weight: .semibold)])
    if !yearly, let year = title.range(of: "[0-9]{4}年?", options: .regularExpression) {
      text.addAttribute(.foregroundColor, value: DuckMedia.labelTextSecondaryNSColor, range: NSRange(year, in: title))
    }
    let size = text.size()
    let pill = CGSize(width: ceil(size.width) + 20, height: 30)
    let image = NSImage(size: pill, flipped: false) { rect in
      DuckMedia.labelPlateNSColor.setFill()
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
    // Adjacent mosaic tiles share an edge. macOS enables edge antialiasing
    // by default, which exposes the background at fractional zoom scales.
    layer.allowsEdgeAntialiasing = false
    layer.edgeAntialiasingMask = []
    layer.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    return layer
  }
  func reset() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for index in Array(requests.keys) { cancelRequest(at: index) }
    for layer in layers.values {
      layer.removeFromSuperlayer(); layer.contents = nil
    }
    layers.removeAll(); slotsByIndex.removeAll(); tileKeys.removeAll()
    pills.values.forEach { $0.removeFromSuperlayer() }; pills.removeAll()
    photoClip.removeAnimation(forKey: "zoom.footerClip"); setPhotoBottom(nil)
    periodReading.removeAnimation(forKey: "zoom.readingFamily"); periodReading.opacity = 1
    CATransaction.commit()
  }
}

/// A transition tile is layers only. The stage resizes tiles every frame; a cell
/// view there re-rasterized its SF Symbol and text badges on each frame, which
/// held the main thread for most of a zoom step. Here the content is laid out
/// once at the reference size and scaled by the GPU through `sublayerTransform`.
@MainActor final class MacZoomMediaTile: NSView, MacGridReadingTile {
  private(set) var displayedImage: NSImage?
  var onDisplay: (() -> Void)?
  private let content = CALayer()
  private let photo = CALayer()
  private let durationLayer = MacTextBadgeLayer(weight: .semibold, fill: DuckMedia.scrimDurationNSColor, radius: 5)
  private let mediaLayer = CALayer()
  private let outline = CALayer()
  private var reference: CGFloat = 1
  private var fitted = false
  private var aspect: CGFloat = 1
  private weak var pipeline: ThumbnailPipeline?
  private var request = PHInvalidImageRequestID
  private var readingRect: CGRect?
  private weak var readingHost: NSView?
  var readingMarkLayers: [CALayer] { [durationLayer, mediaLayer] }
  func setReadingHost(_ host: NSView?) {
    guard readingHost !== host else { return }
    CATransaction.begin(); CATransaction.setDisableActions(true)
    if host == nil { MacGridReadingMarks.remove(from: readingMarkLayers) }
    readingHost = host
    for mark in readingMarkLayers {
      mark.removeFromSuperlayer(); (host?.layer ?? layer)?.addSublayer(mark)
    }
    layout()
    CATransaction.commit()
  }
  func setReadingRect(_ visible: CGRect?) {
    readingRect = visible
    if visible == nil { MacGridReadingMarks.remove(from: readingMarkLayers) }
    layout()
  }
  func readingMarkPoses(in frame: CGRect, visible: CGRect?) -> [MacGridReadingMarks.Pose] {
    let f = photo.frame.applying(CGAffineTransform(scaleX: frame.width / reference, y: frame.height / reference))
    let width = max(1, min(f.width - 16, max(42, durationLayer.textWidth + 12)))
    return MacGridReadingMarks.poses([
      .init(layer: durationLayer, frame: CGRect(x: f.maxX - width - 7, y: f.minY + 7, width: width, height: 18),
        glyphWidth: durationLayer.textWidth, trailing: true),
      .init(layer: mediaLayer, frame: CGRect(x: f.minX + 7, y: f.minY + 7, width: 18, height: 18)),
    ], photo: f, tile: frame, visible: visible)
  }
  private static var symbols: [String: CGImage] = [:]
  private static let still: [String: CAAction] = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(),
    "frame": NSNull(), "hidden": NSNull(), "transform": NSNull(),
    "contentsScale": NSNull(), "backgroundColor": NSNull(), "cornerRadius": NSNull(), "sublayerTransform": NSNull(), "opacity": NSNull()]
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
    photo.backgroundColor = DuckRole.mediaPlaceholderNSColor.cgColor
    content.addSublayer(photo)
    durationLayer.isHidden = true
    layer?.addSublayer(durationLayer)
    mediaLayer.contentsGravity = .resizeAspect; mediaLayer.isHidden = true
    layer?.addSublayer(mediaLayer)
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
    durationLayer.scale = scale
    durationLayer.text = asset.mediaType == .video ? videoDurationLabel(asset.duration) : ""
    durationLayer.isHidden = asset.mediaType != .video
    let symbol = asset.burstIdentifier != nil ? "square.stack" : asset.mediaSubtypes.contains(.photoLive) ? "livephoto" : nil
    mediaLayer.contents = symbol.flatMap { Self.symbol($0, scale: scale) }
    mediaLayer.isHidden = symbol == nil
    outline.isHidden = !selected
    arrange()
    needsLayout = true
    if let stored = MacThumbnailTables.placeholder(asset) { photo.contents = stored }
    request = pipeline.request(asset, pixels: pixels, contentMode: .aspectFill) { [weak self] image, _ in
      guard let self, let image else { return }
      self.show(image)
    }
  }
  func show(_ image: NSImage) {
    displayedImage = image
    photo.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    onDisplay?()
  }
  func cancel() {
    pipeline?.cancel(request); request = PHInvalidImageRequestID
    setReadingHost(nil); setReadingRect(nil)
  }
  private static func symbol(_ name: String, scale: CGFloat) -> CGImage? {
    if let cached = symbols[name] { return cached }
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold).applying(.init(paletteColors: [DuckMedia.onMediaNSColor]))) else { return nil }
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
  }
  /// Images scale independently of reading-size duration and media marks.
  override func layout() {
    super.layout()
    let k = bounds.width / reference
    CATransaction.begin(); CATransaction.setDisableActions(true)
    content.position = .zero
    content.transform = CATransform3DMakeScale(k, bounds.height / reference, 1)
    let poses = readingMarkPoses(in: frame, visible: readingRect)
    if let host = readingHost {
      MacGridReadingMarks.apply(MacGridReadingMarks.hosted(poses, tile: frame,
        visible: readingRect ?? host.bounds, height: host.bounds.height))
    } else { MacGridReadingMarks.apply(poses) }
    CATransaction.commit()
  }
}

extension MacSourceZoomTile: MacGridReadingTile {
  var readingMarkLayers: [CALayer] { cell.zoomReadingLayers }
  func setReadingRect(_ visible: CGRect?) { cell.setZoomReadingRect(visible, frame: frame) }
  func setReadingHost(_ host: NSView?) { cell.setZoomReadingHost(host) }
  func readingMarkPoses(in frame: CGRect, visible: CGRect?) -> [MacGridReadingMarks.Pose] {
    cell.zoomReadingPoses(in: frame, visible: visible)
  }
}

/// Completion belongs to a visible stage animation, rather than a transaction
/// containing virtualized tile layers that AppKit can suspend off screen.
@MainActor private final class MacGridAnimationEnd: NSObject, CAAnimationDelegate {
  private let done: () -> Void
  private let started: ((CFTimeInterval) -> Void)?
  private weak var timingLayer: CALayer?
  init(timingLayer: CALayer? = nil,
    started: ((CFTimeInterval) -> Void)? = nil, _ done: @escaping () -> Void) {
    self.timingLayer = timingLayer
    self.started = started; self.done = done
  }
  nonisolated func animationDidStart(_ anim: CAAnimation) {
    let resolved = anim.beginTime, delivered = CACurrentMediaTime()
    Task { @MainActor in
      let start = resolved > 0 ? self.timingLayer?.convertTime(resolved, to: nil) ?? resolved : delivered
      self.started?(start)
    }
  }
  nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
    guard flag else { return }
    Task { @MainActor in
      self.done()
    }
  }
}

/// A release prepares every native layout and animation before choosing its
/// common clock. Expensive tile preparation must not consume visible spring time.
@MainActor final class MacGridAnimationBatch {
  private struct Entry {
    let layer: CALayer
    let animation: CAAnimation
    let key: String
  }
  private var entries: [Entry] = []
  static func schedule(_ animation: CAAnimation, on layer: CALayer, key: String,
    batch: MacGridAnimationBatch?) {
    if let batch { batch.entries.append(Entry(layer: layer, animation: animation, key: key)) }
    else { layer.add(animation, forKey: key) }
  }
  func install() {
    for entry in entries {
      // Core Animation resolves one transaction's zero starts at commitment,
      // after host layout, resource preparation and serialization have finished.
      entry.animation.beginTime = 0
      // The model already contains the destination. Retain the release origin
      // until the system's resolved start instead of exposing that destination.
      entry.animation.fillMode = .backwards
      entry.layer.add(entry.animation, forKey: entry.key)
    }
    entries.removeAll()
  }
}

@MainActor enum MacGridSpring {
  private static let geometryKeys = ["position.x", "position.y", "bounds.size.width", "bounds.size.height", "transform.scale.x", "transform.scale.y"]
  private static func geometry(_ view: NSView) -> [(CALayer, [CGFloat])] {
    var seen = Set<ObjectIdentifier>()
    func layers(_ layer: CALayer) -> [(CALayer, [CGFloat])] {
      guard seen.insert(ObjectIdentifier(layer)).inserted else { return [] }
      return [(layer, geometryKeys.map { CGFloat((layer.value(forKeyPath: $0) as? NSNumber)?.doubleValue ?? 0) })]
        + (layer.sublayers ?? []).flatMap(layers)
    }
    func visit(_ view: NSView) -> [(CALayer, [CGFloat])] {
      // AppKit can attach a subview's backing layer at the next commit. Include
      // it now: otherwise its photo jumps straight to the destination size
      // while only the enclosing tile carries the release spring.
      (view.layer.map(layers) ?? []) + view.subviews.flatMap(visit)
    }
    return visit(view)
  }
  /// Source cells have native-size marks, unlike the reference-scaled media
  /// tiles. Measure their two layouts at release and spring geometry only;
  /// fixed-size text and badge bounds then remain fixed throughout the move.
  static func animate(_ view: NSView, from: CGRect, derivative: CGRect, model: GridZoom.Settle,
    duration: CFTimeInterval, batch: MacGridAnimationBatch? = nil) {
    guard let root = view.layer else { return }
    let target = view.frame
    func layout(at frame: CGRect) {
      view.frame = frame; view.needsLayout = true; view.layoutSubtreeIfNeeded()
      // NSViewController's layout notification can be deferred until AppKit's
      // next pass. Measure the photo and native marks at this pose too, rather
      // than measuring a child still laid out at the previous density.
      if let source = view as? MacSourceZoomTile { source.cell.viewDidLayout() }
    }
    layout(at: from)
    let initial = Dictionary(uniqueKeysWithValues: geometry(view).map { (ObjectIdentifier($0.0), $0.1) })
    layout(at: target)
    for (layer, end) in geometry(view) {
      guard let start = initial[ObjectIdentifier(layer)] else { continue }
      for (i, key) in geometryKeys.enumerated() {
        let vertical = key == "position.y" || key == "bounds.size.height" || key == "transform.scale.y"
        let travel = vertical ? target.height - from.height : target.width - from.width
        let sizeSlope = vertical ? derivative.height : derivative.width
        var slope = abs(travel) > 0.000001 ? (end[i] - start[i]) / travel * sizeSlope : 0
        if layer === root {
          if key == "position.x" { slope = derivative.minX + derivative.width * root.anchorPoint.x }
          if key == "position.y" { slope = derivative.minY + derivative.height * root.anchorPoint.y }
          if key == "bounds.size.width" { slope = derivative.width }
          if key == "bounds.size.height" { slope = derivative.height }
        }
        add(to: layer, key: key, from: start[i], to: end[i], speed: slope * model.velocity,
          start: model.start, duration: duration, batch: batch)
      }
    }
  }
  private static func add(to layer: CALayer, key: String, from start: CGFloat, to end: CGFloat,
    speed: CGFloat, start time: CFTimeInterval, duration: CFTimeInterval, batch: MacGridAnimationBatch?) {
    let distance = end - start
    guard abs(distance) > 0.000001 || abs(speed) > 0.000001 else { return }
    func spring(_ from: CGFloat, _ to: CGFloat, _ velocity: CGFloat, additive: Bool = false) -> CASpringAnimation {
      let move = CASpringAnimation(keyPath: key)
      move.mass = 1; move.stiffness = GridZoom.settleOmega * GridZoom.settleOmega
      move.damping = 2 * GridZoom.settleOmega
      move.initialVelocity = velocity; move.fromValue = from; move.toValue = to
      move.beginTime = layer.convertTime(time, from: nil)
      move.duration = duration; move.isAdditive = additive
      return move
    }
    if abs(distance) > 0.000001 {
      MacGridAnimationBatch.schedule(spring(start, end, speed / distance), on: layer, key: "zoom." + key, batch: batch)
    } else {
      // Two additive responses cancel their displacement but retain the
      // carried velocity when focus travel cancels pitch travel at an endpoint.
      MacGridAnimationBatch.schedule(spring(1, 0, -speed, additive: true), on: layer, key: "zoom." + key, batch: batch)
      MacGridAnimationBatch.schedule(spring(-1, 0, 0, additive: true), on: layer, key: "zoom.velocity." + key, batch: batch)
    }
  }
  static func animate(_ layer: CALayer, from: CGRect, to: CGRect, derivative d: CGRect,
    model: GridZoom.Settle, duration: CFTimeInterval, batch: MacGridAnimationBatch? = nil) {
    let anchor = layer.anchorPoint
    let values: [(String, CGFloat, CGFloat, CGFloat)] = [
      ("position.x", layer.position.x + from.minX - to.minX + (from.width - to.width) * anchor.x,
        layer.position.x, d.minX + d.width * anchor.x),
      ("position.y", layer.position.y + from.minY - to.minY + (from.height - to.height) * anchor.y,
        layer.position.y, d.minY + d.height * anchor.y),
      ("transform.scale.x", from.width / to.width, 1, d.width / to.width),
      ("transform.scale.y", from.height / to.height, 1, d.height / to.height),
    ]
    for (key, start, end, slope) in values {
      add(to: layer, key: key, from: start, to: end, speed: slope * model.velocity,
        start: model.start, duration: duration, batch: batch)
    }
  }
  /// A zero-anchor content layer maps the measured target rectangles to the
  /// measured release rectangles. Translation includes edge quantization;
  /// only the pitch derivative contributes release velocity.
  static func animateUniform(_ layer: CALayer, from: CGPoint, derivative: CGPoint,
    model: GridZoom.Settle, duration: CFTimeInterval, batch: MacGridAnimationBatch? = nil) {
    let ratio = model.pitch / model.targetPitch
    for (key, from, speed) in [
      ("position.x", from.x, derivative.x * model.velocity),
      ("position.y", from.y, derivative.y * model.velocity),
      ("transform.scale.x", ratio, model.velocity / model.targetPitch),
      ("transform.scale.y", ratio, model.velocity / model.targetPitch),
    ] {
      add(to: layer, key: key, from: from, to: key.hasPrefix("position") ? 0 : 1,
        speed: speed, start: model.start, duration: duration, batch: batch)
    }
  }
  static func remove(from view: NSView) {
    for (layer, _) in geometry(view) { remove(from: layer) }
  }
  static func remove(from layer: CALayer?) {
    for key in geometryKeys {
      layer?.removeAnimation(forKey: "zoom." + key); layer?.removeAnimation(forKey: "zoom.velocity." + key)
    }
    for child in layer?.sublayers ?? [] { remove(from: child) }
  }
}

@MainActor final class MacGridPhotoPlane: NSView {
  override var isFlipped: Bool { true }
  override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Reading families hand off at the photo mixture's midpoint. Ordinary marks
/// share a family across grid densities; each overview has its own vocabulary.
@MainActor enum MacGridReadingFamily {
  static func family(_ columns: Int) -> Int { MacLibraryDensity.isDense(columns) ? columns : 0 }
  static func weights(_ weights: [Int: CGFloat]) -> [Int: CGFloat] {
    weights.reduce(into: [:]) { $0[family($1.key), default: 0] += $1.value }
  }
  static func gate(_ weight: CGFloat) -> Float {
    // A computed half-weight crossing must remain exactly silent after rounding.
    weight <= 0.5 + 0.0000001 ? 0 : Float(min(1, 2 * weight - 1))
  }
  /// Cross-family mixtures are linear. Including every half-weight crossing
  /// keeps distinct reading families disjoint between CA keyframes as well.
  static func keyTimes(from: [Int: CGFloat], to: [Int: CGFloat]) -> [CGFloat] {
    let a = weights(from), b = weights(to)
    var times = Set((0...48).map { CGFloat($0) / 48 })
    for family in Set(a.keys).union(b.keys) {
      let first = a[family, default: 0], last = b[family, default: 0]
      guard abs(last - first) > 0.000001 else { continue }
      let crossing = (0.5 - first) / (last - first)
      if crossing > 0, crossing < 1 { times.insert(crossing) }
    }
    return times.sorted()
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
  var seedImages: [Int: NSImage] = [:]
  var releaseTile: ((NSView) -> Void)?
  var referenceSide: (Int) -> CGFloat = { _ in 1 }
  var groupedGeometry: ((Int) -> LibraryTimelineGeometry)?
  var groupedIntroduction: ((Int) -> AnyView?)?
  var groupedIdentity: ((Int) -> AnyView?)?
  var groupedRevision = ""
  var groupedPinTop: CGFloat = 0
  var denseAsset: ((Int) -> PHAsset?)?
  var denseFact: ((Int) -> MacThumbnailTables.Fact?)?
  var thumbnails: ThumbnailPipeline?
  var densePinTop: CGFloat = 6
  private func faceGap(_ columns: Int) -> CGFloat { MacLibraryDensity.isDense(columns) ? 0 : 2 }
  private final class Face: NSView {
    let columns: Int
    /// Natural-size content point under the shared viewport focus. Each face
    /// retains its own point when input takes over a partially blended pose.
    var referenceFocus: CGPoint = .zero
    var gapFraction: CGPoint = .zero
    /// Empty slots before the first photo in this density.
    var leading = 0
    var canvas: MacDenseCanvas?
    var photoMask: CALayer?
    let photoPlane = MacGridPhotoPlane(frame: .zero)
    let readingPlane = NSView(frame: .zero)
    var tiles: [String: (Int,NSView)] = [:]
    var weight: CGFloat = 0
    override var isFlipped: Bool { true }
    init(columns: Int) {
      self.columns = columns; super.init(frame: .zero); wantsLayer = true
      readingPlane.wantsLayer = true
      addSubview(photoPlane); addSubview(readingPlane)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }
  private var faces: [Int: Face] = [:]
  private var groupedReferences: [Int: CGPoint] = [:]
  private struct FooterReference {
    var focus: CGPoint
    let pitch: CGFloat
    let y: CGFloat
    let leading: Int
    let gapFraction: CGPoint
  }
  private var footerReferences: [Int: FooterReference] = [:]
  private var footerColumns: [Int] = []
  private weak var footerLabel: NSTextField?
  /// Reading motion has its own zero-velocity release. Photo pitch velocity
  /// must not move a label whose release endpoints are identical.
  private var footerRelease: GridZoom.Settle?
  private var footerTrackingOffset: CGFloat = 0
  private var readingCorrections: [ObjectIdentifier: MacGridReadingMarks.Correction] = [:]
  private var releaseReadingCorrections: [ObjectIdentifier: MacGridReadingMarks.Correction] = [:]
  /// Section text belongs to the stage, independent of the photo crossfade.
  private var headers: [MacTimelineCaption.ID: MacGridSectionHeader] = [:]
  private var order: [Int] = []
  private var blend: GridZoom.Blend?
  private var blendWait: DispatchWorkItem?
  private var blendGeneration = 0
  private var blendEnd: MacGridAnimationEnd?
  private var settling: GridZoom.Settle?
  private var settleAwaitingStart = false
  private var settleCompletion: (() -> Void)?
  private var settleGeneration = 0
  private var settleLanded = false
  private var settleEnd: MacGridAnimationEnd?
  private var coverage: [(pitch: CGFloat, focus: CGPoint)] = []
  private var settleDuration: CFTimeInterval = 0
  private(set) var frozenPitchVelocity: CGFloat = 0
  /// Outgoing faces stay opaque until the shown face has most of its pixels,
  /// bounded so cloud-only media cannot hold a crossfade indefinitely.
  static let pixelWait: CFTimeInterval = GridZoom.pixelWait
  /// A face fades in over this long when it first becomes the previewed density.
  static let fadeDuration: CFTimeInterval = GridZoom.gridFadeDuration
  override var isFlipped: Bool { true }
  var isBlending: Bool { blend != nil }
  init(count: Int,anchor: Int,fraction: CGPoint,columns: Int,pitch: CGFloat,focus: CGPoint) {
    self.count = count; self.anchor = anchor; self.fraction = fraction
    self.pitch = pitch; self.focus = focus; shown = columns
    super.init(frame: .zero); wantsLayer = true; layer?.masksToBounds = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance(); updateBackground()
  }
  private func updateBackground() {
    // Resolve after attachment in the inherited appearance. The backing-layer
    // background remains behind the photo and caption subviews.
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = DuckRole.backgroundNSColor.cgColor
    }
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  /// Preserve the original native label while the collection is hidden. The
  /// bounded density metadata is prepared once, not from animation callbacks.
  func attachFooter(_ label: NSTextField, columns: [Int],
    layout: (Int) -> (focus: CGPoint, y: CGFloat, leading: Int)?) {
    guard footerLabel == nil else { return }
    for columns in columns {
      guard let value = layout(columns) else { continue }
      let face = faces[columns]
      footerReferences[columns] = FooterReference(focus: face?.referenceFocus ?? value.focus,
        pitch: naturalPitch(columns), y: value.y, leading: value.leading,
        gapFraction: face?.gapFraction ?? fraction)
    }
    footerColumns = footerReferences.keys.sorted {
      footerReferences[$0]!.pitch > footerReferences[$1]!.pitch
    }
    footerLabel = label
    label.wantsLayer = true
    addSubview(label)
    renderFooter()
  }
  func ownsFooter(_ label: NSTextField) -> Bool { footerLabel === label }
  func detachFooter() {
    footerLabel?.layer?.removeAnimation(forKey: "zoom.footer")
    footerLabel?.removeFromSuperview(); footerLabel = nil
    footerReferences.removeAll(); footerColumns.removeAll()
    footerRelease = nil; footerTrackingOffset = 0
    readingCorrections.removeAll(); releaseReadingCorrections.removeAll()
    setPhotoBottom(nil)
  }
  private func footerY(pitch: CGFloat, focus: CGPoint) -> CGFloat? {
    guard let first = footerColumns.first, let last = footerColumns.last,
      let high = footerReferences[first], let low = footerReferences[last] else { return nil }
    if pitch >= high.pitch { return focus.y + (high.y - high.focus.y) * pitch / high.pitch }
    if pitch <= low.pitch { return focus.y + (low.y - low.focus.y) * pitch / low.pitch }
    for (a, b) in zip(footerColumns, footerColumns.dropFirst()) {
      guard let from = footerReferences[a], let to = footerReferences[b],
        pitch <= from.pitch, pitch >= to.pitch else { continue }
      let t = (from.pitch - pitch) / max(0.001, from.pitch - to.pitch)
      return focus.y + (from.y - from.focus.y) * (1 - t) + (to.y - to.focus.y) * t
    }
    return nil
  }
  private func renderFooter() {
    guard let label = footerLabel, let y = footerY(pitch: pitch, focus: focus) else {
      setPhotoBottom(nil); return
    }
    label.frame = CGRect(x: 0, y: y + footerTrackingOffset, width: bounds.width, height: label.frame.height)
    setPhotoBottom(label.frame.minY - 30)
  }
  private var photoVisibleRect: CGRect {
    CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
      height: min(bounds.height, max(0, footerLabel.map { $0.frame.minY - 30 } ?? bounds.height)))
  }
  private func setPhotoBottom(_ bottom: CGFloat?) {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    for face in faces.values {
      if let canvas = face.canvas { canvas.setPhotoBottom(bottom); continue }
      let visible = bottom.map { CGRect(x: 0, y: 0, width: bounds.width, height: min(bounds.height, max(0, $0))) }
      for (_, tile) in face.tiles.values {
        if let reading = tile as? MacGridReadingTile {
          reading.setReadingHost(bottom == nil ? nil : face.readingPlane)
          reading.setReadingRect(visible)
          if let visible, !readingCorrections.isEmpty {
            let poses = reading.readingMarkLayers.map { MacGridReadingMarks.Pose(layer: $0, frame: $0.frame, opacity: $0.opacity) }
            MacGridReadingMarks.apply(MacGridReadingMarks.corrected(poses, corrections: readingCorrections,
              weight: 1, visible: visible, height: bounds.height))
          }
        }
      }
      guard let bottom else {
        face.photoMask?.removeAnimation(forKey: "zoom.footerClip")
        face.photoPlane.layer?.mask = nil; face.photoMask = nil
        continue
      }
      let mask: CALayer
      if let existing = face.photoMask { mask = existing } else {
        mask = CALayer(); mask.anchorPoint = .zero; mask.position = .zero
        // design-exception: An alpha-only clipping mask; its RGB is never rendered.
        mask.backgroundColor = NSColor.white.cgColor
        face.photoMask = mask; face.photoPlane.layer?.mask = mask
      }
      mask.bounds = CGRect(x: 0, y: 0, width: bounds.width,
        height: min(bounds.height, max(0, bottom)))
    }
  }
  private func animateFooter(duration: CFTimeInterval, batch: MacGridAnimationBatch? = nil) {
    guard let label = footerLabel, let layer = label.layer, let model = footerRelease else { return }
    let move = CAKeyframeAnimation(keyPath: "position.y")
    let positions: [CGFloat] = (0...72).map { step in
      step == 72 ? model.targetPitch
        : model.state(at: model.start + duration * Double(step) / 72).pitch
    }
    move.values = positions.map { NSNumber(value: Double(layer.position.y + $0 - label.frame.minY)) }
    move.duration = duration; move.calculationMode = .linear
    move.beginTime = layer.convertTime(model.start, from: nil)
    MacGridAnimationBatch.schedule(move, on: layer, key: "zoom.footer", batch: batch)
    for face in faces.values {
      guard let clip = face.canvas?.photoClippingLayer ?? face.photoMask else { continue }
      let boundary = CAKeyframeAnimation(keyPath: "bounds.size.height")
      boundary.values = positions.map { NSNumber(value: Double(min(bounds.height, max(0, $0 - 30)))) }
      boundary.duration = duration; boundary.calculationMode = .linear
      boundary.beginTime = clip.convertTime(model.start, from: nil)
      MacGridAnimationBatch.schedule(boundary, on: clip, key: "zoom.footerClip", batch: batch)
      guard let photoModel = settling else { continue }
      for (key, (_, tile)) in face.tiles {
        guard let reading = tile as? MacGridReadingTile else { continue }
        let samples = positions.enumerated().map { step, y -> [MacGridReadingMarks.Pose] in
          let pose = photoModel.state(at: photoModel.start + duration * Double(step) / 72)
          let frame = step == 72 ? tile.frame
            : tileFrame(face, key: key, pitch: pose.pitch, focus: pose.focus) ?? tile.frame
          let visible = CGRect(x: 0, y: 0, width: bounds.width, height: min(bounds.height, max(0, y - 30)))
          let hosted = MacGridReadingMarks.hosted(reading.readingMarkPoses(in: frame, visible: visible),
            tile: frame, visible: visible, height: bounds.height)
          let elapsed = CGFloat(duration * Double(step) / 72), w = GridZoom.settleOmega
          let remaining = step == 72 ? 0 : (1 + w * elapsed) * exp(-w * elapsed)
          return MacGridReadingMarks.corrected(hosted, corrections: releaseReadingCorrections,
            weight: remaining, visible: visible, height: bounds.height)
        }
        MacGridReadingMarks.animate(samples, start: model.start, duration: duration, batch: batch)
      }
    }
  }
  func ensureFace(_ columns: Int,opacity: CGFloat,leading: Int = 0) {
    guard faces[columns] == nil else { return }
    let face = Face(columns: columns)
    face.leading = leading
    face.gapFraction = footerReferences[columns]?.gapFraction ?? fraction
    face.referenceFocus = initialReference(columns: columns, leading: leading)
    face.weight = opacity; face.alphaValue = opacity
    // New faces stack above older faces but stay below the shared captions.
    if let caption = subviews.first(where: { $0 is MacGridSectionHeader || $0 === footerLabel }) {
      addSubview(face, positioned: .below, relativeTo: caption)
    } else { addSubview(face) }
    faces[columns] = face; order.append(columns)
    render()
  }
  /// Hit identity comes from the displayed overview, including translated
  /// chronological copies outside its canonical native columns.
  func overviewPhoto(at point: CGPoint) -> (index: Int, frame: CGRect)? {
    guard photoVisibleRect.contains(point), let canvas = faces[shown]?.canvas else { return nil }
    return canvas.displayedTile(at: point, visible: photoVisibleRect)
  }
  /// Moves the shared focus to a viewport point without moving any pixel, and
  /// adopts the tile under it as the anchor on the shown density.
  func reanchor(to point: CGPoint) {
    if settling != nil { freeze() }
    guard let shownFace = faces[shown], count > 0 else { return }
    let readingY = footerLabel?.frame.minY
    let visiblePhotos = photoVisibleRect
    let nextAnchor: Int, nextFraction: CGPoint
    if let geometry = groupedGeometry?(shown), !geometry.items.isEmpty {
      let scale = pitch / naturalPitch(shown)
      let content = CGPoint(x: shownFace.referenceFocus.x + (point.x - focus.x) / scale,
        y: shownFace.referenceFocus.y + (point.y - focus.y) / scale)
      let nearby = geometry.visibleItems(in: CGRect(
        x: shownFace.referenceFocus.x + (visiblePhotos.minX - focus.x) / scale,
        y: shownFace.referenceFocus.y + (visiblePhotos.minY - focus.y) / scale,
        width: visiblePhotos.width / scale, height: visiblePhotos.height / scale))
      func visibleFrame(_ index: Int) -> CGRect {
        let rect = geometry.items[index]
        return CGRect(x: focus.x + (rect.minX - shownFace.referenceFocus.x) * scale,
          y: focus.y + (rect.minY - shownFace.referenceFocus.y) * scale,
          width: rect.width * scale, height: rect.height * scale).intersection(visiblePhotos)
      }
      let candidates = nearby.filter { !visibleFrame($0).isEmpty }
      func distance(_ index: Int) -> CGFloat {
        let rect = visibleFrame(index)
        return hypot(max(max(rect.minX - point.x, 0), point.x - rect.maxX),
          max(max(rect.minY - point.y, 0), point.y - rect.maxY))
      }
      nextAnchor = candidates.min { distance($0) < distance($1) } ?? anchor
      let rect = geometry.items[nextAnchor]
      nextFraction = CGPoint(x: min(1, max(0, (content.x - rect.minX) / rect.width)),
        y: min(1, max(0, (content.y - rect.minY) / rect.height)))
      // Natural caption positions use the same references as their photo faces.
      // Linear pitch interpolation has sum(weight * naturalPitch) == pitch,
      // so this translation preserves captions as well as all visible photos.
      for columns in MacLibraryDensity.grid { _ = groupedReference(columns) }
    } else if let hit = shownFace.tiles.values.filter({ !$0.1.frame.intersection(visiblePhotos).isEmpty }).min(by: { a, b in
      func distance(_ rect: CGRect) -> CGFloat {
        let rect = rect.intersection(visiblePhotos)
        return hypot(max(max(rect.minX - point.x, 0), point.x - rect.maxX),
          max(max(rect.minY - point.y, 0), point.y - rect.maxY))
      }
      return distance(a.1.frame) < distance(b.1.frame)
    }) {
      // A scaled face can show chronological copies outside its native column
      // range. Keep the displayed copy's identity and in-photo point.
      nextAnchor = hit.0
      let rect = hit.1.frame
      nextFraction = CGPoint(x: min(1, max(0, (point.x - rect.minX) / max(1, rect.width))),
        y: min(1, max(0, (point.y - rect.minY) / max(1, rect.height))))
    } else if let tile = shownFace.canvas?.displayedTile(at: point, visible: visiblePhotos) {
      nextAnchor = tile.index
      nextFraction = CGPoint(x: min(1, max(0, (point.x - tile.frame.minX) / max(1, tile.frame.width))),
        y: min(1, max(0, (point.y - tile.frame.minY) / max(1, tile.frame.height))))
    } else {
      // No currently visible photo can adopt input from an empty clipped area.
      nextAnchor = anchor; nextFraction = fraction
    }
    for columns in Array(groupedReferences.keys) {
      let scale = pitch / naturalPitch(columns)
      if let reference = groupedReferences[columns] {
        groupedReferences[columns] = GridZoom.reanchored(faceFocus: reference,
          stageFocus: focus, to: point, scale: scale)
      }
    }
    for columns in Array(footerReferences.keys) {
      guard var reference = footerReferences[columns] else { continue }
      reference.focus = GridZoom.reanchored(faceFocus: reference.focus,
        stageFocus: focus, to: point, scale: pitch / reference.pitch)
      footerReferences[columns] = reference
    }
    for face in faces.values {
      let scale = pitch / naturalPitch(face.columns)
      face.referenceFocus = GridZoom.reanchored(faceFocus: face.referenceFocus,
        stageFocus: focus, to: point, scale: scale)
    }
    anchor = nextAnchor; fraction = nextFraction; focus = point
    if let readingY, let geometricY = footerY(pitch: pitch, focus: focus) {
      footerTrackingOffset = readingY - geometricY
    }
    render()
  }
  private func naturalPitch(_ columns: Int) -> CGFloat {
    max(1, referenceSide(columns)) + faceGap(columns)
  }
  private func groupedReference(_ columns: Int) -> CGPoint? {
    if let point = groupedReferences[columns] { return point }
    guard let geometry = groupedGeometry?(columns), geometry.items.indices.contains(anchor) else { return nil }
    let rect = geometry.items[anchor]
    let point = CGPoint(x: rect.minX + fraction.x * rect.width, y: rect.minY + fraction.y * rect.height)
    groupedReferences[columns] = point
    return point
  }
  private func initialReference(columns: Int, leading: Int) -> CGPoint {
    if let reference = footerReferences[columns], reference.leading == leading { return reference.focus }
    if let point = groupedReference(columns) { return point }
    let pitch = naturalPitch(columns), gap = faceGap(columns), slot = anchor + leading
    return CGPoint(x: (gap == 0 ? 0 : 2) + CGFloat(slot % columns) * pitch + fraction.x * (pitch - gap),
      y: 4 + CGFloat(slot / columns) * pitch + fraction.y * (pitch - gap))
  }
  /// The target density's own point determines its native adoption offset.
  func contentFocus(columns: Int) -> CGPoint? { faces[columns]?.referenceFocus }
  private func lattice(columns: Int,side: CGFloat, pitch: CGFloat? = nil, focus: CGPoint? = nil) -> CGPoint {
    let pitch = pitch ?? self.pitch, focus = focus ?? self.focus
    guard let face = faces[columns] else { return focus }
    let scale = pitch / naturalPitch(columns), gap = faceGap(columns)
    return CGPoint(x: focus.x - (face.referenceFocus.x - (gap == 0 ? 0 : 2)) * scale
        + face.gapFraction.x * gap * (1 - scale),
      y: focus.y - (face.referenceFocus.y - 4) * scale + face.gapFraction.y * gap * (1 - scale))
  }
  func show(_ columns: Int,animated: Bool,at now: CFTimeInterval = CACurrentMediaTime()) {
    guard faces[columns] != nil else { return }
    advanceBlend(to: now)
    guard animated else {
      shown = columns; blend = nil
      for face in faces.values { face.weight = face.columns == columns ? 1 : 0 }
      renderBlend(at: now); prune(); render(); return
    }
    guard columns != shown else { return }
    shown = columns
    let from = faces.mapValues(\.weight)
    let active = from.keys.filter { from[$0, default: 0] > 0.0001 || $0 == columns }
    blend = GridZoom.Blend(from: from, target: columns,
      curved: active.allSatisfy { MacGridReadingFamily.family($0) == 0 }, at: now)
    renderBlend(at: now)
  }
  /// Fraction of a face's tiles that already show pixels.
  private func loaded(_ face: Face) -> CGFloat {
    if let canvas = face.canvas { return canvas.loadedFraction }
    guard !face.tiles.isEmpty else { return 1 }
    let ready = face.tiles.values.reduce(0) { $0 + (($1.1 as? MacZoomMediaTile)?.displayedImage != nil || ($1.1 as? MacSourceZoomTile)?.cell.displayedImage != nil ? 1 : 0) }
    return CGFloat(ready) / CGFloat(face.tiles.count)
  }
  private func advanceBlend(to now: CFTimeInterval) {
    guard !settleAwaitingStart else { return }
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
    for (columns, weight) in b.weights(at: t) { faces[columns]?.weight = weight }
    if t >= 1 { blend = nil }
    applyWeights()
  }
  private func weights(at now: CFTimeInterval) -> [Int: CGFloat] {
    guard let b = blend else { return faces.mapValues(\.weight) }
    let t = CGFloat(min(1, max(0, (now - b.start) / b.duration)))
    return b.weights(at: t)
  }
  private func opacities(_ weights: [Int: CGFloat]) -> [Int: Float] {
    var result: [Int: Float] = [:], above: CGFloat = 0
    for columns in order.reversed() {
      let weight = weights[columns, default: 0]
      result[columns] = Float(min(1, max(0, weight / max(0.000001, 1 - above))))
      above += weight
    }
    return result
  }
  /// Geometry events sample the mixture without restarting the system fade.
  func trackBlend(at now: CFTimeInterval) { advanceBlend(to: now) }
  private func renderBlend(at now: CFTimeInterval = CACurrentMediaTime(), batch: MacGridAnimationBatch? = nil) {
    guard !settleAwaitingStart || batch != nil else { return }
    if blendWait != nil, var b = blend,
      now - b.requested >= Self.pixelWait || faces[b.target].map({ loaded($0) >= 0.8 }) == true {
      b.start = now; blend = b
    }
    blendWait?.cancel(); blendWait = nil
    blendGeneration += 1
    blendEnd = nil
    let generation = blendGeneration
    advanceBlend(to: now)
    for face in faces.values {
      face.layer?.removeAnimation(forKey: "zoom.fade")
      readingLayer(face)?.removeAnimation(forKey: "zoom.readingFamily")
    }
    guard let b = blend else { prune(); finishSettleIfReady(); return }
    if let target = faces[b.target], loaded(target) < 0.8, now - b.requested < Self.pixelWait {
      let deadline = DispatchWorkItem { [weak self] in self?.renderBlend() }
      blendWait = deadline
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.pixelWait - (now - b.requested), execute: deadline)
      return
    }
    let duration = max(0.001, b.start + b.duration - now)
    var tracks: [Int: [NSNumber]] = [:]
    for k in 0...48 {
      for (columns, opacity) in opacities(weights(at: now + duration * Double(k) / 48)) {
        tracks[columns, default: []].append(NSNumber(value: opacity))
      }
    }
    let readingTimes = MacGridReadingFamily.keyTimes(from: weights(at: now), to: weights(at: now + duration))
    let readingWeights = readingTimes.map { MacGridReadingFamily.weights(weights(at: now + duration * Double($0))) }
    CATransaction.begin(); CATransaction.setDisableActions(true)
    do {
      blendEnd = MacGridAnimationEnd { [weak self] in
        guard let self, generation == self.blendGeneration, let b = self.blend else { return }
        self.blendEnd = nil
        self.advanceBlend(to: max(CACurrentMediaTime(), b.start + b.duration))
        self.prune(); self.finishSettleIfReady()
      }
    }
    for (columns, face) in faces {
      guard let values = tracks[columns], let end = values.last else { continue }
      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.values = values; fade.duration = duration; fade.calculationMode = .linear
      fade.beginTime = face.layer?.convertTime(now, from: nil) ?? now
      if columns == b.target { fade.delegate = blendEnd }
      face.alphaValue = CGFloat(end.floatValue)
      if let layer = face.layer { MacGridAnimationBatch.schedule(fade, on: layer, key: "zoom.fade", batch: batch) }
      if let reading = readingLayer(face) {
        let gate = CAKeyframeAnimation(keyPath: "opacity")
        let family = MacGridReadingFamily.family(columns)
        gate.values = readingWeights.map { NSNumber(value: MacGridReadingFamily.gate($0[family, default: 0])) }
        gate.keyTimes = readingTimes.map { NSNumber(value: Double($0)) }
        gate.duration = duration; gate.calculationMode = .linear
        gate.beginTime = reading.convertTime(now, from: nil)
        reading.opacity = (gate.values?.last as? NSNumber)?.floatValue ?? 0
        MacGridAnimationBatch.schedule(gate, on: reading, key: "zoom.readingFamily", batch: batch)
      }
    }
    CATransaction.commit()
  }
  private func tileDisplayed() {
    guard blendWait != nil, let b = blend, let target = faces[b.target], loaded(target) >= 0.8 else { return }
    renderBlend()
  }
  /// A release finishes a held crossfade with the settle instead of holding a
  /// partially blended pose for the rest of its long fade.
  func hurryBlend(within limit: CFTimeInterval,at now: CFTimeInterval = CACurrentMediaTime()) {
    advanceBlend(to: now)
    guard var b = blend else { return }
    let t = min(1,max(0,(now-b.start)/b.duration)), remaining = (1-t)*b.duration
    guard remaining > limit else { b.requested = now - Self.pixelWait; blend = b; renderBlend(at: now); return }
    b.duration = b.duration*limit/remaining
    b.start = now-t*b.duration
    b.requested = now - Self.pixelWait
    blend = b
    renderBlend(at: now)
  }
  private func readingLayer(_ face: Face) -> CALayer? {
    face.canvas?.periodReadingLayer ?? face.readingPlane.layer
  }
  private func applyReadingWeights() {
    let families = MacGridReadingFamily.weights(faces.mapValues(\.weight))
    for face in faces.values {
      readingLayer(face)?.opacity = MacGridReadingFamily.gate(families[MacGridReadingFamily.family(face.columns), default: 0])
    }
  }
  private func applyWeights() {
    for (columns, opacity) in opacities(faces.mapValues(\.weight)) { faces[columns]?.alphaValue = CGFloat(opacity) }
    applyReadingWeights()
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
    for (_,view) in face.tiles.values { releaseTileView(view) }
    face.tiles.removeAll()
  }
  private func releaseTileView(_ tile: NSView) {
    if let reading = tile as? MacGridReadingTile {
      for mark in reading.readingMarkLayers {
        readingCorrections.removeValue(forKey: ObjectIdentifier(mark))
        releaseReadingCorrections.removeValue(forKey: ObjectIdentifier(mark))
      }
      MacGridReadingMarks.remove(from: reading.readingMarkLayers)
      reading.setReadingHost(nil); reading.setReadingRect(nil)
    }
    releaseTile?(tile); tile.removeFromSuperview()
  }
  /// Layout is committed once at the destination. Each tile carries its own
  /// spring so ordinary-grid gaps stay 2 pt rather than scaling with a face.
  func settle(with model: GridZoom.Settle, done: @escaping () -> Void) {
    let batch = MacGridAnimationBatch()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    frozenPitchVelocity = 0
    releaseReadingCorrections = readingCorrections; readingCorrections.removeAll()
    settleAwaitingStart = false
    let readingY = footerLabel?.frame.minY
    footerTrackingOffset = 0; footerRelease = nil
    if let readingY, let targetY = footerY(pitch: model.targetPitch, focus: model.targetFocus) {
      footerRelease = GridZoom.Settle(start: model.start, pitch: readingY, focus: .zero,
        velocity: 0, targetPitch: targetY, targetFocus: .zero)
    }
    settling = model; settleCompletion = done; settleLanded = false
    settleGeneration += 1
    let generation = settleGeneration
    var duration = model.duration
    if let footerRelease { duration = max(duration, footerRelease.duration) }
    if let b = blend { duration = max(duration, b.start + b.duration - model.start) }
    settleDuration = duration
    coverage = (0...72).map { model.state(at: model.start + duration * Double($0) / 72) }
    pitch = model.targetPitch; focus = model.targetFocus
    render()
    renderBlend(at: model.start, batch: batch)
    settleEnd = MacGridAnimationEnd(timingLayer: layer,
      started: { [weak self] start in
        guard let self, generation == self.settleGeneration else { return }
        self.releaseAnimationStarted(at: start)
      }) { [weak self] in
      guard let self, generation == self.settleGeneration, self.settling != nil else { return }
      self.settleEnd = nil
      self.settleLanded = true; self.finishSettleIfReady()
    }
    // A constant-opacity animation owns the stage's native completion clock.
    // It changes no pixels and does not wait on off-screen tile backing layers.
    let clock = CABasicAnimation(keyPath: "opacity")
    clock.fromValue = 1; clock.toValue = 1; clock.duration = duration
    clock.beginTime = layer?.convertTime(model.start, from: nil) ?? model.start
    clock.delegate = settleEnd
    if let layer { MacGridAnimationBatch.schedule(clock, on: layer, key: "zoom.settleClock", batch: batch) }
    for face in faces.values {
      if let canvas = face.canvas {
        let columns = face.columns
        canvas.animateZoom(model, duration: duration, batch: batch) { [weak self] p, f in
          self?.lattice(columns: columns, side: p, pitch: p, focus: f) ?? .zero
        }
        // Photos share a gapless transform; period text stays outside it.
      }
      for (key, (_, tile)) in face.tiles {
        guard let from = tileFrame(face, key: key, pitch: model.pitch, focus: model.focus),
          let unit = tileFrame(face, key: key, pitch: model.pitch + 1, focus: model.focus, snapped: false),
          let base = tileFrame(face, key: key, pitch: model.pitch, focus: model.focus, snapped: false),
          tile.layer != nil else { continue }
        MacGridSpring.animate(tile, from: from, derivative: CGRect(
          x: unit.minX - base.minX, y: unit.minY - base.minY,
          width: unit.width - base.width, height: unit.height - base.height), model: model, duration: duration, batch: batch)
      }
    }
    animateHeaders(model, duration: duration, batch: batch)
    animateFooter(duration: duration, batch: batch)
    // Materialize deferred backing content while the target pose is still in
    // this uncommitted transaction, before the release clock starts.
    layoutSubtreeIfNeeded()
    func prepare(_ layer: CALayer) {
      layer.layoutIfNeeded(); layer.displayIfNeeded()
      for child in layer.sublayers ?? [] { prepare(child) }
    }
    if let layer { prepare(layer) }
    let start = CACurrentMediaTime(), shift = start - model.start
    settling = GridZoom.Settle(start: start, pitch: model.pitch, focus: model.focus,
      velocity: model.velocity, targetPitch: model.targetPitch, targetFocus: model.targetFocus)
    if let current = footerRelease {
      footerRelease = GridZoom.Settle(start: start, pitch: current.pitch, focus: .zero,
        velocity: 0, targetPitch: current.targetPitch, targetFocus: .zero)
    }
    if var current = blend {
      current.start += shift; current.requested += shift; blend = current
    }
    settleAwaitingStart = true
    batch.install()
    CATransaction.commit()
    coverage = []
  }
  /// Core Animation supplies the resolved commitment time once. Input before
  /// this event retains the release origin instead of consuming preparation time.
  func releaseAnimationStarted(at start: CFTimeInterval) {
    guard settleAwaitingStart, let model = settling, start.isFinite else { return }
    let shift = start - model.start
    settling = GridZoom.Settle(start: start, pitch: model.pitch, focus: model.focus,
      velocity: model.velocity, targetPitch: model.targetPitch, targetFocus: model.targetFocus)
    if let current = footerRelease {
      footerRelease = GridZoom.Settle(start: current.start + shift, pitch: current.pitch, focus: current.focus,
        velocity: current.velocity, targetPitch: current.targetPitch, targetFocus: current.targetFocus)
    }
    if var current = blend {
      current.start += shift; current.requested += shift; blend = current
    }
    settleAwaitingStart = false
    // A readiness event may have arrived while the transaction was pending.
    if blendWait != nil { renderBlend() }
  }
  private func finishSettleIfReady() {
    guard settleLanded, blend == nil, let model = settling else { return }
    let done = settleCompletion
    settling = nil; settleCompletion = nil; settleLanded = false; settleAwaitingStart = false
    footerRelease = nil; footerTrackingOffset = 0
    readingCorrections.removeAll(); releaseReadingCorrections.removeAll()
    pitch = model.targetPitch; focus = model.targetFocus
    removeSettleAnimations(); render()
    done?()
  }
  /// Gesture interruption uses the identical analytic pose, never presentation
  /// layer polling. Removing animations and relayout happen in one transaction.
  func freeze(at now: CFTimeInterval = CACurrentMediaTime()) {
    guard let model = settling else { return }
    let pending = settleAwaitingStart
    let progress = pending ? 0 : CGFloat(min(1, max(0, (now - model.start) / max(0.000001, settleDuration))))
    let held = MacGridReadingMarks.snapshot(faces.values.flatMap { $0.tiles.values.flatMap {
      ($0.1 as? MacGridReadingTile)?.readingMarkLayers ?? []
    } }, at: progress)
    let state = model.state(at: pending ? model.start : now)
    let readingY: CGFloat?
    if let label = footerLabel, let move = label.layer?.animation(forKey: "zoom.footer") as? CAKeyframeAnimation,
      let position = MacGridReadingMarks.value(move, at: progress) {
      readingY = position - ((label.layer?.position.y ?? 0) - label.frame.minY)
    } else { readingY = footerRelease.map { $0.state(at: pending ? $0.start : now).pitch } ?? footerLabel?.frame.minY }
    footerRelease = nil
    readingCorrections.removeAll(); releaseReadingCorrections.removeAll()
    frozenPitchVelocity = pending ? model.velocity : model.pitchVelocity(at: now)
    if pending, var current = blend {
      let shift = now - model.start
      current.start += shift; current.requested += shift; blend = current
    }
    settleAwaitingStart = false
    settling = nil; settleCompletion = nil; settleLanded = false
    settleGeneration += 1
    CATransaction.begin(); CATransaction.setDisableActions(true)
    advanceBlend(to: now)
    pitch = state.pitch; focus = state.focus
    if let readingY, let geometricY = footerY(pitch: pitch, focus: focus) {
      footerTrackingOffset = readingY - geometricY
    }
    removeSettleAnimations(); renderBlend(at: now); render()
    let attached = Set(faces.values.flatMap { $0.tiles.values.flatMap {
      ($0.1 as? MacGridReadingTile)?.readingMarkLayers.map(ObjectIdentifier.init) ?? []
    } })
    for pose in held where attached.contains(ObjectIdentifier(pose.layer)) {
      let raw = pose.layer.frame
      readingCorrections[ObjectIdentifier(pose.layer)] = MacGridReadingMarks.Correction(
        x: pose.frame.minX - raw.minX, y: pose.frame.minY - raw.minY,
        width: pose.frame.width - raw.width, opacity: pose.opacity - pose.layer.opacity)
    }
    MacGridReadingMarks.apply(held.filter { attached.contains(ObjectIdentifier($0.layer)) })
    CATransaction.commit()
  }
  private func removeSettleAnimations() {
    settleEnd = nil; layer?.removeAnimation(forKey: "zoom.settleClock")
    for face in faces.values {
      face.canvas?.removeZoomAnimations()
      face.photoMask?.removeAnimation(forKey: "zoom.footerClip")
      for (_, tile) in face.tiles.values {
        MacGridSpring.remove(from: tile)
        if let reading = tile as? MacGridReadingTile { MacGridReadingMarks.remove(from: reading.readingMarkLayers) }
      }
    }
    for header in headers.values { header.layer?.removeAnimation(forKey: "zoom.caption") }
    footerLabel?.layer?.removeAnimation(forKey: "zoom.footer")
  }
  /// Deterministic model advancement for hostless checks; runtime motion is CA.
  /// A pending release uses its saved provisional epoch, not the supplied time.
  func advance(to now: CFTimeInterval) {
    if settleAwaitingStart, let model = settling { releaseAnimationStarted(at: model.start) }
    advanceBlend(to: now)
    prune()
    if let model = settling {
      if now >= model.start + settleDuration { settleLanded = true }
      finishSettleIfReady()
    } else { prune(); render() }
  }
  func render() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    updateBackground()
    for face in faces.values {
      face.frame = bounds; face.photoPlane.frame = bounds; face.readingPlane.frame = bounds
      populate(face)
    }
    populateHeaders()
    renderFooter()
    applyReadingWeights()
    CATransaction.commit()
  }
  private func snap(_ value: CGFloat) -> CGFloat {
    let scale = window?.backingScaleFactor ?? 2
    return (value * scale).rounded() / scale
  }
  private func tileFrame(_ face: Face, key: String, pitch: CGFloat, focus: CGPoint, snapped: Bool = true) -> CGRect? {
    let s: (CGFloat) -> CGFloat = snapped ? snap : { $0 }
    if let geometry = groupedGeometry?(face.columns), let index = face.tiles[key]?.0,
      geometry.items.indices.contains(index), geometry.items.indices.contains(anchor) {
      let ratio = pitch / (max(1, referenceSide(face.columns)) + 2)
      let rect = geometry.items[index]
      return CGRect(x: s(focus.x + (rect.minX - face.referenceFocus.x) * ratio),
        y: s(focus.y + (rect.minY - face.referenceFocus.y) * ratio),
        width: max(1, s(rect.width * ratio)), height: max(1, s(rect.height * ratio)))
    }
    let parts = key.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return nil }
    let gap = faceGap(face.columns), origin = lattice(columns: face.columns, side: max(1, pitch - gap), pitch: pitch, focus: focus)
    let x = origin.x + CGFloat(parts[1]) * pitch, y = origin.y + CGFloat(parts[0]) * pitch
    return CGRect(x: s(x), y: s(y), width: max(1, s(x + pitch) - gap - s(x)), height: max(1, s(y + pitch) - gap - s(y)))
  }
  private func coverageRect(_ face: Face) -> CGRect {
    let grouped = groupedGeometry != nil
    let target = grouped ? focus : lattice(columns: face.columns, side: max(1, pitch - faceGap(face.columns)))
    return coverage.reduce(bounds) { rect, pose in
      let origin = grouped ? pose.focus : lattice(columns: face.columns, side: max(1, pose.pitch - faceGap(face.columns)), pitch: pose.pitch, focus: pose.focus)
      let ratio = pitch / pose.pitch
      return rect.union(CGRect(x: target.x - origin.x * ratio, y: target.y - origin.y * ratio,
        width: bounds.width * ratio, height: bounds.height * ratio))
    }
  }
  private func prepareTile(_ tile: NSView, at index: Int) {
    tile.wantsLayer = true
    if let image = seedImages[index] {
      if let media = tile as? MacZoomMediaTile, media.displayedImage == nil { media.show(image) }
      if let source = tile as? MacSourceZoomTile, source.cell.displayedImage == nil { source.cell.retainDisplayedImage(image) }
    }
    let displayed: () -> Void = { [weak self] in self?.tileDisplayed() }
    (tile as? MacZoomMediaTile)?.onDisplay = displayed
    (tile as? MacSourceZoomTile)?.cell.onDisplay = displayed
  }
  private func populate(_ face: Face) {
    if let geometry = groupedGeometry?(face.columns) { populateGrouped(face, geometry: geometry); return }
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
      canvas.onDisplay = { [weak self] in self?.tileDisplayed() }
      canvas.render(columns: columns, origin: origin, pitch: pitch, visible: coverageRect(face), leading: face.leading,
        pinTop: bounds.minY + densePinTop, extendsRows: true)
      return
    }
    let reference = max(1,referenceSide(columns))
    let visible = coverageRect(face)
    let lastRow = max(0, (count - 1 + face.leading) / columns)
    let rowStart = max(0, Int(floor((visible.minY-origin.y)/pitch))-1)
    let rowEnd = min(lastRow, Int(ceil((visible.maxY-origin.y)/pitch))+1)
    // Real rows extend horizontally while scaled down. Extra columns read
    // chronological neighbors, but cannot synthesize rows beyond the content.
    let colStart = Int(floor((visible.minX-origin.x)/pitch))-1, colEnd = Int(ceil((visible.maxX-origin.x)/pitch))+1
    var keep = Set<String>()
    for row in rowStart...max(rowStart,rowEnd) where row <= rowEnd {
      for col in colStart...max(colStart,colEnd) {
        let index = row*columns+col-face.leading
        guard index >= 0, index < count else { continue }
        let key = "\(row):\(col)"; keep.insert(key)
        let tile: NSView
        if let old = face.tiles[key], old.0 == index { tile = old.1 }
        else {
          if let old = face.tiles.removeValue(forKey: key) { releaseTileView(old.1) }
          tile = makeTile?(index,reference) ?? NSView()
          prepareTile(tile, at: index)
          face.photoPlane.addSubview(tile); face.tiles[key] = (index,tile)
        }
        // Edges snap to device pixels from the lattice, so every gap in a frame
        // has one width and tiles never shimmer while the pitch animates.
        let x0 = snap(origin.x+CGFloat(col)*pitch), y0 = snap(origin.y+CGFloat(row)*pitch)
        let x1 = snap(origin.x+CGFloat(col+1)*pitch)-gap, y1 = snap(origin.y+CGFloat(row+1)*pitch)-gap
        let frame = CGRect(x: x0,y: y0,width: max(1,x1-x0),height: max(1,y1-y0))
        if tile.frame != frame { tile.frame = frame; tile.needsLayout = true }
        tile.layoutSubtreeIfNeeded()
      }
    }
    for key in Array(face.tiles.keys) where !keep.contains(key) {
      if let old = face.tiles.removeValue(forKey: key) { releaseTileView(old.1) }
    }
  }
  private func populateGrouped(_ face: Face, geometry: LibraryTimelineGeometry) {
    guard geometry.items.indices.contains(anchor) else { return }
    let reference = max(1, referenceSide(face.columns))
    let ratio = pitch / (reference + 2)
    let offset = CGPoint(x: focus.x - face.referenceFocus.x * ratio,
      y: focus.y - face.referenceFocus.y * ratio)
    func frame(_ rect: CGRect) -> CGRect {
      CGRect(x: snap(offset.x + rect.minX * ratio), y: snap(offset.y + rect.minY * ratio),
        width: max(1, snap(rect.width * ratio)), height: max(1, snap(rect.height * ratio)))
    }
    let cover = coverageRect(face)
    let visible = CGRect(x: (cover.minX-offset.x) / ratio, y: (cover.minY-offset.y) / ratio, width: cover.width / ratio, height: cover.height / ratio)
    var keep = Set<String>()
    for index in geometry.visibleItems(in: visible.insetBy(dx: 0, dy: -reference)) {
      let key = String(index); keep.insert(key)
      let tile: NSView
      if let existing = face.tiles[key] { tile = existing.1 }
      else { tile = makeTile?(index, reference) ?? NSView(); prepareTile(tile, at: index); face.photoPlane.addSubview(tile); face.tiles[key] = (index, tile) }
      tile.frame = frame(geometry.items[index]); tile.needsLayout = true
      tile.layoutSubtreeIfNeeded()
    }
    for key in Array(face.tiles.keys) where !keep.contains(key) {
      if let old = face.tiles.removeValue(forKey: key) { releaseTileView(old.1) }
    }
  }
  /// Captions follow geometric density, independently of the photo mixture.
  /// A held fade cannot move a date heading after the fingers have stopped.
  private func headerRects(pitch: CGFloat, focus: CGPoint) -> [MacTimelineCaption.ID: CGRect] {
    let stops = MacLibraryDensity.grid.sorted { referenceSide($0) > referenceSide($1) }
    var weights: [Int: CGFloat] = [shown: 1]
    if let first = stops.first, let last = stops.last {
      if pitch >= referenceSide(first) + 2 { weights = [first: 1] }
      else if pitch <= referenceSide(last) + 2 { weights = [last: 1] }
      else {
        for pair in zip(stops, stops.dropFirst()) {
          let high = referenceSide(pair.0) + 2, low = referenceSide(pair.1) + 2
          if pitch <= high && pitch >= low {
            let t = (high - pitch) / max(0.001, high - low)
            weights = [pair.0: 1 - t, pair.1: t]
            break
          }
        }
      }
    }
    guard let geometry = groupedGeometry?(shown), geometry.items.indices.contains(anchor) else { return [:] }
    let total = weights.values.reduce(CGFloat.zero, +)
    guard total > 0 else { return [:] }
    var positions: [MacTimelineCaption.ID: CGFloat] = [:]
    var contentBottom: CGFloat = 0
    for (columns, weight) in weights where weight > 0 {
      guard let g = groupedGeometry?(columns), g.items.indices.contains(anchor) else { continue }
      // Native-size reading blocks follow their photo boundary once; they do
      // not inherit the photo face's scale or timed crossfade.
      let ratio = weights.count == 1 ? pitch / (max(1, referenceSide(columns)) + 2) : 1
      guard let reference = groupedReference(columns) else { continue }
      let offset = focus.y - reference.y * ratio
      contentBottom += (offset + (g.items.last?.maxY ?? g.height) * ratio) * weight / total
      for caption in g.macCaptions.ordered where g.items.indices.contains(caption.firstItem) {
        let firstRow = g.items[caption.firstItem].minY
        let y = offset + firstRow * ratio - (firstRow - caption.frame.minY)
        positions[caption.id, default: 0] += y * weight / total
      }
    }
    let natural: (MacTimelineCaption.ID) -> CGRect? = { id in
      guard let y = positions[id], let caption = geometry.macCaptions.byID[id] else { return nil }
      return CGRect(x: 0, y: y, width: self.bounds.width, height: caption.frame.height)
    }
    return geometry.macCaptions.ordered.reduce(into: [:]) { result, caption in
      guard positions[caption.id] != nil else { return }
      var frame = geometry.macCaptions.frame(for: caption, top: groupedPinTop, width: bounds.width,
        contentBottom: contentBottom, natural: natural)
      frame.origin.y = snap(frame.minY)
      result[caption.id] = frame
    }
  }
  private func populateHeaders() {
    guard let geometry = groupedGeometry?(shown) else { return }
    let rects = headerRects(pitch: pitch, focus: focus)
    var keep = Set(rects.filter { $0.value.intersects(bounds) }.keys)
    if settling != nil {
      for pose in coverage {
        keep.formUnion(headerRects(pitch: pose.pitch, focus: pose.focus)
          .filter { $0.value.intersects(bounds) }.keys)
      }
    }
    for caption in geometry.macCaptions.ordered where keep.contains(caption.id) {
      guard let rect = rects[caption.id] else { continue }
      let view: MacGridSectionHeader
      if let existing = headers[caption.id] { view = existing }
      else {
        view = MacGridSectionHeader(frame: rect)
        let content: AnyView?
        switch caption.id.kind {
        case .folder: content = groupedIdentity?(caption.firstItem)
        case .summary: content = groupedIntroduction?(caption.firstItem)
        case .date: content = caption.parent == nil ? groupedIntroduction?(caption.firstItem) : nil
        }
        view.configure(caption: caption, content: content, revision: groupedRevision)
        headers[caption.id] = view; addSubview(view)
        view.layer?.zPosition = CGFloat(caption.id.kind.zIndex)
      }
      view.floatingDate = caption.id.kind == .date
      view.wantsLayer = true; view.frame = rect; view.layoutSubtreeIfNeeded()
    }
    for id in Array(headers.keys) where !keep.contains(id) { headers.removeValue(forKey: id)?.removeFromSuperview() }
  }
  private func animateHeaders(_ model: GridZoom.Settle, duration: CFTimeInterval, batch: MacGridAnimationBatch? = nil) {
    var tracks: [MacTimelineCaption.ID: [NSNumber]] = [:]
    for k in 0...72 {
      let time = model.start + duration * Double(k) / 72
      let pose = model.state(at: time)
      let rects = headerRects(pitch: pose.pitch, focus: pose.focus)
      for (id, header) in headers {
        guard let rect = rects[id], let layer = header.layer else { continue }
        let y = k == 72 ? layer.position.y : layer.position.y + rect.minY - header.frame.minY
        tracks[id, default: []].append(NSNumber(value: Double(y)))
      }
    }
    for (id, header) in headers {
      let move = CAKeyframeAnimation(keyPath: "position.y")
      move.values = tracks[id]; move.duration = duration; move.calculationMode = .linear
      move.beginTime = header.layer?.convertTime(model.start, from: nil) ?? model.start
      if let layer = header.layer { MacGridAnimationBatch.schedule(move, on: layer, key: "zoom.caption", batch: batch) }
    }
  }
  func headerFrame(at firstItem: Int) -> CGRect? {
    guard let id = groupedGeometry?(shown).macCaptions.caption(kind: .date, at: firstItem)?.id else { return nil }
    return headers[id]?.frame
  }
  func captionFrame(_ id: MacTimelineCaption.ID) -> CGRect? { headers[id]?.frame }
  func tile(at index: Int) -> NSView? {
    faces[shown]?.tiles.values.first { $0.0 == index }?.1
      ?? faces.values.lazy.compactMap { $0.tiles.values.first { $0.0 == index }?.1 }.first
  }
  func displayedImage(at index: Int) -> NSImage? {
    guard let tile = tile(at: index) else { return nil }
    return (tile as? MacZoomMediaTile)?.displayedImage ?? (tile as? MacSourceZoomTile)?.cell.displayedImage
  }
  var visibleTileCount: Int { faces.values.reduce(0) { $0+$1.tiles.count } }
  @discardableResult func retainDensePixels(in canvas: MacDenseCanvas) -> Bool {
    guard let source = faces[shown]?.canvas else { return false }
    return canvas.retainDisplayedPixels(from: source)
  }
  func stop() {
    blendGeneration += 1; settleGeneration += 1
    blendWait?.cancel(); blendWait = nil; settling = nil; settleCompletion = nil; settleAwaitingStart = false
    blendEnd = nil; settleEnd = nil
    layer?.removeAnimation(forKey: "zoom.settleClock")
    for face in faces.values { release(face); face.removeFromSuperview() }
    faces.removeAll(); order.removeAll(); blend = nil
    groupedReferences.removeAll(); frozenPitchVelocity = 0
    detachFooter()
    seedImages.removeAll()
    for header in headers.values { header.removeFromSuperview() }; headers.removeAll()
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






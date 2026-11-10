import AppKit
import Photos
import SwiftUI
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

private final class MacCountingFetch: PHFetchResult<PHAsset>, @unchecked Sendable {
  private let base: PHFetchResult<PHAsset>
  private let lock = NSLock()
  private var enumerations = 0
  private var indexedEnumerations = 0
  var fullEnumerations: Int { lock.lock(); defer { lock.unlock() }; return enumerations }
  var bulkReads: Int { lock.lock(); defer { lock.unlock() }; return indexedEnumerations }
  init(_ base: PHFetchResult<PHAsset>) { self.base = base; super.init() }
  override var count: Int { base.count }
  override func object(at index: Int) -> PHAsset { base.object(at: index) }
  override func index(of object: PHAsset) -> Int { base.index(of: object) }
  override func enumerateObjects(_ block: @escaping (PHAsset, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
    lock.lock(); enumerations += 1; lock.unlock()
    base.enumerateObjects(block)
  }
  override func enumerateObjects(at indexes: IndexSet, options: NSEnumerationOptions,
    using block: @escaping (PHAsset, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
    lock.lock(); indexedEnumerations += 1; lock.unlock()
    base.enumerateObjects(at: indexes, options: options, using: block)
  }
}

@MainActor func macGridPhotoChildren(_ face: NSView) -> [NSView] {
  if let canvas = face.subviews.first(where: { $0 is MacDenseCanvas }) { return [canvas] }
  return (face.subviews.first { $0 is MacGridPhotoPlane })?.subviews ?? []
}

@MainActor func mountMacGridCollection(_ collection: LibraryCollectionView, coordinator: MacMediaGrid.Coordinator) {
  let canvas = MacDenseCanvas(frame: collection.bounds)
  canvas.autoresizingMask = [.width, .height]; canvas.isHidden = true
  collection.addSubview(canvas); coordinator.denseCanvas = canvas
  if let layout = collection.collectionViewLayout as? LibraryTimelineLayout {
    layout.denseThreshold = MacLibraryDensity.denseThreshold
  }
  coordinator.parent.reducedMotionOverride = false
  coordinator.collection = collection; collection.delegate = coordinator
}

@MainActor final class MacGridTests: XCTestCase {
  func testHostedOverviewClicksAdvanceYearMonthAndGridBeforeNativeAdoption() async throws {
    let original = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = original }
    let library = PhotoLibraryModel()
    library.installSyntheticAssets(CatalogLibraryFixture(count: 2_400).fetch(filter: .all, view: .all))
    let source = MacPhotoLibrarySource(library)
    let navigation = MacLibraryNavigation()
    let size = MacGridSize()
    let width: CGFloat = 1166
    let overview = MacLibraryDensity.overview(forWidth: width)
    size.columns = try XCTUnwrap(overview.last)
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 700),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let host = NSHostingController(rootView: OverviewClickTestHost(source: source, navigation: navigation, size: size)
      .frame(width: width, height: 700))
    host.sizingOptions = []
    window.contentViewController = host; window.setContentSize(NSSize(width: width, height: 700))
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(150))
    window.contentView?.layoutSubtreeIfNeeded()
    func findGrid(_ view: NSView) -> LibraryCollectionView? {
      if let grid = view as? LibraryCollectionView { return grid }
      return view.subviews.lazy.compactMap(findGrid).first
    }
    let collection = try XCTUnwrap(findGrid(host.view))
    let scroll = try XCTUnwrap(collection.enclosingScrollView)
    let layout = try XCTUnwrap(collection.collectionViewLayout as? LibraryTimelineLayout)
    XCTAssertEqual(layout.columns, overview.last)
    XCTAssertGreaterThan(collection.numberOfItems(inSection: 0), 1_000)
    scroll.contentView.scroll(to: CGPoint(x: 0, y: layout.collectionViewContentSize.height / 2))
    scroll.reflectScrolledClipView(scroll.contentView)
    collection.layoutSubtreeIfNeeded()
    let firstIndex = collection.denseHit?(CGPoint(x: 450, y: scroll.contentView.bounds.midY))
    let index = try XCTUnwrap(firstIndex)
    let firstFrame = layout.frame(at: index)
    let location = collection.convert(CGPoint(x: firstFrame.midX, y: firstFrame.midY), to: nil)
    func click(_ location: CGPoint, count: Int) throws {
      let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: count, clickCount: count, pressure: 1))
      collection.mouseDown(with: event)
    }
    try click(location, count: 1)
    let stage = try XCTUnwrap(scroll.subviews.compactMap { $0 as? MacGridZoomStage }.first)
    XCTAssertEqual(size.columns, overview.first)
    XCTAssertEqual(stage.shown, overview.first)
    XCTAssertEqual(layout.columns, overview.last,
      "Exercise the real interval where the visible month stage still covers the native year grid")
    XCTAssertEqual(source.identifiers[stage.anchor], source.identifiers[index])
    // A second native press arrives before completion; do not advance either
    // animation clock or force the collection to adopt the month geometry.
    try click(location, count: 2)
    XCTAssertEqual(size.columns, 9, "The second press must leave the month overview")
    XCTAssertEqual(stage.shown, 9)
    XCTAssertTrue(scroll.subviews.contains { $0 === stage }, "Input must retain the shown stage, not replay its year entry")
    XCTAssertEqual(source.identifiers[stage.anchor], source.identifiers[index],
      "The repeated press must follow the displayed photo, not an index from the covered year grid")
    XCTAssertTrue(source.selection.isEmpty)
  }

  func testDenseClicksResolveSourceIdentityForEveryNativeClickCount() async throws {
    for clickCount in [1, 2, 3] {
      let width: CGFloat = 947
      let source = GridTestSource()
      source.identifiers = (0..<240).map { "source-\(239 - $0)" }
      source.zoomStops = MacLibraryDensity.grid + MacLibraryDensity.overview(forWidth: width)
      let columns = source.zoomStops[source.zoomStops.count - 2]
      var requested: Int?
      let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
        receiverID: nil, columns: columns, resize: { requested = $0 })
      let coordinator = MacMediaGrid.Coordinator(grid)
      let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 400))
      let collection = LibraryCollectionView(frame: scroll.bounds)
      let layout = LibraryTimelineLayout(mode: .all, target: 20)
      layout.requestedColumns = columns; collection.collectionViewLayout = layout
      collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
      scroll.documentView = collection
      mountMacGridCollection(collection, coordinator: coordinator)
      coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
      try await Task.sleep(for: .milliseconds(50))
      coordinator.leading = 3; layout.leadingSlots = 3
      layout.adopt(mode: .all, columns: columns)
      coordinator.ensureDocumentHeight(); collection.layoutSubtreeIfNeeded(); coordinator.updateDense()
      collection.denseHit = { coordinator.denseIndex(at: $0) }
      collection.drill = { coordinator.drillDown(from: $0) }
      let index = columns * 2 + clickCount
      let frame = layout.frame(at: index)
      let point = collection.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
      let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
        modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
        eventNumber: clickCount, clickCount: clickCount, pressure: 1))
      collection.mouseDown(with: event)
      XCTAssertEqual(requested, 9, "Every overview press steps to the ordinary grid")
      let anchor = try XCTUnwrap(coordinator.zoomStage?.anchor)
      XCTAssertEqual(coordinator.identifier(at: anchor), source.identifiers[index],
        "Hit testing must retain the clicked source identity, including leading slots")
      XCTAssertTrue(source.selection.isEmpty, "Overview activation is not ordinary selection")
      coordinator.removeZoomStage()
    }
  }

  func testOrdinaryZoomFromNewestUsesCompleteFirstRowAndPartialLastRow() async throws {
    for count in [16, 97] {
      let source = GridTestSource(); source.identifiers = (0..<count).map { "photo-\($0)" }
      let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
        receiverID: nil, columns: 3)
      let coordinator = MacMediaGrid.Coordinator(grid)
      let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 420))
      let collection = LibraryCollectionView(frame: scroll.bounds)
      let layout = LibraryTimelineLayout(mode: .all, target: 264)
      layout.requestedColumns = 3; collection.collectionViewLayout = layout
      collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
      scroll.documentView = collection
      mountMacGridCollection(collection, coordinator: coordinator)
      coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
      try await Task.sleep(for: .milliseconds(50))
      // Start already resting at the newest edge. scrollToNewest() is a separate
      // 0.35-second native animation and would keep moving this fixture while
      // the deterministic zoom clock advances directly to its settled state.
      coordinator.ensureDocumentHeight(); collection.layoutSubtreeIfNeeded()
      scroll.contentView.scroll(to: CGPoint(x: 0,
        y: max(0, coordinator.settledContentHeight - scroll.contentSize.height)))
      scroll.reflectScrolledClipView(scroll.contentView)
      coordinator.pinnedToNewest = true
      for columns in [9, 6, 4, 3, 9] {
        coordinator.parent.columns = columns
        coordinator.animateLayout(columns: columns)
        let stage = try XCTUnwrap(coordinator.zoomStage)
        XCTAssertEqual(stage.anchor, count - 1)
        stage.advance(to: CACurrentMediaTime() + 3)
        collection.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(coordinator.leading, 0)
        XCTAssertEqual(layout.frame(at: 0).minX, 2, accuracy: 0.5)
        XCTAssertEqual(layout.frame(at: columns - 1).minY, layout.frame(at: 0).minY, accuracy: 0.5)
        let last = layout.frame(at: count - 1)
        let lastRowFirst = layout.frame(at: ((count - 1) / columns) * columns)
        XCTAssertEqual(lastRowFirst.minX, 2, accuracy: 0.5)
        XCTAssertEqual(last.minY, lastRowFirst.minY, accuracy: 0.5)
        XCTAssertTrue(coordinator.pinnedToNewest)
        XCTAssertEqual(scroll.contentView.bounds.minY,
          max(0, coordinator.settledContentHeight - scroll.contentSize.height), accuracy: 0.5)
      }
      coordinator.removeZoomStage()
    }
  }

  func testViewerReturnPreservesVisibleCellAndRevealsOnlyNearestEdge() async {
    let source = GridTestSource()
    source.identifiers = (0..<96).map { "item-\($0)" }
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 9)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = LibraryScrollView(frame: CGRect(x: 0, y: 0, width: 540, height: 240))
    let collection = LibraryCollectionView(frame: CGRect(x: 0, y: 0, width: 540, height: 240))
    let layout = LibraryTimelineLayout(mode: .all, target: 135)
    layout.requestedColumns = 9; collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    scroll.documentView = collection
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    collection.layoutSubtreeIfNeeded()
    scroll.contentView.scroll(to: CGPoint(x: 0, y: 120))
    let before = scroll.contentView.bounds.minY
    coordinator.pendingFocus = "item-27"; coordinator.applyPendingFocus()
    XCTAssertEqual(scroll.contentView.bounds.minY, before, accuracy: 0.5,
      "Closing a visible photo must not centre its cell")
    coordinator.pendingFocus = "item-0"; coordinator.applyPendingFocus()
    XCTAssertEqual(scroll.contentView.bounds.minY, layout.frame(at: 0).minY, accuracy: 0.5)
    coordinator.pendingFocus = "item-95"; coordinator.applyPendingFocus()
    XCTAssertEqual(scroll.contentView.bounds.maxY, layout.frame(at: 95).maxY, accuracy: 0.5,
      "An offscreen return photo only needs its nearest edge revealed")
  }
  func testPhotoLibraryOpensBeforeBulkReadAndCompletesWithoutScrolling() async throws {
    let original = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = original }
    let fixture = CatalogLibraryFixture(count: 2_400)
    let fetch = MacCountingFetch(fixture.fetch(filter: .all, view: .all))
    let library = PhotoLibraryModel()
    library.installSyntheticAssets(CatalogAssetCollection([]))
    library.syntheticFetch = { _, _ in fetch }
    await library.reload(resetWindow: true)

    XCTAssertEqual(library.total, 2_400)
    XCTAssertEqual(library.loaded, 240)
    XCTAssertEqual(fetch.bulkReads, 0, "Opening the grid must not wait on a bulk read")
    let source = MacPhotoLibrarySource(library)
    let openingIDs = source.fetchResult.identifiers
    XCTAssertTrue(source.fetchResult.opening)
    XCTAssertNil(source.fetchResult.totals, "The opening rows are not the collection total")

    for _ in 0..<150 where source.fetchResult.opening {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertEqual(library.loaded, 2_400)
    XCTAssertFalse(library.hasMoreRows)
    XCTAssertEqual(fetch.bulkReads, 1, "The same result completes automatically in one bulk read")
    XCTAssertEqual(fetch.fullEnumerations, 0, "The Mac grid uses its lightweight index")
    XCTAssertFalse(source.fetchResult.opening)
    XCTAssertEqual(source.fetchResult.count, 2_400)
    XCTAssertEqual(Array(source.fetchResult.identifiers.suffix(240)), openingIDs)
    XCTAssertEqual(source.fetchResult.positions?[openingIDs[0]], 2_160)
    XCTAssertNotEqual(source.fetchResult.mediaKind(at: 2_399), .unknown)

    let calendar = MacLibraryNavigation.periods(fetch)
    XCTAssertFalse(calendar.0.isEmpty)
    XCTAssertFalse(calendar.1.isEmpty)
    XCTAssertEqual(fetch.fullEnumerations, 1, "The calendar builds its own index only when requested")
  }
  func testViewerLayoutDoesNotAcquireNewestPinFromUnmovedSource() async {
    let source = GridTestSource()
    source.identifiers = []
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 9)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = LibraryScrollView(frame: CGRect(x: 0, y: 0, width: 540, height: 688))
    let collection = LibraryCollectionView(frame: CGRect(x: 0, y: 0, width: 540, height: 688))
    let layout = LibraryTimelineLayout(mode: .all, target: 135)
    layout.requestedColumns = 9; collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    scroll.documentView = collection
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
    coordinator.scrolled(event: click)
    XCTAssertFalse(coordinator.pinnedToNewest, "A sidebar click while this source is empty is not a scroll to its newest edge")
    source.identifiers = (0..<96).map { "item-\($0)" }
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertGreaterThan(coordinator.settledContentHeight, scroll.contentSize.height)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    coordinator.scrolled(event: click)
    coordinator.contentResized()
    XCTAssertFalse(coordinator.pinnedToNewest)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5,
      "Selection and viewer layout must retain the source viewport even when its footer is below the fold")
    let arrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: 125)!
    coordinator.ensureDocumentHeight()
    scroll.contentView.scroll(to: CGPoint(x: 0, y: coordinator.settledContentHeight - scroll.contentSize.height))
    coordinator.scrolled(event: arrow)
    XCTAssertTrue(coordinator.pinnedToNewest, "Actual scrolling still adopts the newest edge")
  }

  func testViewerOwnsNativeSourceViewportUntilReturnThenRestoresBrowsing() async {
    let source = GridTestSource()
    source.identifiers = (0..<96).map { "item-\($0)" }
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 9)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = LibraryScrollView(frame: CGRect(x: 0, y: 0, width: 540, height: 688))
    let collection = LibraryCollectionView(frame: CGRect(x: 0, y: 0, width: 540, height: 688))
    let layout = LibraryTimelineLayout(mode: .all, target: 135)
    layout.requestedColumns = 9; collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    scroll.documentView = collection
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    coordinator.ensureDocumentHeight()
    let original = scroll.contentView.bounds.origin
    let flight = MacViewerFlight()
    let origin = MacCoverFlightSource(rect: .zero, image: nil, radius: 0, assetID: "item-0",
      clip: scroll.bounds, window: nil, sourceViewport: scroll)
    flight.begin(origin)
    coordinator.pinnedToNewest = true
    coordinator.contentResized()
    XCTAssertEqual(scroll.contentView.bounds.origin, original, "A layout's pending bottom restore cannot move the departing grid")
    let bottom = CGRect(x: 0, y: coordinator.settledContentHeight - 8, width: 8, height: 8)
    _ = collection.scrollToVisible(bottom)
    scroll.reflectScrolledClipView(scroll.contentView)
    XCTAssertEqual(scroll.contentView.bounds.origin, original, "AppKit's document visibility request must obey the same source ownership")
    scroll.contentView.setBoundsOrigin(CGPoint(x: 0, y: 30))
    var proposed = scroll.contentView.bounds; proposed.origin.y = 25
    scroll.contentView.bounds = proposed
    XCTAssertEqual(scroll.contentView.bounds.origin, original)
    scroll.setFrameSize(NSSize(width: 540, height: 640)); scroll.layoutSubtreeIfNeeded()
    XCTAssertEqual(scroll.contentView.bounds.origin, original)
    XCTAssertEqual(scroll.contentView.bounds.height, scroll.contentSize.height, accuracy: 0.5,
      "Native resizing remains live while only the source offset is retained")
    var completed = false
    flight.close(to: { nil }) { completed = true }
    XCTAssertTrue(completed)
    XCTAssertEqual(scroll.contentView.bounds.origin, original, "Releasing source ownership must not replay a deferred scroll")
    XCTAssertFalse(coordinator.pinnedToNewest)
    coordinator.contentResized()
    XCTAssertEqual(scroll.contentView.bounds.origin, original)
    _ = collection.scrollToVisible(bottom)
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, original.y, "Native browsing resumes after return")
    flight.begin(origin)
    let retained = scroll.contentView.bounds.origin
    flight.releaseSourceViewport()
    scroll.contentView.scroll(to: .zero)
    XCTAssertNotEqual(scroll.contentView.bounds.origin, retained, "Removal without a close flight also releases the source")
    flight.begin(origin)
    flight.begin(nil)
    _ = collection.scrollToVisible(bottom)
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "A replacement without a source releases the previous lease")
  }

  func testFirstDisplayedPixelsStartAnAutonomousFadeWhileMagnifyRests() async {
    let stage = MacGridZoomStage(count: 16, anchor: 0, fraction: .zero, columns: 4, pitch: 200, focus: .zero)
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    stage.makeTile = { _, _ in MacZoomMediaTile() }
    stage.ensureFace(4, opacity: 1); stage.ensureFace(6, opacity: 0)
    stage.show(6, animated: true)
    let incoming = stage.subviews.last!
    XCTAssertNil(incoming.layer?.animation(forKey: "zoom.fade"), "Blank pixels hold the composite")
    let pixels = macGridPhotoChildren(incoming).compactMap { $0 as? MacZoomMediaTile }
    XCTAssertFalse(pixels.isEmpty, "The incoming photo plane must contain real transition tiles")
    for tile in pixels {
      tile.show(NSImage(size: NSSize(width: 8, height: 8)))
    }
    let fade = incoming.layer?.animation(forKey: "zoom.fade") as? CAKeyframeAnimation
    XCTAssertNotNil(fade, "Displayed pixels schedule the curve through an event")
    XCTAssertEqual(fade?.speed, 1, "Core Animation continues while magnify rests")
    let start = fade?.beginTime
    stage.trackBlend(at: CACurrentMediaTime() + 0.1)
    XCTAssertEqual(incoming.layer?.animation(forKey: "zoom.fade")?.beginTime, start,
      "Geometry events must not restart the autonomous fade")
    stage.stop()
  }

  func testGroupedCaptionUsesOnlyNativeSizePositionKeyframes() {
    let stage = MacGridZoomStage(count: 90, anchor: 30, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 4, pitch: 200, focus: CGPoint(x: 250, y: 300))
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    let geometry: (Int) -> LibraryTimelineGeometry = { MacGridGeometry.make(count: 90, groups: [0: "First", 30: "Second", 60: "Third"], columns: $0, width: 804) }
    stage.groupedGeometry = geometry
    stage.referenceSide = { geometry($0).items[0].width }
    stage.makeTile = { _, _ in NSView() }
    stage.ensureFace(4, opacity: 1); stage.ensureFace(6, opacity: 0)
    let now = CACurrentMediaTime()
    stage.show(6, animated: true, at: now); stage.hurryBlend(within: 0.15, at: now)
    stage.settle(with: GridZoom.Settle(start: now, pitch: 200, focus: stage.focus, velocity: 0,
      targetPitch: 134, targetFocus: CGPoint(x: 250, y: 300))) {}
    let captions = stage.subviews.compactMap { $0 as? MacGridSectionHeader }
    XCTAssertFalse(captions.isEmpty)
    for caption in captions {
      let move = caption.layer?.animation(forKey: "zoom.caption") as? CAKeyframeAnimation
      XCTAssertEqual(move?.keyPath, "position.y")
      XCTAssertEqual(move?.values?.count, 73)
      XCTAssertTrue(CATransform3DIsIdentity(caption.layer!.transform))
      XCTAssertEqual(caption.frame.height, MacGridSectionHeader.dateHeight)
    }
    stage.stop()
  }

  func testSettleUsesSystemSpringsAndFreezesAtTheSharedAnalyticPose() {
    let stage = MacGridZoomStage(count: 90, anchor: 20, fraction: CGPoint(x: 0.3, y: 0.7),
      columns: 4, pitch: 200, focus: CGPoint(x: 250, y: 320))
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    stage.makeTile = { _, _ in NSView() }
    stage.ensureFace(4, opacity: 1)
    let now = CACurrentMediaTime()
    let model = GridZoom.Settle(start: now, pitch: stage.pitch, focus: stage.focus, velocity: -10000,
      targetPitch: 134, targetFocus: CGPoint(x: 250, y: 280))
    var completed = false
    stage.settle(with: model) { completed = true }
    XCTAssertEqual(stage.pitch, model.targetPitch, "The model layout is committed once at the destination")
    let clock = stage.layer?.animation(forKey: "zoom.settleClock") as? CABasicAnimation
    XCTAssertEqual(clock?.keyPath, "opacity")
    XCTAssertEqual(clock?.fromValue as? Int, 1)
    XCTAssertEqual(clock?.toValue as? Int, 1)
    XCTAssertNotNil(clock?.delegate, "Completion must not wait on virtualized off-screen tiles")
    let end = model.state(at: now + (clock?.duration ?? 0))
    XCTAssertLessThan(abs(end.pitch - model.targetPitch), 0.05)
    XCTAssertLessThan(hypot(end.focus.x - model.targetFocus.x, end.focus.y - model.targetFocus.y), 0.25)
    let tiles = stage.subviews.flatMap(macGridPhotoChildren)
    let springs = tiles.compactMap { $0.layer?.animation(forKey: "zoom.bounds.size.width") as? CASpringAnimation }
    XCTAssertFalse(springs.isEmpty)
    for spring in springs {
      XCTAssertEqual(spring.stiffness, GridZoom.settleOmega * GridZoom.settleOmega)
      XCTAssertEqual(spring.damping, 2 * GridZoom.settleOmega)
      XCTAssertEqual(spring.mass, 1)
    }
    let start = now + 0.2
    stage.releaseAnimationStarted(at: start)
    let interrupt = start + 0.12, pose = model.state(at: model.start + 0.12)
    stage.freeze(at: interrupt)
    XCTAssertEqual(stage.pitch, pose.pitch, accuracy: 0.000001)
    XCTAssertEqual(stage.focus.x, pose.focus.x, accuracy: 0.000001)
    XCTAssertEqual(stage.focus.y, pose.focus.y, accuracy: 0.000001)
    XCTAssertFalse(completed)
    XCTAssertNil(stage.layer?.animation(forKey: "zoom.settleClock"))
    XCTAssertTrue(stage.subviews.flatMap(macGridPhotoChildren).allSatisfy { $0.layer?.animation(forKey: "zoom.bounds.size.width") == nil })
    stage.stop()
  }

  func testSourceTileSpringsKeepNativeBadgeBoundsAndTwoPointGaps() {
    let source = GridTestSource()
    let stage = MacGridZoomStage(count: 16, anchor: 0, fraction: .zero, columns: 4, pitch: 200, focus: .zero)
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    stage.makeTile = { index, _ in
      let tile = MacSourceZoomTile()
      source.configure(tile.cell, id: "item-\(index)", pixels: 400, originalAspect: false)
      tile.cell.setState("needs_you")
      return tile
    }
    stage.ensureFace(4, opacity: 1)
    let now = CACurrentMediaTime()
    stage.settle(with: GridZoom.Settle(start: now, pitch: 200, focus: .zero, velocity: 0,
      targetPitch: 268, targetFocus: .zero)) {}
    let tiles = stage.subviews.flatMap(macGridPhotoChildren).compactMap { $0 as? MacSourceZoomTile }.sorted { $0.frame.minX < $1.frame.minX }
    let row = tiles.filter { $0.frame.minY == 0 }
    XCTAssertGreaterThanOrEqual(row.count, 2)
    for pair in zip(row, row.dropFirst()) {
      XCTAssertEqual(pair.1.frame.minX - pair.0.frame.maxX, 2, accuracy: 0.000001)
      let a = pair.0.layer!, b = pair.1.layer!
      let ax = a.animation(forKey: "zoom.position.x") as? CASpringAnimation
      let bx = b.animation(forKey: "zoom.position.x") as? CASpringAnimation
      let width = a.animation(forKey: "zoom.bounds.size.width") as! CASpringAnimation
      let x0 = (ax?.fromValue as? CGFloat) ?? a.position.x
      let x1 = (bx?.fromValue as? CGFloat) ?? b.position.x
      XCTAssertEqual(x1 - x0 - (width.fromValue as! CGFloat), 2, accuracy: 0.000001)
    }
    var checkedMarks = 0
    func verifyMarks(_ layer: CALayer) {
      if layer is MacBadgeLayer {
        checkedMarks += 1
        XCTAssertNil(layer.animation(forKey: "zoom.bounds.size.width"), "Native-size marks must not scale")
        XCTAssertNil(layer.animation(forKey: "zoom.transform.scale.x"))
      }
      for child in layer.sublayers ?? [] { verifyMarks(child) }
    }
    for tile in tiles { verifyMarks(tile.cell.view.layer!) }
    XCTAssertGreaterThan(checkedMarks, 0, "Check the source marks before AppKit attaches their backing view")
    stage.stop()
  }

  func testSourcePhotoSpringIncludesBackingLayersBeforeTheirAppKitCommit() {
    let tile = MacSourceZoomTile(); tile.wantsLayer = true
    tile.cell.configureUnavailable(id: "photo", label: "photo", video: false)
    tile.frame = CGRect(x: 20, y: 40, width: 198, height: 198)
    tile.layoutSubtreeIfNeeded(); tile.cell.viewDidLayout()
    let model = GridZoom.Settle(start: CACurrentMediaTime(), pitch: 300, focus: .zero, velocity: 0,
      targetPitch: 200, targetFocus: .zero)
    MacGridSpring.animate(tile, from: CGRect(x: 20, y: 40, width: 298, height: 298),
      derivative: CGRect(x: 0, y: 0, width: 1, height: 1), model: model, duration: 0.6)
    let photo = tile.cell.view.layer!.sublayers!.first!
    let width = photo.animation(forKey: "zoom.bounds.size.width") as? CASpringAnimation
    XCTAssertEqual((width?.fromValue as? NSNumber)?.doubleValue, 298)
    XCTAssertEqual((width?.toValue as? NSNumber)?.doubleValue, 198)
    XCTAssertEqual(photo.bounds.width, 198)
    XCTAssertNil(photo.animation(forKey: "zoom.transform.scale.x"))
    tile.cancel()
  }

  func testReleaseCompletesOnlyAfterFadeAndAdoptsExactTargetPose() {
    let stage = MacGridZoomStage(count: 16, anchor: 0, fraction: .zero, columns: 4, pitch: 200, focus: .zero)
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    stage.makeTile = { _, _ in
      let tile = MacZoomMediaTile(); tile.show(NSImage(size: NSSize(width: 8, height: 8))); return tile
    }
    stage.ensureFace(4, opacity: 1); stage.ensureFace(6, opacity: 0)
    let now = CACurrentMediaTime()
    stage.show(6, animated: true, at: now); stage.hurryBlend(within: 0.15, at: now)
    let model = GridZoom.Settle(start: now, pitch: 200, focus: .zero, velocity: 0,
      targetPitch: 200, targetFocus: .zero)
    var completed = false
    stage.settle(with: model) { completed = true }
    XCTAssertTrue(stage.subviews.contains { $0.layer?.animation(forKey: "zoom.fade") is CAKeyframeAnimation })
    stage.advance(to: now + 0.05); XCTAssertFalse(completed)
    stage.advance(to: now + 1); XCTAssertTrue(completed)
    XCTAssertFalse(stage.isBlending); XCTAssertEqual(stage.pitch, 200); XCTAssertEqual(stage.focus, .zero)
    XCTAssertEqual(stage.subviews.count, 1, "Prune outgoing faces only after the fade")
    stage.stop()
  }

  func testDensePhotosShareOneSpringAndKeepQuantizedTargetsAndNativePeriodText() {
    let canvas = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 944, height: 600))
    canvas.count = 2000
    canvas.factAt = { .init(key: "dense-\($0)", date: Date(timeIntervalSince1970: 1792495800 - Double($0) * 3600)) }
    let now = CACurrentMediaTime()
    let model = GridZoom.Settle(start: now, pitch: 44.5, focus: CGPoint(x: 472, y: 200), velocity: -300,
      targetPitch: 22, targetFocus: CGPoint(x: 472, y: 100))
    let columns = 42, leading = 5, anchor = 52
    func origin(_ pitch: CGFloat, _ focus: CGPoint) -> CGPoint {
      CGPoint(x: focus.x - CGFloat((anchor + leading) % columns) * pitch,
        y: focus.y - CGFloat((anchor + leading) / columns) * pitch)
    }
    canvas.render(columns: columns, origin: origin(model.targetPitch, model.targetFocus),
      pitch: model.targetPitch, visible: canvas.bounds, leading: leading)
    let photos = canvas.photoContentLayer
    let rectangles = photos.sublayers!.map(\.frame)
    XCTAssertGreaterThan(rectangles.count, 500)
    canvas.animateZoom(model, duration: 0.6, origin: origin)
    XCTAssertEqual(Set(photos.animationKeys() ?? []), ["zoom.position.x", "zoom.position.y", "zoom.transform.scale.x", "zoom.transform.scale.y"])
    XCTAssertTrue(photos.sublayers!.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    XCTAssertTrue(photos.sublayers!.allSatisfy { !$0.allowsEdgeAntialiasing && $0.edgeAntialiasingMask.isEmpty },
      "A shared fractional transform must not soften adjoining photo edges into transparent seams")
    XCTAssertEqual(photos.sublayers!.map(\.frame), rectangles, "The quantized target layout must not be changed by the transform")
    for label in canvas.periodReadingLayer.sublayers! {
      XCTAssertTrue(CATransform3DIsIdentity(label.transform))
      XCTAssertNil(label.animation(forKey: "zoom.transform.scale.x"))
      XCTAssertTrue(label.animation(forKey: "zoom.pill") is CAKeyframeAnimation)
      let move = label.animation(forKey: "zoom.pill") as! CAKeyframeAnimation
      for value in move.values as! [NSValue] {
        XCTAssertEqual(value.pointValue.x - label.bounds.width * label.anchorPoint.x, 12,
          accuracy: 0.001, "Period text keeps its reading margin while photos move horizontally")
      }
    }
    canvas.removeZoomAnimations()
    XCTAssertTrue((photos.animationKeys() ?? []).isEmpty)
    XCTAssertTrue(CATransform3DIsIdentity(photos.transform))
    XCTAssertEqual(photos.position, .zero)
    XCTAssertEqual(photos.sublayers!.map(\.frame), rectangles)
    canvas.reset()
  }

  func testDensePeriodCaptionUsesItsRenderedPinDuringSettle() {
    let canvas = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 944, height: 600))
    canvas.count = 90
    canvas.factAt = { .init(key: "pin-\($0)", date: Date(timeIntervalSince1970: 1792495800)) }
    canvas.render(columns: 21, origin: .zero, pitch: 22, visible: canvas.bounds, pinTop: 6)
    let model = GridZoom.Settle(start: CACurrentMediaTime(), pitch: 44, focus: .zero, velocity: 0,
      targetPitch: 22, targetFocus: .zero)
    canvas.animateZoom(model, duration: 0.6) { _, _ in .zero }
    let labels = canvas.periodReadingLayer.sublayers!
    XCTAssertFalse(labels.isEmpty)
    for label in labels {
      let move = label.animation(forKey: "zoom.pill") as! CAKeyframeAnimation
      let first = (move.values!.first as! NSValue).pointValue
      XCTAssertEqual(first.y - label.bounds.height * label.anchorPoint.y, 6)
      XCTAssertEqual(label.frame.minY, 6)
    }
    canvas.removeZoomAnimations(); canvas.reset()
  }

  func testDensePeriodCaptionKeepsReadingMarginAcrossGestureReversal() {
    let canvas = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 944, height: 600))
    canvas.count = 90
    canvas.factAt = { .init(key: "margin-\($0)", date: Date(timeIntervalSince1970: 1792495800)) }
    for x in [0.0, -80, -160, -80, 0, 80] {
      canvas.render(columns: 21, origin: CGPoint(x: x, y: 0), pitch: 22, visible: canvas.bounds, pinTop: 6)
      let labels = canvas.periodReadingLayer.sublayers!
      XCTAssertFalse(labels.isEmpty)
      for label in labels {
        XCTAssertEqual(label.frame.minX, 12)
        XCTAssertEqual(label.frame.minY, 6)
      }
    }
    canvas.reset()
  }

  func testFractionalDenseReleaseKeepsExactPixelEdgesWithTileSprings() {
    let canvas = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 944, height: 600))
    canvas.count = 120
    canvas.render(columns: 21, origin: .zero, pitch: 22, visible: canvas.bounds)
    let photos = canvas.photoContentLayer
    let target = photos.sublayers!.map(\.frame)
    let model = GridZoom.Settle(start: CACurrentMediaTime(), pitch: 44.37, focus: .zero, velocity: -200,
      targetPitch: 22, targetFocus: .zero)
    canvas.animateZoom(model, duration: 0.6) { _, focus in focus }
    XCTAssertTrue((photos.animationKeys() ?? []).isEmpty, "Alternating quantized widths cannot share a scale")
    XCTAssertTrue(photos.sublayers!.contains { $0.animation(forKey: "zoom.transform.scale.x") is CASpringAnimation })
    XCTAssertTrue(photos.sublayers!.allSatisfy { !$0.allowsEdgeAntialiasing && $0.edgeAntialiasingMask.isEmpty },
      "Per-tile fractional springs need the same seam-free shared edges as the mosaic transform")
    XCTAssertEqual(photos.sublayers!.map(\.frame), target)
    canvas.removeZoomAnimations()
    XCTAssertTrue(photos.sublayers!.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    canvas.reset()
  }

  func testDenseHandoffRetainsPixelsOnlyForTheSameLattice() {
    let source = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 944, height: 600))
    let destination = MacDenseCanvas(frame: source.frame)
    for canvas in [source, destination] {
      canvas.pipeline = ThumbnailPipeline()
      canvas.factAt = { .init(key: "maczoom-handoff-test-\($0)", date: nil) }
      canvas.count = 90; canvas.render(columns: 21, origin: .zero, pitch: 45, visible: canvas.bounds)
    }
    let image = NSImage(size: CGSize(width: 8, height: 8))
    for tile in source.photoContentLayer.sublayers! { tile.contents = image }
    XCTAssertEqual(destination.loadedFraction, 0)
    destination.retainDisplayedPixels(from: source)
    XCTAssertEqual(destination.loadedFraction, 1)
    destination.reset()
    destination.factAt = { .init(key: "different-handoff-test-\($0)", date: nil) }
    destination.render(columns: 21, origin: .zero, pitch: 45, visible: destination.bounds)
    destination.retainDisplayedPixels(from: source)
    XCTAssertEqual(destination.loadedFraction, 0, "Equal indexes must not substitute different assets")
    destination.reset()
    destination.render(columns: 43, origin: .zero, pitch: 22, visible: destination.bounds)
    destination.retainDisplayedPixels(from: source)
    XCTAssertEqual(destination.loadedFraction, 0, "A different lattice must load its own pixels")
    source.reset(); destination.reset()
  }

  func testCompletedZoomReleasesStageSoTheNextToolbarDensityCanApply() async {
    let source = GridTestSource(); source.identifiers = (0..<30).map { "item-\($0)" }
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0, receiverID: nil, columns: 9)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 600))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 88); layout.requestedColumns = 9
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    scroll.documentView = collection; mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    for columns in [6, 4, 3, 4, 6, 9, 3] {
      coordinator.parent.columns = columns
      coordinator.animateLayout(columns: columns)
      guard let stage = coordinator.zoomStage else { XCTFail("Missing zoom stage"); continue }
      stage.advance(to: CACurrentMediaTime() + 2)
      collection.layoutSubtreeIfNeeded()
      try? await Task.sleep(for: .milliseconds(20))
      XCTAssertNil(coordinator.zoomStage, "Cleanup must not depend on a display clock in an inactive window")
      XCTAssertNil(coordinator.animationTarget)
      XCTAssertEqual(layout.columns, columns)
    }
    coordinator.removeZoomStage()
  }

  func testGroupedZoomHasOneNativeSizeHeaderAndExactSettledGeometry() {
    for count in [1, 2, 5, 12, 90] {
      let groups = Dictionary(uniqueKeysWithValues: stride(from: 0, to: count, by: 3).map { ($0, "Section \($0)") })
      let width: CGFloat = 804
      func geometry(_ columns: Int) -> LibraryTimelineGeometry {
        MacGridGeometry.make(count: count, groups: groups, columns: columns, width: width, headerHeights: [0: 138])
      }
      func pitch(_ columns: Int) -> CGFloat { geometry(columns).items[0].width + 2 }
      let g = geometry(3), anchor = g.items[0]
      let stage = MacGridZoomStage(count: count, anchor: 0, fraction: CGPoint(x: 0.5, y: 0.5),
        columns: 3, pitch: pitch(3), focus: CGPoint(x: anchor.midX, y: anchor.midY))
      stage.frame = CGRect(x: 0, y: 0, width: width, height: 1200)
      stage.referenceSide = { geometry($0).items[0].width }
      stage.groupedGeometry = geometry
      stage.makeTile = { _, _ in NSView() }
      stage.ensureFace(3, opacity: 1)
      for columns in [4, 6, 9, 6, 4, 3] {
        stage.ensureFace(columns, opacity: 0)
        let now = CACurrentMediaTime()
        stage.show(columns, animated: true, at: now)
        for frame in 0...60 {
          stage.advance(to: now + Double(frame) / 60)
          let captions = stage.subviews.compactMap { $0 as? MacGridSectionHeader }
          XCTAssertEqual(captions.count, Set(captions.map { ObjectIdentifier($0) }).count)
          for caption in captions {
            XCTAssertEqual(caption.frame.minX, 0, "The pinned surface must not expose photos at either viewport edge")
            XCTAssertEqual(caption.frame.maxX, width)
          }
          for h in geometry(columns).headers {
            if let rect = stage.headerFrame(at: h.firstItem) { XCTAssertEqual(rect.height, h.frame.height) }
          }
          XCTAssertFalse(stage.subviews.contains { face in face.subviews.contains { $0 is MacGridSectionHeader } }, "Caption must not belong to a crossfading face")
        }
        let destination = geometry(columns)
        stage.pitch = pitch(columns)
        stage.focus = CGPoint(x: destination.items[0].midX, y: destination.items[0].midY)
        stage.show(columns, animated: false); stage.render()
        for header in destination.headers {
          if let rect = stage.headerFrame(at: header.firstItem) {
            XCTAssertEqual(rect.minY, header.frame.minY, accuracy: 0.001)
            XCTAssertEqual(rect.height, header.frame.height)
            XCTAssertEqual(rect.minX, 0)
            XCTAssertEqual(rect.width, width)
          }
        }
      }
      stage.stop()
    }
  }

  func testToolbarStageStartsWithinDisplayPixelOfClampedPhotoPointInShortGrid() async {
    for count in [1, 2, 5, 12] {
      for grouped in [false, true] {
        let source = GridTestSource(); source.identifiers = (0..<count).map { "item-\($0)" }
        if grouped { source.introduction = AnyView(Text("Folder summary")) }
        let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0, receiverID: nil, columns: 9)
        let coordinator = MacMediaGrid.Coordinator(grid)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 600))
        let collection = LibraryCollectionView(frame: scroll.bounds)
        let layout = LibraryTimelineLayout(mode: .all, target: 88); layout.requestedColumns = 9
        collection.collectionViewLayout = layout
        collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
        collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
        scroll.documentView = collection; mountMacGridCollection(collection, coordinator: coordinator)
        coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
        try? await Task.sleep(for: .milliseconds(50))
        collection.layoutSubtreeIfNeeded()
        coordinator.animateLayout(columns: 6)
        guard let stage = coordinator.zoomStage else { XCTFail("Missing live zoom stage"); continue }
        // A system animation commits destination frames immediately. Interrupt
        // at release time to inspect the exact entry pose without polling CA.
        stage.freeze(at: 0)
        var compared = 0
        for index in 0..<count {
          let settled = collection.convert(layout.frame(at: index), to: scroll)
          // The lattice also carries chronological neighbours outside its
          // natural columns. Compare the canonical on-screen copy.
          let copies = stage.subviews.flatMap(macGridPhotoChildren).compactMap { $0 as? MacSourceZoomTile }
            .filter { ($0.cell.presentationID ?? $0.cell.assetID) == source.identifiers[index] }
            .map { $0.convert($0.bounds, to: scroll) }
          if let rendered = copies.min(by: {
            hypot($0.minX - settled.minX, $0.minY - settled.minY) < hypot($1.minX - settled.minX, $1.minY - settled.minY)
          }) {
            XCTAssertEqual(rendered.minY, settled.minY, accuracy: 0.5)
            compared += 1
          }
        }
        XCTAssertGreaterThan(compared, 0)
        coordinator.removeZoomStage()
      }
    }
  }

  func testOverviewStageStartsWithTheSettledGaplessPitch() async {
    for count in [1, 2, 5, 12] {
      for columns in MacLibraryDensity.overview(forWidth: 804) + [20, 40] {
        let source = GridTestSource(); source.identifiers = (0..<count).map { "item-\($0)" }
        let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0, receiverID: nil, columns: columns)
        let coordinator = MacMediaGrid.Coordinator(grid)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 600))
        let collection = LibraryCollectionView(frame: scroll.bounds)
        let layout = LibraryTimelineLayout(mode: .all, target: 20)
        layout.requestedColumns = columns; layout.denseThreshold = MacLibraryDensity.denseThreshold
        collection.collectionViewLayout = layout
        collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
        scroll.documentView = collection; mountMacGridCollection(collection, coordinator: coordinator)
        coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
        try? await Task.sleep(for: .milliseconds(50))
        collection.layoutSubtreeIfNeeded()
        coordinator.animateLayout(columns: 9)
        guard let stage = coordinator.zoomStage else { XCTFail("Missing overview stage"); continue }
        stage.freeze(at: 0)
        XCTAssertEqual(stage.pitch, layout.frame(at: 0).width, accuracy: 0.000001,
          "A gapless overview must not gain an ordinary-grid gap on entry")
        coordinator.removeZoomStage()
      }
    }
  }

  func testDenseRemainderFillsViewportAndKeepsHitAnchorAndHeightConsistent() async {
    for width: CGFloat in [947, 959] {
      for columns in [20, 40, 43] {
        let count = columns * 3
        let source = GridTestSource(); source.identifiers = (0..<count).map { "item-\($0)" }
        let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
          receiverID: nil, columns: columns)
        let coordinator = MacMediaGrid.Coordinator(grid)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 300))
        let collection = LibraryCollectionView(frame: scroll.bounds)
        let layout = LibraryTimelineLayout(mode: .all, target: 20)
        layout.requestedColumns = columns; layout.denseThreshold = MacLibraryDensity.denseThreshold
        collection.collectionViewLayout = layout
        collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
        scroll.documentView = collection; mountMacGridCollection(collection, coordinator: coordinator)
        coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
        try? await Task.sleep(for: .milliseconds(50))
        for leading in [0, 3] {
          coordinator.leading = leading; layout.leadingSlots = leading
          layout.adopt(mode: .all, columns: columns)
          coordinator.ensureDocumentHeight(); collection.layoutSubtreeIfNeeded(); coordinator.updateDense()
          let pitch = width / CGFloat(columns), lastInRow = columns - leading - 1
          XCTAssertEqual(layout.frame(at: lastInRow).maxX, width, accuracy: 0.000001)
          XCTAssertEqual(layout.frame(at: 0).width, pitch, accuracy: 0.000001)
          XCTAssertEqual(coordinator.denseIndex(at: CGPoint(x: width - 0.25, y: 4 + pitch / 2)), lastInRow,
            "The remainder beside the last column must contain the last photo, not an empty hit region")
          let tiles = coordinator.denseCanvas!.photoContentLayer.sublayers!
          let firstRow = tiles.filter { abs($0.frame.minY - 4) < 0.001 }
          XCTAssertEqual(firstRow.map { $0.frame.maxX }.max()!, width, accuracy: 0.000001,
            "The rendered pixel edges and the native geometry must fill the same width")
          XCTAssertEqual(coordinator.settledContentHeight, layout.collectionViewContentSize.height, accuracy: 0.000001)
        }
        coordinator.animateLayout(columns: 9)
        guard let stage = coordinator.zoomStage else { XCTFail("Missing overview stage"); continue }
        stage.freeze(at: 0)
        XCTAssertEqual(stage.pitch, width / CGFloat(columns), accuracy: 0.000001,
          "The stage must enter at the same fractional pitch as browsing and hit testing")
        coordinator.removeZoomStage()
      }
    }
  }

  func testDenseStageCopiesKeepAssetIdentityAndNativeBrowsingBounds() {
    let canvas = MacDenseCanvas(frame: CGRect(x: 0, y: 0, width: 804, height: 300))
    canvas.count = 2000
    canvas.factAt = { .init(key: "copy-\($0)", date: nil) }
    let origin = CGPoint(x: 202, y: -400), pitch: CGFloat = 20
    canvas.render(columns: 20, origin: origin, pitch: pitch, visible: canvas.bounds, extendsRows: true)
    var images: [Int: CGImage] = [:], copies: [Int: Int] = [:]
    for tile in canvas.photoContentLayer.sublayers! {
      let point = CGPoint(x: tile.frame.midX, y: tile.frame.midY)
      let index = Int(floor((point.y - origin.y) / pitch)) * 20 + Int(floor((point.x - origin.x) / pitch))
      XCTAssertTrue((0..<canvas.count).contains(index))
      XCTAssertEqual(canvas.displayedTile(at: point, visible: tile.frame)?.index, index)
      copies[index, default: 0] += 1
      if images[index] == nil {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: CGFloat(index % 255) / 255, green: 0.2, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1)); images[index] = context.makeImage()!
      }
      tile.contents = images[index]
    }
    XCTAssertTrue(copies.values.contains { $0 > 1 }, "A photo may occupy multiple distinct chronological slots")
    for x: CGFloat in [0.25, 803.75] {
      let point = CGPoint(x: x, y: 150)
      XCTAssertTrue(canvas.displayedTile(at: point, visible: canvas.bounds)!.frame.contains(point))
    }
    let native = MacDenseCanvas(frame: canvas.bounds); native.count = canvas.count; native.factAt = canvas.factAt
    native.render(columns: 20, origin: origin, pitch: pitch, visible: native.bounds)
    XCTAssertTrue(native.retainDisplayedPixels(from: canvas))
    for tile in native.photoContentLayer.sublayers! {
      XCTAssertGreaterThanOrEqual(tile.frame.minX, origin.x)
      XCTAssertLessThanOrEqual(tile.frame.maxX, origin.x + 20 * pitch)
      let index = native.displayedTile(at: CGPoint(x: tile.frame.midX, y: tile.frame.midY), visible: tile.frame)!.index
      XCTAssertTrue(tile.contents as AnyObject? === images[index], "Pixel adoption uses asset identity, not a neighboring slot")
    }
    native.factAt = { .init(key: "replacement-\($0)", date: nil) }
    native.render(columns: 20, origin: origin, pitch: pitch, visible: native.bounds)
    XCTAssertTrue(native.retainDisplayedPixels(from: canvas))
    XCTAssertTrue(native.photoContentLayer.sublayers!.allSatisfy { $0.contents == nil },
      "A changed content key must reject old pixels even when the index and slot are unchanged")
    for count in [1, 27] {
      canvas.count = count
      canvas.render(columns: 20, origin: CGPoint(x: 202, y: 0), pitch: pitch,
        visible: canvas.bounds, leading: 3, extendsRows: true)
      for tile in canvas.photoContentLayer.sublayers! {
        let hit = canvas.displayedTile(at: CGPoint(x: tile.frame.midX, y: tile.frame.midY), visible: tile.frame)!
        XCTAssertTrue((0..<count).contains(hit.index))
        XCTAssertGreaterThanOrEqual(tile.frame.minY, 0)
        XCTAssertLessThanOrEqual(tile.frame.maxY, CGFloat((count - 1 + 3) / 20 + 1) * pitch)
      }
    }
    native.reset(); canvas.reset()
  }

  private func denseCoverageStage() -> MacGridZoomStage {
    let stage = MacGridZoomStage(count: 6000, anchor: 1010, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 20, pitch: 25, focus: CGPoint(x: 402, y: 150))
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 300)
    stage.referenceSide = { 804 / CGFloat($0) }
    stage.ensureFace(20, opacity: 0.6); stage.ensureFace(40, opacity: 0.4)
    return stage
  }

  func testDenseEdgeCopyReanchorKeepsBothFacesInPlace() {
    for x: CGFloat in [35, 769] {
      let stage = denseCoverageStage()
      let canvases = stage.subviews.flatMap(macGridPhotoChildren).compactMap { $0 as? MacDenseCanvas }
      let point = CGPoint(x: x, y: 125)
      let hit = canvases[0].displayedTile(at: point, visible: stage.bounds)!
      XCTAssertTrue(hit.frame.contains(point), "Both sides of the narrowed face need real chronological copies")
      let expected = CGPoint(x: (point.x - hit.frame.minX) / hit.frame.width,
        y: (point.y - hit.frame.minY) / hit.frame.height)
      let before = Dictionary(uniqueKeysWithValues: canvases.flatMap { $0.photoContentLayer.sublayers! }
        .filter { $0.frame.intersects(stage.bounds) }.map { (ObjectIdentifier($0), $0.frame) })
      stage.reanchor(to: point)
      XCTAssertEqual(stage.anchor, hit.index)
      XCTAssertEqual(stage.fraction.x, expected.x, accuracy: 0.000001)
      XCTAssertEqual(stage.fraction.y, expected.y, accuracy: 0.000001)
      let after = Dictionary(uniqueKeysWithValues: canvases.flatMap { $0.photoContentLayer.sublayers! }
        .map { (ObjectIdentifier($0), $0.frame) })
      for (id, frame) in before { XCTAssertEqual(after[id], frame, "Taking over a side copy must not rewrap either face") }
      stage.stop()
    }
  }

  func testDensePreparedReleaseCoversEveryFaceThroughReversal() {
    let stage = denseCoverageStage()
    func scalar(_ layer: CALayer, _ key: String, _ time: CGFloat) -> CGFloat {
      var value = CGFloat((layer.value(forKeyPath: key) as! NSNumber).doubleValue)
      for name in ["zoom." + key, "zoom.velocity." + key] {
        guard let animation = layer.animation(forKey: name) as? CASpringAnimation else { continue }
        let from = CGFloat((animation.fromValue as! NSNumber).doubleValue)
        let to = CGFloat((animation.toValue as! NSNumber).doubleValue)
        let omega = sqrt(animation.stiffness / animation.mass), displacement = from - to
        let velocity = animation.initialVelocity * (to - from)
        let sample = to + (displacement + (velocity + omega * displacement) * time) * exp(-omega * time)
        value = animation.isAdditive ? value + sample : sample
      }
      return value
    }
    var now = CACurrentMediaTime()
    for columns in [40, 20, 40] {
      stage.show(columns, animated: true, at: now); stage.hurryBlend(within: 0.26, at: now)
      let model = GridZoom.Settle(start: now, pitch: stage.pitch, focus: stage.focus,
        velocity: stage.frozenPitchVelocity, targetPitch: 804 / CGFloat(columns), targetFocus: stage.focus)
      stage.settle(with: model) {}
      let canvases = stage.subviews.flatMap(macGridPhotoChildren).compactMap { $0 as? MacDenseCanvas }
      for time: CGFloat in [0, 0.04, 0.12, 0.3, CGFloat(model.duration)] {
        for canvas in canvases {
          let photos = canvas.photoContentLayer
          let px = scalar(photos, "position.x", time), py = scalar(photos, "position.y", time)
          let psx = scalar(photos, "transform.scale.x", time), psy = scalar(photos, "transform.scale.y", time)
          let frames = photos.sublayers!.map { tile -> CGRect in
            let w = tile.bounds.width * scalar(tile, "transform.scale.x", time)
            let h = tile.bounds.height * scalar(tile, "transform.scale.y", time)
            return CGRect(x: px + (scalar(tile, "position.x", time) - w * tile.anchorPoint.x) * psx,
              y: py + (scalar(tile, "position.y", time) - h * tile.anchorPoint.y) * psy,
              width: w * psx, height: h * psy)
          }
          for x: CGFloat in [0.25, 80, 402, 724, 803.75] {
            for y: CGFloat in [0.25, 75, 150, 225, 299.75] {
              XCTAssertTrue(frames.contains { $0.contains(CGPoint(x: x, y: y)) },
                "Every active face must cover the viewport along its prepared native spring, including side overscan")
            }
          }
        }
      }
      stage.releaseAnimationStarted(at: now)
      stage.freeze(at: now + 0.08)
      stage.reanchor(to: CGPoint(x: columns == 40 ? 35 : 769, y: 125))
      now += 0.08
    }
    stage.stop()
  }

  func testMonthCoversReadOldestFirstAndKeepTheirDrillDownTokens() {
    let period = LibraryCalendarPeriod(id: "month", date: nil, title: "",
      tokens: ["20", "19", "18", "17", "16", "15"], covers: [0, 24, 48, 72, 96, 120])
    let ordered = MacCalendarGrid.chronologicalMonth(period)
    XCTAssertEqual(ordered.tokens, ["15", "16", "17", "18", "19", "20"])
    XCTAssertEqual(ordered.covers, [120, 96, 72, 48, 24, 0])
    for count in 1...6 {
      for mirrored in [false, true] {
        let slots = MacCalendarGrid.monthCoverSlots(count: count, mirrored: mirrored)
        XCTAssertEqual(slots.count, count)
        for pair in zip(slots, slots.dropFirst()) {
          XCTAssertTrue(pair.0.1 < pair.1.1 || (pair.0.1 == pair.1.1 && pair.0.0 < pair.1.0),
            "Days must advance left to right, then top to bottom, including mirrored compositions")
        }
      }
    }
  }

  func testAspectAvailabilityAtEveryDensityAndPlaceholder() {
    for columns in MacLibraryDensity.grid {
      XCTAssertTrue(MacLibraryDensity.canChangeAspect(level: .all, columns: columns, hasPhotos: true))
    }
    for columns in [12, 14, 20, 40, 80] {
      XCTAssertFalse(MacLibraryDensity.canChangeAspect(level: .all, columns: columns, hasPhotos: true))
    }
    for level in MacLibraryLevel.allCases {
      XCTAssertFalse(MacLibraryDensity.canChangeAspect(level: level, columns: 3, hasPhotos: false))
    }
    for level in [MacLibraryLevel.years, .months] {
      XCTAssertFalse(MacLibraryDensity.canChangeAspect(level: level, columns: 3, hasPhotos: true))
    }
  }

  func testFolderSummaryHeightMatchesLaidOutHostingView() {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = []
    let folder = FolderSource(id: "folder", name: String(repeating: "Long folder name ", count: 8),
      bookmark: Data(), automatic: false, enabled: true, receiver: nil, lastCheck: nil)
    let summary = AnyView(FolderSectionHeader(folders: folders, source: folder, settings: { _ in }, stop: { _ in }))
    var previous: CGFloat = .greatestFiniteMagnitude
    for gridWidth: CGFloat in [320, 460, 760, 1180] {
      let width = MacGridSectionHeader.contentWidth(for: gridWidth)
      let measured = MacGridSectionHeader.fittingHeight(introduction: summary, width: gridWidth)
      let header = MacGridSectionHeader(frame: CGRect(x: 0, y: 0, width: gridWidth, height: measured))
      header.configure(title: "October 26, 2026", introduction: summary)
      header.layoutSubtreeIfNeeded()
      guard let host = header.summary else { XCTFail("Missing folder summary"); return }
      XCTAssertEqual(host.frame.width, width)
      XCTAssertEqual(host.frame.minX, MacGridSectionHeader.inset)
      XCTAssertEqual(host.frame.maxX, gridWidth - MacGridSectionHeader.inset)
      XCTAssertEqual(host.frame.height, ceil(host.fittingSize.height), accuracy: 1)
      XCTAssertEqual(measured, ceil(host.fittingSize.height) + MacGridSectionHeader.dateHeight, accuracy: 1)
      XCTAssertLessThanOrEqual(measured, previous)
      previous = measured
    }
  }

  func testNativePinnedHeaderSurfaceCoversTheViewportThroughSectionPushOff() async {
    let source = GridTestSource(); source.identifiers = (0..<90).map { "item-\($0)" }
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 600))
    let collection = LibraryCollectionView(frame: CGRect(x: 0, y: 0, width: 804, height: 5000))
    let layout = LibraryTimelineLayout(mode: .all, target: 135)
    collection.collectionViewLayout = layout; scroll.documentView = collection
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    layout.groups = [0: "First", 18: "Second", 42: "Third"]
    layout.headerHeights = [0: 154, 18: 130, 42: 174]
    layout.revision += 1
    for columns in [3, 4, 6, 9] {
      layout.requestedColumns = columns; layout.adopt(mode: .all, columns: columns); layout.prepare()
      let geometry = MacGridGeometry.make(count: 90, groups: layout.groups, columns: columns,
        width: scroll.contentSize.width, headerHeights: layout.headerHeights)
      let next = geometry.headers[1].frame.minY
      for offset in [CGFloat.zero, 100, next - 100, next + 20] {
        scroll.contentView.scroll(to: CGPoint(x: 0, y: offset))
        layout.invalidateLayout(); layout.prepare()
        let a = layout.layoutAttributesForSupplementaryView(ofKind: LibraryTimelineLayout.headerKind,
          at: IndexPath(item: 0, section: 0))!.frame
        XCTAssertEqual(a.minX, 0)
        XCTAssertEqual(a.maxX, scroll.contentSize.width)
        XCTAssertLessThanOrEqual(a.maxY, next, "The complete background leaves with its section")
      }
    }
  }

  func testFirstLayoutDefersHeaderMeasurementUntilViewportHasWidth() async {
    let source = GridTestSource()
    source.introduction = AnyView(Text(String(repeating: "Wrapped folder summary ", count: 20)))
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: .zero)
    let collection = LibraryCollectionView(frame: .zero)
    let layout = LibraryTimelineLayout(mode: .all, target: 135); layout.requestedColumns = 4
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    scroll.documentView = collection; mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    XCTAssertTrue(coordinator.dataSource!.snapshot().itemIdentifiers.isEmpty)
    scroll.setFrameSize(NSSize(width: 804, height: 600))
    coordinator.contentResized()
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(coordinator.dataSource!.snapshot().itemIdentifiers, source.identifiers)
    XCTAssertEqual(layout.headerHeights, source.headerHeights(width: scroll.contentSize.width))
    scroll.setFrameSize(NSSize(width: 460, height: 600))
    coordinator.contentResized()
    XCTAssertEqual(layout.headerHeights, source.headerHeights(width: scroll.contentSize.width))
  }

  func testReadOnlyAlbumCannotEnterSelection() {
    let source = GridTestSource()
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 4, selecting: false, readOnly: true)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let collection = LibraryCollectionView(); mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.ids = source.identifiers
    coordinator.beginSelection(at: IndexPath(item: 0, section: 0))
    coordinator.toggleSelection(at: IndexPath(item: 0, section: 0))
    XCTAssertTrue(source.selection.isEmpty)
  }

  func testSourceSectionsShareTileGeometryAndPreservePartialRows() {
    let geometry = MacGridGeometry.make(count: 8, groups: [0: "Today", 3: "Yesterday"], columns: 4, width: 804)
    XCTAssertEqual(geometry.headers.map(\.firstItem), [0, 3])
    XCTAssertEqual(geometry.items[0].size, geometry.items[3].size)
    XCTAssertGreaterThan(geometry.items[3].minY, geometry.items[0].maxY)
    XCTAssertEqual(geometry.items[3].minX, geometry.items[0].minX)
    let summary = MacGridGeometry.make(count: 8, groups: [0: "Today", 3: "Yesterday"], columns: 4, width: 804, headerHeights: [0: 150])
    XCTAssertEqual(summary.items[0].minY - geometry.items[0].minY, 106)
    XCTAssertEqual(summary.items[0].width, geometry.items[0].width)
  }

  func testMarkRefreshKeepsNativeCellAndSelection() async {
    let source = GridTestSource()
    let navigation = MacLibraryNavigation()
    let grid = MacMediaGrid(source: source, navigation: navigation, queueRevision: 0, receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 804, height: 600))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 135); layout.requestedColumns = 4
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind, withIdentifier: .init("timeline"))
    scroll.documentView = collection; mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(100))
    collection.layoutSubtreeIfNeeded()
    let path = IndexPath(item: 0, section: 0)
    guard let before = collection.item(at: path) as? PhotoCell else { XCTFail("No visible native cell"); return }
    source.mark = "needs_you"; source.selection = ["a"]
    coordinator.applyItems(scroll: scroll, layout: layout)
    XCTAssertTrue(collection.item(at: path) === before, "A mark observation cannot replace the cell")
    XCTAssertEqual(coordinator.dataSource?.snapshot().itemIdentifiers, ["a", "b", "c"])
    XCTAssertEqual(coordinator.selectedPaths(), [path])
    source.identifiers = ["c", "a", "new"]
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(400))
    XCTAssertEqual(coordinator.dataSource?.snapshot().itemIdentifiers, ["c", "a", "new"])
    XCTAssertEqual(coordinator.selectedPaths(), [IndexPath(item: 1, section: 0)])
    XCTAssertEqual(source.selection, ["a"])
  }

  func testHistoryRefreshKeepsLoadedPagesAndSourceIdentity() async {
    let previous = BackupEnvironment.core
    defer { BackupEnvironment.core = previous }
    let core = GridHistoryCore(); BackupEnvironment.core = core
    let model = BackupHistoryModel()
    XCTAssertFalse(model.resolved, "The first request has not established an empty history")
    await model.reload(receiver: "test-receiver")
    XCTAssertTrue(model.resolved)
    let current = model.photos.first!.job!
    let prior = BackupJob(id: -1, asset: current.asset, state: "queued", confirmedBytes: 0,
      errorCode: nil, receiverID: current.receiverID)
    XCTAssertEqual(model.matching(HistoryPhoto(job: prior))?.id, model.photos.first?.id,
      "An earlier record for the same source follows its current task identity")
    let preparation = SourceBrowserItem(cursor: 0, source: current.asset.source_id,
      revision: current.asset.revision, retry_at: nil, state: nil)
    let preparing = HistoryPhoto(BackupTaskItem(id: "preparing", cursor: 0, sort_value: nil,
      job: nil, preparation: preparation))!
    XCTAssertEqual(model.matching(preparing)?.id, model.photos.first?.id)
    let edited = SourceBrowserItem(cursor: 0, source: current.asset.source_id,
      revision: "old-revision", retry_at: nil, state: nil)
    let oldPhoto = HistoryPhoto(BackupTaskItem(id: "old", cursor: 0, sort_value: nil,
      job: nil, preparation: edited))!
    XCTAssertNil(model.matching(oldPhoto), "An edited source is not the same recorded photo")
    let state = MacHistoryGridState()
    let firstPage = MacHistoryGridSource(history: model, state: state, filter: "all", type: .all, search: "")
    XCTAssertTrue(firstPage.startsAtEnd)
    XCTAssertEqual(firstPage.identifiers.last, "job-0")
    let grid = MacMediaGrid(source: firstPage, navigation: state.navigation, queueRevision: 0,
      receiverID: nil, columns: 4)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 420))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 200)
    layout.requestedColumns = 4; collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    scroll.documentView = collection
    mountMacGridCollection(collection, coordinator: coordinator)
    coordinator.parent.reducedMotionOverride = true
    coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    let newestOffset = coordinator.settledContentHeight - scroll.contentView.bounds.height
    XCTAssertGreaterThan(newestOffset, 0)
    XCTAssertEqual(scroll.contentView.bounds.minY, newestOffset, accuracy: 0.5)
    firstPage.didDisplay(firstPage.identifiers.suffix(24))
    await Task.yield()
    XCTAssertEqual(model.photos.count, 200, "Opening at the latest end must not fetch older pages")
    coordinator.pinnedToNewest = false
    let anchor = "job-188"
    let oldFrame = layout.frame(at: firstPage.identifiers.firstIndex(of: anchor)!)
    scroll.contentView.scroll(to: CGPoint(x: 0, y: oldFrame.minY + 8))
    coordinator.rememberScroll()
    let retainedAnchor = firstPage.scroll.anchor
    let retainedInset = firstPage.scroll.inset
    firstPage.didDisplay(firstPage.identifiers.dropFirst().prefix(24))
    for _ in 0..<50 where model.photos.count == 200 { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(model.photos.count, 220, "Older pages load from the timeline's top edge")
    let expanded = MacHistoryGridSource(history: model, state: state, filter: "all", type: .all, search: "")
    XCTAssertEqual(Array(expanded.identifiers.suffix(firstPage.identifiers.count - 1)), Array(firstPage.identifiers.dropFirst()))
    coordinator.parent.source = expanded
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertNotNil(retainedAnchor)
    if let retainedAnchor, let newIndex = expanded.identifiers.firstIndex(of: retainedAnchor) {
      XCTAssertEqual(scroll.contentView.bounds.minY, layout.frame(at: newIndex).minY + retainedInset, accuracy: 0.5)
    }
    core.reordered = true
    await model.reload(receiver: "test-receiver")
    XCTAssertEqual(model.photos.count, 220, "Observations must retain the loaded browsing window")
    XCTAssertEqual(model.photos.first?.id, "job-219")
    XCTAssertFalse(model.hasMore)
    let source = MacHistoryGridSource(history: model, state: state, filter: "all", type: .all, search: "")
    XCTAssertEqual(source.identifiers.count, 220)
    XCTAssertEqual(source.identifiers.first, "job-7", "Needs You reasons precede ordinary records")
    XCTAssertEqual(source.identifiers.filter { $0 == "job-7" }.count, 1)
    XCTAssertEqual(source.groups.count, 2, "Only the reason and its trailing section break remain")
    XCTAssertEqual(source.flowHeaders, Set(source.groups.keys))
    XCTAssertEqual(source.identifiers.dropFirst().first, "job-219")
    XCTAssertEqual(source.identifiers.last, "job-0", "The latest update is at the end")
    XCTAssertFalse(MacHistoryGridSource(history: model, state: state, filter: "attention", type: .all, search: "").startsAtEnd)
    XCTAssertEqual(source.date("job-0"), Date(timeIntervalSince1970: 1_792_495_800))
    XCTAssertNotEqual(source.date("job-0"), source.photos["job-0"]?.takenAt,
      "History dates describe a status update even for a much older photo")
    let geometry = MacGridGeometry.make(count: source.identifiers.count, groups: source.groups,
      columns: 4, width: 804, headerHeights: source.headerHeights(width: 804), flowHeaders: source.flowHeaders)
    XCTAssertTrue(geometry.macCaptions.ordered.allSatisfy { $0.id.kind == .summary })
    let video = MacHistoryGridSource(history: model, state: state, filter: "all", type: .video, search: "")
    XCTAssertEqual(video.identifiers.count, 110)
    XCTAssertFalse(video.identifiers.contains("job-7"))
    source.scroll.anchor = "job-200"
    XCTAssertEqual(MacHistoryGridSource(history: model, state: state, filter: "all", type: .all, search: "").scroll.anchor, "job-200")
    XCTAssertNil(video.scroll.anchor, "Each browse view owns its anchor")
  }

  func testFolderResizeRetainsDisplayedPixelsUntilReplacementArrives() {
    let cell = PhotoCell()
    let folder = FolderSource(id: "folder", name: "Synthetic", bookmark: Data(), automatic: false,
      enabled: true, receiver: nil, lastCheck: nil)
    let photo = FolderPhoto(relative: "photo.jpg", source_id: "file", revision: "1", size: 100,
      media_type: "image/jpeg", modified_ms: 1000, folder_id: "folder", capture_ms: 1000,
      date_source: "embedded", backup: "not_backed_up", saved_at_ms: nil)
    let image = NSImage(size: NSSize(width: 32, height: 32))
    cell.configureFolder(photo, source: folder, pixels: 100, synthetic: image)
    XCTAssertTrue(cell.displayedImage === image)
    // The deliberately invalid bookmark makes the larger request unavailable.
    cell.configureFolder(photo, source: folder, pixels: 200)
    XCTAssertTrue(cell.displayedImage === image, "Resizing an unchanged file must never blank its cover")
    cell.cancel()
  }

  func testSupplementaryDiffProbesAcceptSectionOnlyPaths() {
    let layout = LibraryTimelineLayout(mode: .all, target: 135)
    XCTAssertNil(layout.layoutAttributesForSupplementaryView(ofKind: LibraryTimelineLayout.headerKind, at: IndexPath(index: 0)))
    XCTAssertNil(layout.layoutAttributesForSupplementaryView(ofKind: LibraryTimelineLayout.headerKind, at: IndexPath()))
  }

  func testHeldPhotoBlendDoesNotMoveGroupedCaptions() {
    let stage = MacGridZoomStage(count: 90, anchor: 10, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 4, pitch: 160, focus: CGPoint(x: 250, y: 300))
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 1800)
    let geometry: (Int) -> LibraryTimelineGeometry = {
      MacGridGeometry.make(count: 90, groups: [0: "First", 30: "Second", 60: "Third"], columns: $0, width: 804)
    }
    stage.groupedGeometry = geometry
    stage.referenceSide = { geometry($0).items[0].width }
    stage.makeTile = { _, _ in NSView() }
    stage.ensureFace(4, opacity: 1); stage.ensureFace(6, opacity: 0)
    let now = CACurrentMediaTime()
    stage.show(6, animated: true, at: now); stage.render()
    let frames = [0, 30, 60].compactMap { stage.headerFrame(at: $0) }
    for time in [0.2, 0.6, 1.5] {
      stage.advance(to: now + time)
      XCTAssertEqual([0, 30, 60].compactMap { stage.headerFrame(at: $0) }, frames)
    }
    stage.stop()
  }

  func testTopGroupedSummaryDoesNotDipAndReturnDuringDensityChanges() {
    let geometry: (Int) -> LibraryTimelineGeometry = {
      MacGridGeometry.make(count: 90, groups: [0: "First", 30: "Second", 60: "Third"],
        columns: $0, width: 804, headerHeights: [0: 154, 30: 130, 60: 174])
    }
    for (from, to) in [(3, 4), (4, 6), (6, 9), (9, 6), (6, 4), (4, 3)] {
      let anchor = 5, a = geometry(from).items[anchor], b = geometry(to).items[anchor]
      let focus = CGPoint(x: a.midX, y: a.midY)
      let stage = MacGridZoomStage(count: 90, anchor: anchor, fraction: CGPoint(x: 0.5, y: 0.5),
        columns: from, pitch: a.width + 2, focus: focus)
      stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
      stage.groupedGeometry = geometry
      stage.referenceSide = { geometry($0).items[0].width }
      stage.makeTile = { _, _ in NSView() }
      stage.ensureFace(from, opacity: 1); stage.ensureFace(to, opacity: 0)
      let start = stage.headerFrame(at: 0)
      let now = CACurrentMediaTime()
      stage.show(to, animated: true, at: now)
      stage.settle(with: GridZoom.Settle(start: now, pitch: a.width + 2, focus: focus, velocity: 0,
        targetPitch: b.width + 2, targetFocus: CGPoint(x: b.midX, y: b.midY))) {}
      XCTAssertEqual(stage.headerFrame(at: 0), start)
      let caption = stage.subviews.compactMap { $0 as? MacGridSectionHeader }.first!
      let move = caption.layer!.animation(forKey: "zoom.caption") as! CAKeyframeAnimation
      let positions = move.values as! [NSNumber]
      for position in positions {
        XCTAssertEqual(position.doubleValue, positions.last!.doubleValue, accuracy: 0.001,
          "The top summary must stay still throughout \(from) → \(to), including the middle frames")
      }
      stage.stop()
    }
  }

  func testShortGridZoomKeepsFirstSlotAtEveryDensity() async {
    for count in [1, 2, 5] {
      let source = GridTestSource(); source.identifiers = (0..<count).map { "item-\($0)" }
      let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0, receiverID: nil, columns: 3)
      let coordinator = MacMediaGrid.Coordinator(grid)
      let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 804, height: 700))
      let collection = LibraryCollectionView(frame: scroll.bounds)
      let layout = LibraryTimelineLayout(mode: .all, target: 264); layout.requestedColumns = 3
      collection.collectionViewLayout = layout
      collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
      scroll.documentView = collection; mountMacGridCollection(collection, coordinator: coordinator)
      coordinator.installDataSource(collection); coordinator.applyItems(scroll: scroll, layout: layout)
      try? await Task.sleep(for: .milliseconds(50))
      for columns in [4, 6, 9, 6, 4, 3] {
        coordinator.parent.columns = columns
        coordinator.animateLayout(columns: columns)
        XCTAssertEqual(coordinator.zoomStage?.anchor, 0)
        XCTAssertEqual(coordinator.zoomStage?.fraction, .zero)
        coordinator.zoomStage?.advance(to: CACurrentMediaTime() + 3)
        collection.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(coordinator.leading, 0)
        XCTAssertEqual(layout.frame(at: 0).minX, 2, accuracy: 0.5)
        XCTAssertEqual(layout.frame(at: 0).minY, 4, accuracy: 0.5)
      }
      coordinator.removeZoomStage()
    }
  }

  func testZoomSourceTileRetainsVisiblePixelsBeforeNewRequestCompletes() {
    let stage = MacGridZoomStage(count: 1, anchor: 0, fraction: .zero, columns: 4, pitch: 200, focus: .zero)
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 600)
    let image = NSImage(size: NSSize(width: 64, height: 64))
    stage.seedImages = [0: image]
    stage.makeTile = { _, _ in MacSourceZoomTile() }
    stage.ensureFace(4, opacity: 1)
    XCTAssertTrue(stage.displayedImage(at: 0) === image)
    stage.stop()
    XCTAssertTrue(stage.seedImages.isEmpty)
  }

  func testFolderParentKeepsIdentityAcrossSecondAndThirdDateAndLeavesWithItsLastDate() {
    let groups = [0: "October 20", 12: "October 21", 24: "October 22", 36: "October 20", 48: "October 21"]
    let folders = [0: MacTimelineFolder(id: "a", title: "Camera", identityHeight: 41),
      36: MacTimelineFolder(id: "b", title: "Camera", identityHeight: 63)]
    for columns in [3, 4, 6, 9] {
      let geometry = MacGridGeometry.make(count: 72, groups: groups, columns: columns, width: 804,
        headerHeights: [0: 264, 36: 344], folders: folders)
      let captions = geometry.macCaptions
      let parent = captions.caption(kind: .folder, at: 0)!
      let summary = captions.caption(kind: .summary, at: 0)!
      let nextSummary = captions.caption(kind: .summary, at: 36)!
      func frame(_ caption: MacTimelineCaption, _ top: CGFloat) -> CGRect {
        captions.frame(for: caption, top: top, width: 804,
          contentBottom: geometry.items.last!.maxY, natural: { captions.byID[$0]?.frame })
      }
      XCTAssertEqual(frame(parent, 0).minY, summary.frame.minY)
      XCTAssertEqual(frame(parent, 0).height, 41)
      for first in [12, 24] {
        let date = captions.caption(kind: .date, at: first)!
        let previous = captions.caption(kind: .date, at: first - 12)!
        for delta: CGFloat in [-20, 0, 20, 80] {
          let top = date.frame.minY - parent.frame.height + delta
          XCTAssertEqual(frame(parent, top).minY, top, "A sibling date must never push the folder name")
          XCTAssertEqual(frame(summary, top).minY, summary.frame.minY, "Summary body remains in document flow")
          XCTAssertLessThanOrEqual(frame(previous, top).maxY, frame(date, top).minY)
          XCTAssertGreaterThanOrEqual(frame(date, top).minY, frame(parent, top).maxY)
        }
      }
      let last = captions.caption(kind: .date, at: 24)!
      for distance: CGFloat in [84, 60, 20, 0, -20] {
        let top = nextSummary.frame.minY - distance
        let identity = frame(parent, top), date = frame(last, top)
        XCTAssertLessThanOrEqual(identity.maxY, date.minY)
        XCTAssertLessThanOrEqual(date.maxY, nextSummary.frame.minY,
          "The outgoing date cannot accompany the next folder's summary")
      }
      XCTAssertNotEqual(captions.caption(kind: .date, at: 0)!.id,
        captions.caption(kind: .date, at: 36)!.id, "Repeated date text has independent folder ownership")
    }
  }

  func testShortFolderKeepsPermanentSummaryExtentAndAllPhotosRemainsDateOnly() {
    for count in [1, 2, 5] {
      let plain = MacGridGeometry.make(count: count, groups: [0: "Today"], columns: 9,
        width: 804, headerHeights: [0: 424])
      let nested = MacGridGeometry.make(count: count, groups: [0: "Today"], columns: 9,
        width: 804, headerHeights: [0: 424],
        folders: [0: MacTimelineFolder(id: "short", title: "Long folder", identityHeight: 93)])
      XCTAssertEqual(nested.items, plain.items)
      XCTAssertEqual(nested.height, plain.height, "Pinning must neither add a row nor collapse summary height")
      XCTAssertEqual(nested.macCaptions.ordered.count, 3)
      XCTAssertEqual(plain.macCaptions.ordered.map(\.id.kind), [.date])
      let captions = nested.macCaptions
      let parent = captions.caption(kind: .folder, at: 0)!
      let date = captions.caption(kind: .date, at: 0)!
      for top: CGFloat in [0, 100, 300, 420] {
        let p = captions.frame(for: parent, top: top, width: 804, contentBottom: nested.items.last!.maxY,
          natural: { captions.byID[$0]?.frame })
        let d = captions.frame(for: date, top: top, width: 804, contentBottom: nested.items.last!.maxY,
          natural: { captions.byID[$0]?.frame })
        XCTAssertLessThanOrEqual(p.maxY, d.minY)
        XCTAssertLessThanOrEqual(d.maxY, nested.items.last!.maxY)
        XCTAssertEqual(nested.height, plain.height)
      }
    }
  }

  func testWrappedFolderIdentityUsesTheSameMeasuredRowInSummaryAndPinnedHeader() {
    let source = HierarchyGridSource()
    source.folderSources.sources[0].name = String(repeating: "Long camera folder name ", count: 12)
    source.folderSources.sources[0].lastKnownPath = nil
    var priorHeight: CGFloat = .greatestFiniteMagnitude
    for width: CGFloat in [320, 460, 804] {
      let folder = source.folderHeaders(width: width)[0]!
      let geometry = source.geometry(columns: 4, width: width)
      let parent = geometry.macCaptions.caption(kind: .folder, at: 0)!
      let summary = geometry.macCaptions.caption(kind: .summary, at: 0)!
      let identity = MacGridSectionHeader(frame: CGRect(x: 0, y: 0, width: width, height: folder.identityHeight))
      identity.configure(caption: parent, content: source.folderIdentity(at: 0), revision: source.contentRevision)
      identity.layoutSubtreeIfNeeded()
      XCTAssertGreaterThanOrEqual(folder.identityHeight, DuckSettingsMetrics.rowHeight)
      XCTAssertLessThanOrEqual(folder.identityHeight, priorHeight)
      XCTAssertEqual(identity.summary!.frame.height, ceil(identity.summary!.fittingSize.height), accuracy: 1)
      XCTAssertEqual(parent.frame.minY, summary.frame.minY, "The pinned copy starts at exactly the original identity row")
      XCTAssertEqual(parent.frame.height, folder.identityHeight)
      XCTAssertGreaterThan(summary.frame.height, folder.identityHeight)
      XCTAssertTrue(identity.isReady(for: parent, revision: source.contentRevision))
      XCTAssertFalse(identity.isReady(for: summary, revision: source.contentRevision), "A frame match does not prove caption identity")
      XCTAssertFalse(identity.isReady(for: parent, revision: "old"), "A stale summary cannot retire a current cover")
      priorHeight = folder.identityHeight
    }
  }

  func testFolderScopesUseFlatPhotosAndOnlySelectedSourceNotices() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.sources = ["a", "b"].map {
      FolderSource(id: $0, name: "Camera exports " + $0,
        bookmark: Data(), automatic: false, enabled: true, receiver: nil, lastCheck: nil)
    }
    folders.previewRows = folders.sources.flatMap { folder in
      (0..<3).map { index in
        FolderPhoto(relative: "sample-\(index).jpg", source_id: "photo-\(index)", revision: "1", size: 1,
          media_type: "image/jpeg", modified_ms: 0, folder_id: folder.id,
          capture_ms: 1_700_000_000_000 + UInt64(index) * 86_400_000,
          date_source: "embedded", backup: "not_backed_up", saved_at_ms: nil)
      }
    }
    let browser = FolderBrowser(); browser.scope = .folder("a"); await browser.reload(folders)
    let source = MacFolderGridSource(folders: folders, browser: browser)
    XCTAssertTrue(source.membershipReady)
    XCTAssertEqual(source.identifiers.count, 3)
    XCTAssertTrue(source.identifiers.allSatisfy { source.photos[$0]?.folder_id == "a" })
    XCTAssertTrue(source.groups.isEmpty); XCTAssertTrue(source.dateIDs.isEmpty)
    XCTAssertTrue(source.folderHeaders(width: 804).isEmpty)
    folders.facts["a"] = FolderFacts(unsupported_by_kind: ["raw": 12])
    folders.revision += 1
    let notice = MacFolderGridSource(folders: folders, browser: browser)
    XCTAssertEqual(notice.identifiers, source.identifiers)
    XCTAssertEqual(notice.flowHeaders, [0]); XCTAssertTrue(notice.dateIDs.isEmpty)
    let geometry = MacGridGeometry.make(count: notice.identifiers.count, groups: notice.groups,
      columns: 4, width: 804, headerHeights: notice.headerHeights(width: 804), flowHeaders: notice.flowHeaders)
    XCTAssertEqual(geometry.macCaptions.ordered.count, 1)
    let caption = geometry.macCaptions.ordered[0]
    XCTAssertEqual(caption.id.kind, .summary)
    let scrolled = geometry.macCaptions.frame(for: caption, top: 400, width: 804,
      contentBottom: geometry.height, natural: { geometry.macCaptions.byID[$0]?.frame })
    XCTAssertEqual(scrolled.minY, caption.frame.minY, "Source notes scroll away without pinning")
    browser.scope = .all
    XCTAssertFalse(MacFolderGridSource(folders: folders, browser: browser).membershipReady)
    await browser.reload(folders)
    let all = MacFolderGridSource(folders: folders, browser: browser)
    XCTAssertTrue(all.groups.isEmpty); XCTAssertTrue(all.flowHeaders.isEmpty)
    XCTAssertEqual(all.identifiers.count, 6)
    let dates = all.identifiers.compactMap { all.date($0) }
    XCTAssertEqual(dates, dates.sorted(), "The combined scope places the newest items at the end")
    browser.scope = .folder("b"); browser.search = "sample"; await browser.reload(folders)
    let search = MacFolderGridSource(folders: folders, browser: browser)
    XCTAssertEqual(search.identifiers.count, 3)
    XCTAssertTrue(search.groups.isEmpty)
  }

  func testVisibleDateUsesOnlyActuallyVisibleTopRow() {
    let items: [(index: Int, frame: CGRect)] = [
      (0, CGRect(x: 0, y: 0, width: 100, height: 100)),
      (1, CGRect(x: 102, y: 0, width: 100, height: 100)),
      (2, CGRect(x: 0, y: 102, width: 100, height: 100)),
      (3, CGRect(x: 102, y: 102, width: 100, height: 100)),
      (4, CGRect(x: 0, y: 204, width: 100, height: 100)),
      (5, CGRect(x: 250, y: 0, width: 100, height: 100))
    ]
    XCTAssertEqual(MacGridDateRange.topRow(in: CGRect(x: 0, y: 50, width: 202, height: 230), items: items), [0, 1])
    XCTAssertEqual(MacGridDateRange.topRow(in: CGRect(x: 0, y: 100, width: 202, height: 230), items: items), [2, 3])
    XCTAssertTrue(MacGridDateRange.topRow(in: CGRect(x: 0, y: 400, width: 202, height: 230), items: items).isEmpty)
  }

  func testVisibleDateFormatsSingleDayAndCrossYearWithoutInventingDates() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let first = calendar.date(from: DateComponents(year: 2023, month: 12, day: 31, hour: 12))!
    let last = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 12))!
    let locale = Locale(identifier: "en_US")
    XCTAssertEqual(MacGridDateRange.title(dates: [first, first.addingTimeInterval(60)], calendar: calendar, locale: locale), "December 31, 2023")
    let interval = MacGridDateRange.title(dates: [last, first], calendar: calendar, locale: locale)
    XCTAssertTrue(interval.contains("2023")); XCTAssertTrue(interval.contains("2024"))
    XCTAssertEqual(interval, MacGridDateRange.title(dates: [first, last], calendar: calendar, locale: locale))
    XCTAssertEqual(MacGridDateRange.title(dates: [], calendar: calendar, locale: locale), "")
  }

  func testFolderZoomKeepsNativeParentGeometryThroughForwardReverseAndInputTakeover() {
    let source = HierarchyGridSource()
    var geometries: [Int: LibraryTimelineGeometry] = [:]
    let geometry: (Int) -> LibraryTimelineGeometry = { columns in
      if let existing = geometries[columns] { return existing }
      let result = source.geometry(columns: columns, width: 804); geometries[columns] = result; return result
    }
    let initial = geometry(4), anchor = initial.items[18]
    let stage = MacGridZoomStage(count: source.identifiers.count, anchor: 18, fraction: CGPoint(x: 0.5, y: 0.5),
      columns: 4, pitch: anchor.width + 2, focus: CGPoint(x: anchor.midX, y: 200))
    stage.frame = CGRect(x: 0, y: 0, width: 804, height: 700)
    stage.groupedGeometry = geometry; stage.referenceSide = { geometry($0).items[0].width }
    stage.groupedIntroduction = source.introduction; stage.groupedIdentity = source.folderIdentity
    stage.groupedRevision = source.contentRevision; stage.makeTile = { _, _ in NSView() }
    stage.ensureFace(4, opacity: 1)
    let parent = initial.macCaptions.caption(kind: .folder, at: 0)!
    let initialParent = stage.captionFrame(parent.id)!
    XCTAssertEqual(initialParent.minY, 0)
    for columns in [6, 9, 6, 4, 3, 4] {
      stage.ensureFace(columns, opacity: 0)
      let firstPitch = stage.pitch, targetPitch = geometry(columns).items[0].width + 2
      stage.show(columns, animated: true)
      for step in 0...24 {
        stage.pitch = firstPitch + (targetPitch - firstPitch) * CGFloat(step) / 24
        stage.render()
        let frame = stage.captionFrame(parent.id)!
        XCTAssertEqual(frame.minY, 0)
        XCTAssertEqual(frame.height, initialParent.height)
        XCTAssertEqual(frame.width, 804)
        let captions = stage.subviews.compactMap { $0 as? MacGridSectionHeader }
        XCTAssertEqual(captions.count, Set(captions.compactMap(\.captionID)).count)
        XCTAssertTrue(captions.allSatisfy { CATransform3DIsIdentity($0.layer!.transform) })
      }
    }
    let before = stage.subviews.compactMap { $0 as? MacGridSectionHeader }.map { ($0, $0.frame) }
    stage.reanchor(to: CGPoint(x: 440, y: 400))
    for (caption, frame) in before { XCTAssertEqual(caption.frame, frame) }
    stage.stop()
  }

  func testRegistrationFeedbackExpires() async {
    let action = SelectionBackupAction()
    await action.perform({ true }, failure: { nil })
    XCTAssertTrue(action.added)
    try? await Task.sleep(for: .milliseconds(2150))
    XCTAssertFalse(action.added)
  }
}

@MainActor final class HierarchyGridSource: MacGridSource {
  let folderSources = FolderSources(backup: BackupModel.shared)
  var identifiers = (0..<72).map { "hierarchy-\($0)" }
  var fetchResult: MacGridFetchResult { MacGridFetchResult(identifiers: identifiers) }
  let contextID = "hierarchy-test"
  let contentRevision = "1"
  var selection = Set<String>()
  let scroll = MacGridScrollState()
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  let groups = [0: "October 20", 12: "October 21", 24: "October 22", 36: "October 20", 48: "October 21", 60: "October 22"]
  init() {
    folderSources.previewRows = []
    folderSources.sources = ["first", "second"].map {
      FolderSource(id: $0, name: "Camera \($0)", bookmark: Data(), automatic: false,
        enabled: true, receiver: nil, lastCheck: nil,
        lastKnownPath: "/Volumes/Camera/Exports/\($0)")
    }
  }
  func introduction(at index: Int) -> AnyView? {
    guard index == 0 || index == 36 else { return nil }
    return AnyView(FolderSectionHeader(folders: folderSources, source: folderSources.sources[index / 36],
      settings: { _ in }, stop: { _ in }, identityAccessibilityHidden: true))
  }
  func folderIdentity(at index: Int) -> AnyView? {
    guard index == 0 || index == 36 else { return nil }
    return AnyView(FolderIdentityRow(folders: folderSources, source: folderSources.sources[index / 36],
      settings: { _ in }, stop: { _ in }))
  }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] {
    Dictionary(uniqueKeysWithValues: [0, 36].map { ($0, MacGridSectionHeader.fittingHeight(introduction: introduction(at: $0)!, width: width)) })
  }
  func folderHeaders(width: CGFloat) -> [Int: MacTimelineFolder] {
    Dictionary(uniqueKeysWithValues: [0, 36].map {
      let folder = folderSources.sources[$0 / 36]
      return ($0, MacTimelineFolder(id: folder.id, title: folderSources.displayName(folder),
        identityHeight: MacGridSectionHeader.fittingContentHeight(folderIdentity(at: $0)!, width: width)))
    })
  }
  func geometry(columns: Int, width: CGFloat) -> LibraryTimelineGeometry {
    MacGridGeometry.make(count: identifiers.count, groups: groups, columns: columns, width: width,
      headerHeights: headerHeights(width: width), folders: folderHeaders(width: width))
  }
  func date(_ id: String) -> Date? { nil }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    cell.configureUnavailable(id: id, label: id, video: false)
  }
}

@MainActor private final class GridTestSource: MacGridSource {
  var zoomStops = MacLibraryDensity.grid
  var identifiers = ["a", "b", "c"]
  var fetchResult: MacGridFetchResult { MacGridFetchResult(identifiers: identifiers) }
  var contextID = "test"
  var contentRevision = "1"
  var selection = Set<String>()
  let scroll = MacGridScrollState()
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  var mark: String?
  var introduction: AnyView?
  var groups: [Int: String] { introduction == nil ? [:] : [0: "Today"] }
  func introduction(at index: Int) -> AnyView? { index == 0 ? introduction : nil }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] {
    introduction.map { [0: MacGridSectionHeader.fittingHeight(introduction: $0, width: width)] } ?? [:]
  }
  func date(_ id: String) -> Date? { nil }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    cell.configureUnavailable(id: id, label: id, video: false)
    cell.setState(mark)
  }
}

final class GridHistoryCore: CoreTransport, @unchecked Sendable {
  var reordered = false
  func call(_ command: String) async throws -> Data {
    let query = try JSONSerialization.jsonObject(with: Data(command.utf8)) as! [String: Any]
    var ordered = Array(0..<220)
    if reordered { ordered.insert(ordered.removeLast(), at: 0) }
    if query["state"] as? String == "attention" { ordered = [7] }
    let start = (query["after"] as? Int).flatMap { ordered.firstIndex(of: $0).map { $0 + 1 } } ?? 0
    let page = ordered.dropFirst(start).prefix(200)
    let items: [[String: Any]] = page.map { id in
      ["id": "job-\(id)", "cursor": id, "sort_value": 1_792_495_800_000 - id * 1000,
        "job": ["id": id, "receiver_id": "test-receiver", "state": id == 7 ? "failed" : "received",
          "processing": "complete", "confirmed_bytes": 100,
          "asset": ["kind": id % 2 == 0 ? "video" : "photo", "source_id": "source-\(id)", "revision": "1",
            "metadata": ["source_type": id % 3 == 0 ? "folder" : "library", "created_at_ms": "1514764800000"],
            "resources": [["filename": "sample-\(id).jpg", "size": 100]]]]]
    }
    let summary: [String: Any] = ["total": 220, "attention": 1, "received": 219, "published": 219,
      "publication_failed": 0, "waiting": 0, "failed": 1, "queued": 0, "running": 0, "paused": 0, "confirmed_bytes": 21900]
    return try JSONSerialization.data(withJSONObject: ["ok": true, "value": ["items": items, "summary": summary]])
  }
}


@MainActor final class MacCalendarResizeTests: XCTestCase {
  func testRetainedInactiveMonthMaterializesNewestPeriodOnFirstActivation() async throws {
    let original = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = original }
    let fixture = CatalogLibraryFixture(count: 60_000)
    let library = PhotoLibraryModel()
    library.installSyntheticAssets(fixture.fetch(filter: .all, view: .all))
    let navigation = MacLibraryNavigation()
    navigation.rebuild(library.fetch)
    for _ in 0..<200 where navigation.indexing { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertFalse(navigation.indexing)
    XCTAssertGreaterThan(navigation.months.count, 60)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let host = NSHostingController(rootView: RetainedCalendarTestHost(library: library, navigation: navigation)
      .frame(width: 980, height: 720))
    host.sizingOptions = []
    window.contentViewController = host
    window.setContentSize(NSSize(width: 980, height: 720))
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(100))
    window.contentView?.layoutSubtreeIfNeeded()
    func collection(in view: NSView) -> MacCalendarCollection? {
      if let collection = view as? MacCalendarCollection { return collection }
      return view.subviews.lazy.compactMap { collection(in: $0) }.first
    }
    let grid = try XCTUnwrap(collection(in: host.view))
    let scroll = try XCTUnwrap(grid.enclosingScrollView)
    XCTAssertGreaterThan(scroll.contentSize.width, 900)
    XCTAssertGreaterThan(scroll.contentSize.height, 650)
    XCTAssertEqual(scroll.alphaValue, 0, accuracy: 0.001)
    XCTAssertGreaterThan(grid.numberOfItems(inSection: 0), 60)
    navigation.selectLevel(.months)
    try await Task.sleep(for: .milliseconds(350))
    window.contentView?.layoutSubtreeIfNeeded()
    let layout = try XCTUnwrap(grid.collectionViewLayout)
    let newest = IndexPath(item: navigation.months.count - 1, section: 0)
    let viewport = scroll.contentView.bounds
    let expectedFrame = try XCTUnwrap(layout.layoutAttributesForItem(at: newest)?.frame)
    XCTAssertTrue(expectedFrame.intersects(viewport), "The newest month must occupy the actual viewport")
    XCTAssertEqual(viewport.maxY, layout.collectionViewContentSize.height, accuracy: 1)
    let actual = try XCTUnwrap(grid.item(at: newest), "Native AppKit must materialize the newest month, not leave only its old hidden cells")
    XCTAssertTrue(actual.view.superview != nil)
    XCTAssertTrue(actual.view.frame.intersects(viewport))
    XCTAssertTrue(grid.indexPathsForVisibleItems().contains(newest))
    XCTAssertEqual(actual.view.frame.minY, expectedFrame.minY, accuracy: 0.5)
    XCTAssertEqual(actual.view.accessibilityIdentifier(), "library.period." + navigation.months[0].id)
    XCTAssertGreaterThan(scroll.alphaValue, 0.99)
  }

  func testCalendarCoversHaveBoundedResponsiveReadingSizes() {
    for width in stride(from: CGFloat(360), through: 1800, by: 17) {
      let year = MacCalendarMetrics.itemSize(kind: .years, width: width, covers: 1)
      XCTAssertLessThanOrEqual(year.width, MacCalendarMetrics.maximumYearWidth)
      XCTAssertEqual(year.height, round(year.width * 1.25))
      let month = MacCalendarMetrics.itemSize(kind: .months, width: width, covers: 6)
      XCTAssertLessThanOrEqual(month.width, MacCalendarMetrics.maximumMonthWidth)
      XCTAssertLessThanOrEqual(month.width, width - MacCalendarMetrics.inset * 2)
    }
  }

  func testNativeCalendarResizeRetainsMidPeriodThroughReversal() throws {
    for kind in [MacLibraryLevel.months, .years] {
      let fixture = CalendarResizeFixture(kind: kind)
      defer { fixture.window.contentView = nil }
      let path = IndexPath(item: 15, section: 0)
      let before = try XCTUnwrap(fixture.layout.layoutAttributesForItem(at: path)?.frame)
      let fraction: CGFloat = 0.37
      let origin = before.minY + before.height * fraction
      fixture.scroll.contentView.scroll(to: CGPoint(x: 0, y: origin))
      fixture.scroll.reflectScrolledClipView(fixture.scroll.contentView)
      fixture.collection.viewWillStartLiveResize()
      for width: CGFloat in [980, 760, 1100, 1200] {
        fixture.resize(width)
        let frame = try XCTUnwrap(fixture.layout.layoutAttributesForItem(at: path)?.frame)
        XCTAssertEqual(fixture.scroll.contentView.bounds.minY,
          frame.minY + fraction * frame.height, accuracy: 1, "\(kind) at \(width)")
      }
      fixture.collection.viewDidEndLiveResize()
      XCTAssertEqual(fixture.scroll.contentView.bounds.minY, origin, accuracy: 1)
      // Explicit focus is consumed once; later layout cannot replay it.
      fixture.collection.place(22)
      let browsing = max(0, fixture.scroll.contentView.bounds.minY - 90)
      fixture.scroll.contentView.scroll(to: CGPoint(x: 0, y: browsing))
      fixture.collection.needsLayout = true; fixture.collection.layoutSubtreeIfNeeded()
      XCTAssertEqual(fixture.scroll.contentView.bounds.minY, browsing, accuracy: 1)
    }
  }

  func testNativeCalendarResizeKeepsNewestEdge() throws {
    for kind in [MacLibraryLevel.months, .years] {
      let fixture = CalendarResizeFixture(kind: kind)
      defer { fixture.window.contentView = nil }
      fixture.collection.place(nil)
      fixture.collection.viewWillStartLiveResize()
      for width: CGFloat in [760, 1000, 1200] {
        fixture.resize(width)
        XCTAssertEqual(fixture.scroll.contentView.bounds.minY,
          max(0, fixture.layout.collectionViewContentSize.height - fixture.scroll.contentSize.height), accuracy: 1)
      }
      fixture.collection.viewDidEndLiveResize()
    }
  }
}

@MainActor private final class CalendarResizeFixture: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
  let kind: MacLibraryLevel
  let window: NSWindow
  let scroll = MacCalendarScrollView()
  let collection = MacCalendarCollection()
  let layout: MacCalendarFlowLayout
  init(kind: MacLibraryLevel) {
    self.kind = kind; layout = MacCalendarFlowLayout(kind: kind)
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    super.init()
    scroll.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
    scroll.autoresizingMask = [.width, .height]
    scroll.scrollerStyle = .overlay; scroll.hasVerticalScroller = true
    collection.collectionViewLayout = layout
    collection.dataSource = self; collection.delegate = self
    collection.register(CalendarResizeItem.self, forItemWithIdentifier: .init("calendar-test"))
    collection.autoresizingMask = [.width]
    scroll.documentView = collection; window.contentView = scroll
    collection.reloadData(); resize(1200)
  }
  func resize(_ width: CGFloat) {
    window.setContentSize(NSSize(width: width, height: 700))
    scroll.needsLayout = true; scroll.layoutSubtreeIfNeeded()
    collection.needsLayout = true; collection.layoutSubtreeIfNeeded()
  }
  func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { 36 }
  func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
    collectionView.makeItem(withIdentifier: .init("calendar-test"), for: indexPath)
  }
  func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
    sizeForItemAt indexPath: IndexPath) -> NSSize {
    MacCalendarMetrics.itemSize(kind: kind, width: collectionView.bounds.width, covers: 6)
  }
}
@MainActor private final class CalendarResizeItem: NSCollectionViewItem {
  override func loadView() { view = NSView() }
}

private struct RetainedCalendarTestHost: View {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var navigation: MacLibraryNavigation
  var body: some View {
    ZStack {
      Color.clear
      MacCalendarGrid(library: library, navigation: navigation, kind: .months)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct OverviewClickTestHost: View {
  let source: MacPhotoLibrarySource
  @ObservedObject var navigation: MacLibraryNavigation
  @ObservedObject var size: MacGridSize
  var body: some View {
    MacMediaGrid(source: source, navigation: navigation, queueRevision: 0, receiverID: nil,
      columns: size.columns, prefillsTables: false, reducedMotionOverride: false, resize: { size.columns = $0 })
  }
}

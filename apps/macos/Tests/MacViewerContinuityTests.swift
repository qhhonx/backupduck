import AppKit
import Photos
import SwiftUI
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

@MainActor final class MacViewerContinuityTests: XCTestCase {
  private func bitmap(_ size: CGSize, hdr: Bool = false) throws -> CGImage {
    let space = try XCTUnwrap(CGColorSpace(name: hdr ? CGColorSpace.extendedLinearSRGB : CGColorSpace.displayP3))
    let flags = CGImageAlphaInfo.premultipliedLast.rawValue
      | (hdr ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue : 0)
    let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
      bitsPerComponent: hdr ? 32 : 8, bytesPerRow: 0, space: space, bitmapInfo: flags))
    context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [hdr ? 1.5 : 0.6, 0.3, 0.2, 1])))
    context.fill(CGRect(origin: .zero, size: size))
    let image = try XCTUnwrap(context.makeImage())
    return hdr ? try XCTUnwrap(CGImageCreateCopyWithContentHeadroom(2, image)) : image
  }

  func testCroppedPosterKeepsItsTrueRegionOfPortraitAndPanorama() throws {
    let square = NSImage(cgImage: try bitmap(CGSize(width: 80, height: 80)), size: .zero)
    let portrait = MacCoverFlightSource.renditionSize(square, fullAspect: 0.5, in: CGSize(width: 200, height: 400))
    XCTAssertEqual(portrait, CGSize(width: 200, height: 200), "The centre crop cannot stretch into the portrait's full height")
    let panorama = MacCoverFlightSource.renditionSize(square, fullAspect: 3, in: CGSize(width: 600, height: 200))
    XCTAssertEqual(panorama, CGSize(width: 200, height: 200), "The source crop occupies only the panorama's centre")
    let full = NSImage(cgImage: try bitmap(CGSize(width: 240, height: 80)), size: .zero)
    XCTAssertEqual(MacCoverFlightSource.renditionSize(full, fullAspect: 3, in: CGSize(width: 80, height: 80)),
      CGSize(width: 240, height: 80), "The grid clips full-aspect pixels without changing their aspect")
  }

  func testFlightHoldsNativeRenditionAndPublishesHDRUpgradeAfterHandoff() throws {
    let seed = NSImage(cgImage: try bitmap(CGSize(width: 80, height: 40)), size: .zero)
    let upgraded = NSImage(cgImage: try bitmap(CGSize(width: 160, height: 80), hdr: true), size: .zero)
    let view = MacMediaImageView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
    view.setImage(seed, holding: false)
    view.setImage(upgraded, holding: true)
    XCTAssertTrue(view.image === seed, "A late quality callback must not replace the rendition under a flying cover")
    let heldContents = try XCTUnwrap(view.layer?.contents)
    XCTAssertEqual(CFGetTypeID(heldContents as CFTypeRef), CGImage.typeID)
    let held = heldContents as! CGImage
    XCTAssertEqual(held.width, 80)
    view.releaseFlight()
    XCTAssertTrue(view.image === upgraded)
    let displayedContents = try XCTUnwrap(view.layer?.contents)
    XCTAssertEqual(CFGetTypeID(displayedContents as CFTypeRef), CGImage.typeID)
    let displayed = displayedContents as! CGImage
    XCTAssertEqual(displayed.width, 160); XCTAssertEqual(displayed.bitsPerComponent, 32)
    XCTAssertEqual(displayed.contentHeadroom, 2)
    XCTAssertTrue(displayed.colorSpace?.isHDR() == true || displayed.colorSpace.map { CGColorSpaceUsesExtendedRange($0) } == true)
    XCTAssertEqual(displayed.dataProvider?.data as Data?, upgraded.cgImage(forProposedRect: nil, context: nil, hints: nil)?.dataProvider?.data as Data?)
  }

  func testNativeFlightCompositesOpaquePixelsWithoutBrighteningOverWhiteWindow() async throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let pixels = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    pixels.setFillColor(CGColor(gray: 0.2, alpha: 1)); pixels.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    let image = NSImage(cgImage: try XCTUnwrap(pixels.makeImage()), size: .zero)
    func red(_ layer: CALayer, side: Int, at point: CGPoint) throws -> Int {
      let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
        bytesPerRow: side * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: side, height: side))
      layer.render(in: context)
      let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
      return Int(data[Int(point.y) * side * 4 + Int(point.x) * 4])
    }
    let native = MacMediaImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    native.setImage(image, holding: false)
    let settled = try red(XCTUnwrap(native.layer), side: 100, at: CGPoint(x: 50, y: 50))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400)); content.wantsLayer = true
    content.layer?.backgroundColor = NSColor.white.cgColor; window.contentView = content
    window.orderFront(nil)
    defer { window.orderOut(nil); window.contentView = nil }
    let endpoint = MacCoverFlightSource(rect: CGRect(x: 150, y: 150, width: 100, height: 100), image: image,
      radius: 0, assetID: "opaque", clip: window.contentLayoutRect, window: window, fullAspectRatio: 1)
    let driver = MacFlightDriver(source: endpoint, target: { endpoint }, first: endpoint,
      frame: try XCTUnwrap(content.superview), window: window, duration: 1, owner: nil, completion: {})
    defer { driver.finish() }
    CATransaction.flush()
    for _ in 0..<5 {
      try await Task.sleep(for: .milliseconds(100))
      let presentation = try XCTUnwrap(driver.presentationLayer, "The native render server must publish the actual flight presentation")
      let sample = try red(presentation, side: 400, at: CGPoint(x: 200, y: 200))
      XCTAssertLessThanOrEqual(abs(sample - settled), 2, "Source-over rendition blending must not reveal the white window through opaque media")
    }
  }

  private func displayedGridIDs(_ source: any MacGridSource) async -> [String] {
    let grid = MacMediaGrid(source: source, navigation: MacLibraryNavigation(), queueRevision: 0,
      receiverID: nil, columns: 3, prefillsTables: false)
    let coordinator = MacMediaGrid.Coordinator(grid)
    let scroll = LibraryScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 550))
    let collection = LibraryCollectionView(frame: scroll.bounds)
    let layout = LibraryTimelineLayout(mode: .all, target: 135); layout.requestedColumns = 3
    collection.collectionViewLayout = layout
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(MacGridSectionHeader.self, forSupplementaryViewOfKind: LibraryTimelineLayout.headerKind,
      withIdentifier: .init("timeline"))
    scroll.documentView = collection
    mountMacGridCollection(collection, coordinator: coordinator); coordinator.installDataSource(collection)
    coordinator.applyItems(scroll: scroll, layout: layout)
    try? await Task.sleep(for: .milliseconds(50))
    collection.layoutSubtreeIfNeeded()
    return coordinator.dataSource?.snapshot().itemIdentifiers ?? []
  }
  private func nativeView<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let found = view as? T { return found }
    return view.subviews.lazy.compactMap { self.nativeView(type, in: $0) }.first
  }
  private func nativePager(in view: NSView) -> MediaPageController? {
    if let found = view.nextResponder as? MediaPageController { return found }
    return view.subviews.lazy.compactMap { self.nativePager(in: $0) }.first
  }
  private func rightKey(in window: NSWindow) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: 124))
  }

  func testLibraryDetailNeighborsMatchTheActualGridForKeysDragAndNativePaging() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary; BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let fetch = CatalogLibraryFixture(count: 9).fetch(filter: .all, view: .all)
    let library = PhotoLibraryModel(); library.installSyntheticAssets(fetch)
    let source = MacPhotoLibrarySource(library)
    let displayed = await displayedGridIDs(source)
    XCTAssertEqual(displayed.count, 9)
    let initial = try XCTUnwrap(source.asset(displayed[3]))
    let expected = try displayed.map { try XCTUnwrap(source.asset($0)).localIdentifier }
    XCTAssertNotEqual(expected.first, fetch.object(at: 0).localIdentifier,
      "This fixture must distinguish grid display order from the backing PhotoKit fetch")
    let navigation = MacLibraryNavigation()
    let host = NSHostingController(rootView: MacPhotoPreview(asset: initial, library: library,
      navigation: navigation, close: { _ in }))
    host.sizingOptions = []
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = host
    window.setContentSize(NSSize(width: 900, height: 600)); window.orderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(150))
    let pager = try XCTUnwrap(nativePager(in: host.view))
    XCTAssertEqual(pager.selectedIndex, 3)
    let keys = try XCTUnwrap(nativeView(MacMediaKeyView.self, in: host.view))
    XCTAssertTrue(keys.handle?(try rightKey(in: window)) == true)
    XCTAssertEqual(navigation.viewerCurrent?()?.localIdentifier, expected[4])
    try await Task.sleep(for: .milliseconds(80))
    let image = try XCTUnwrap(nativeView(MacMediaScroll.self, in: try XCTUnwrap(pager.selectedViewController).view))
    image.onSwipe?(-1)
    XCTAssertEqual(navigation.viewerCurrent?()?.localIdentifier, expected[5])
    try await Task.sleep(for: .milliseconds(300))
    let delegate = try XCTUnwrap(pager.delegate as? MacMediaPager.Coordinator)
    pager.selectedIndex = 6
    delegate.pageController(pager, didTransitionTo: 6)
    delegate.pageControllerDidEndLiveTransition(pager)
    XCTAssertEqual(navigation.viewerCurrent?()?.localIdentifier, expected[6],
      "The native trackpad directory must reveal the actual next grid asset")
  }

  func testRetainedGridKeepsItsNativeViewportReadyAcrossWorkspaceActivation() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary; BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let library = PhotoLibraryModel()
    library.installSyntheticAssets(CatalogLibraryFixture(count: 24).fetch(filter: .all, view: .all))
    let source = MacPhotoLibrarySource(library)
    let navigation = MacLibraryNavigation()
    func page(active: Bool) -> AnyView {
      AnyView(MacMediaGrid(source: source, navigation: navigation, queueRevision: 0, receiverID: nil,
        columns: 3, active: active, prefillsTables: false)
        .opacity(active ? 1 : 0).allowsHitTesting(active).accessibilityHidden(!active))
    }
    let host = NSHostingController(rootView: page(active: true)); host.sizingOptions = []
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 550),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = host
    window.setContentSize(NSSize(width: 800, height: 550)); window.orderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(150))
    let scroll = try XCTUnwrap(nativeView(LibraryScrollView.self, in: host.view))
    let collection = try XCTUnwrap(scroll.documentView as? LibraryCollectionView)
    let visible = collection.indexPathsForVisibleItems()
    XCTAssertFalse(visible.isEmpty)
    let viewport = scroll.contentView.bounds
    host.rootView = page(active: false)
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertFalse(scroll.isHidden, "Workspace compositing must not tear down the native viewport while inactive")
    XCTAssertEqual(collection.indexPathsForVisibleItems(), visible)
    XCTAssertEqual(scroll.contentView.bounds, viewport)
    host.rootView = page(active: true)
    host.view.layoutSubtreeIfNeeded()
    XCTAssertFalse(scroll.isHidden, "The visible workspace must never wait for a queued native unhide")
    XCTAssertTrue(nativeView(LibraryScrollView.self, in: host.view) === scroll)
    XCTAssertEqual(collection.indexPathsForVisibleItems(), visible)
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertFalse(scroll.isHidden)
    XCTAssertEqual(scroll.contentView.bounds, viewport)
  }

  func testFolderDetailNeighborsMatchActualGridIDsForKeysAndDrag() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary; BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let folders = FolderSources(backup: BackupModel.shared)
    let photos = (0..<9).map { index in
      FolderPhoto(relative: "order-\(index).jpg", source_id: "\(index)", revision: "1", size: 1,
        media_type: "image/jpeg", modified_ms: UInt64(index), folder_id: "fixture", capture_ms: UInt64(index + 1),
        date_source: "metadata", backup: "saved", saved_at_ms: nil)
    }
    folders.previewRows = photos
    let picture = NSImage(cgImage: try bitmap(CGSize(width: 80, height: 40)), size: .zero)
    folders.previewImage = { _ in picture }
    let browser = FolderBrowser(); await browser.reload(folders)
    let source = MacFolderGridSource(folders: folders, browser: browser)
    let displayed = await displayedGridIDs(source)
    XCTAssertEqual(displayed.count, 9)
    let context = displayed.compactMap { source.photos[$0] }
    var selectedID: String?
    let navigation = MacLibraryNavigation()
    let host = NSHostingController(rootView: FolderViewer(photo: context[3], context: context,
      folders: folders, navigation: navigation, close: { selectedID = $0.id }))
    host.sizingOptions = []
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = host
    window.setContentSize(NSSize(width: 900, height: 600)); window.orderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(150))
    let pager = try XCTUnwrap(nativePager(in: host.view))
    let page = try XCTUnwrap(pager.selectedViewController)
    let keys = try XCTUnwrap(nativeView(MacMediaKeyView.self, in: page.view))
    XCTAssertTrue(keys.handle?(try rightKey(in: window)) == true)
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertEqual(pager.selectedIndex, 4)
    navigation.viewerBack?(); XCTAssertEqual(selectedID, displayed[4])
    let image = try XCTUnwrap(nativeView(MacMediaScroll.self, in: try XCTUnwrap(pager.selectedViewController).view))
    image.onSwipe?(-1)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(pager.selectedIndex, 5)
    navigation.viewerBack?(); XCTAssertEqual(selectedID, displayed[5])
    let delegate = try XCTUnwrap(pager.delegate as? MacCollectionPager.Coordinator)
    pager.selectedIndex = 6
    delegate.pageController(pager, didTransitionTo: 6); delegate.pageControllerDidEndLiveTransition(pager)
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertEqual(pager.selectedIndex, 6)
    navigation.viewerBack?(); XCTAssertEqual(selectedID, displayed[6])
  }

  func testHistoryDetailNeighborsFollowTheFilteredNativeGridAcrossSourceTypes() async throws {
    let oldCore = BackupEnvironment.core, oldSample = BackupEnvironment.sampleAsset
    let oldLibrary = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false; BackupEnvironment.core = GridHistoryCore()
    let fixture = CatalogLibraryFixture(count: 220).fetch(filter: .all, view: .all)
    BackupEnvironment.sampleAsset = { fixture.object(at: Int($0.id)) }
    defer {
      BackupEnvironment.core = oldCore; BackupEnvironment.sampleAsset = oldSample
      BackupEnvironment.usesPhotoLibrary = oldLibrary
    }
    let history = BackupHistoryModel(); await history.reload(receiver: "test-receiver")
    let state = MacHistoryGridState(); await state.resolve(history.photos + history.attention)
    let source = MacHistoryGridSource(history: history, state: state, filter: "all", type: .photo, search: "sample-1")
    let displayed = await displayedGridIDs(source)
    XCTAssertGreaterThan(displayed.count, 4)
    let context = displayed.compactMap { source.photos[$0] }
    XCTAssertEqual(context.prefix(4).map(\.id), ["job-1", "job-11", "job-13", "job-15"])
    let library = PhotoLibraryModel(); library.installSyntheticAssets(fixture)
    let navigation = MacLibraryNavigation()
    var selectedID: String?
    let host = NSHostingController(rootView: MacHistoryPreview(photo: context[0], collection: context,
      library: library, navigation: navigation, media: state, close: { selectedID = $0 }))
    host.sizingOptions = []
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = host
    window.setContentSize(NSSize(width: 900, height: 600)); window.orderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(150))
    let pager = try XCTUnwrap(nativePager(in: host.view))
    let keys = try XCTUnwrap(nativeView(MacMediaKeyView.self, in: try XCTUnwrap(pager.selectedViewController).view))
    XCTAssertTrue(keys.handle?(try rightKey(in: window)) == true)
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertEqual(pager.selectedIndex, 1)
    navigation.viewerBack?(); XCTAssertEqual(selectedID, displayed[1])
    let image = try XCTUnwrap(nativeView(MacMediaScroll.self, in: try XCTUnwrap(pager.selectedViewController).view))
    image.onSwipe?(-1)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(pager.selectedIndex, 2)
    navigation.viewerBack?(); XCTAssertEqual(selectedID, displayed[2])
    let delegate = try XCTUnwrap(pager.delegate as? MacCollectionPager.Coordinator)
    pager.selectedIndex = 3
    delegate.pageController(pager, didTransitionTo: 3); delegate.pageControllerDidEndLiveTransition(pager)
    try await Task.sleep(for: .milliseconds(80))
    navigation.viewerBack?(); XCTAssertEqual(selectedID, displayed[3],
      "An unavailable file keeps its place after PhotoKit entries in the same grid directory")
  }

  func testNativePagerDoesNotResetToThreeSlotsBetweenContinuousSwipes() throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let fetch = CatalogLibraryFixture(count: 9).fetch(filter: .all, view: .all)
    let assets = (0..<fetch.count).map { fetch.object(at: $0) }
    let library = PhotoLibraryModel(); library.installSyntheticAssets(fetch)
    let session = MediaPreviewSession(asset: assets[0], library: library, reviewAssets: assets)
    let parent = MacMediaPager(session: session, flight: MacViewerFlight(), playRequest: 0)
    let coordinator = MacMediaPager.Coordinator(parent)
    let controller = NSPageController(); controller.view = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 550))
    controller.transitionStyle = .horizontalStrip; controller.delegate = coordinator
    coordinator.install(controller)
    for index in 1...6 {
      controller.selectedIndex = index
      coordinator.pageController(controller, didTransitionTo: index)
      coordinator.pageControllerDidEndLiveTransition(controller)
      XCTAssertEqual(controller.arrangedObjects.compactMap { $0 as? Int }, Array(0..<9))
      XCTAssertEqual(controller.selectedIndex, index, "A new swipe must retain AppKit's stable strip position")
      XCTAssertEqual(session.current.asset.localIdentifier, assets[index].localIdentifier)
    }
    controller.delegate = nil; session.stop()
  }

  func testPhaseLessWheelNavigatesNativePagesAndMixedCollectionContinuously() throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let fetch = CatalogLibraryFixture(count: 9).fetch(filter: .all, view: .all)
    let assets = (0..<fetch.count).map { fetch.object(at: $0) }
    let library = PhotoLibraryModel(); library.installSyntheticAssets(fetch)
    let session = MediaPreviewSession(asset: assets[3], library: library, reviewAssets: assets)
    let parent = MacMediaPager(session: session, flight: MacViewerFlight(), playRequest: 0)
    let coordinator = MacMediaPager.Coordinator(parent)
    let controller = MediaPageController()
    let container = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 550))
    controller.view = container; controller.transitionStyle = .horizontalStrip; controller.delegate = coordinator
    coordinator.install(controller)
    let scroll = MacMediaScroll(frame: container.bounds); container.addSubview(scroll)
    container.nextResponder = controller
    var replacements = 0; scroll.onSwipe = { _ in replacements += 1 }
    func wheel(_ delta: Int32) throws {
      let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
        wheel1: 0, wheel2: delta, wheel3: 0))
      let event = try XCTUnwrap(NSEvent(cgEvent: cg))
      XCTAssertTrue(event.phase.isEmpty); XCTAssertTrue(event.momentumPhase.isEmpty)
      scroll.scrollWheel(with: event)
    }
    for index in [4, 5, 6, 5, 4, 3] {
      try wheel(index > controller.selectedIndex ? -1 : 1)
      XCTAssertEqual(controller.selectedIndex, index, "Forwarding alone is insufficient: the native selected page must change")
      XCTAssertEqual(session.current.asset.localIdentifier, assets[index].localIdentifier)
    }
    XCTAssertEqual(replacements, 0, "The native pager owns horizontal movement")
    session.stop()

    controller.delegate = nil
  }

  func testMixedCollectionUsesOneNativeDirectoryThroughSwipesAndWheelReversal() throws {
    var selected = 3
    let parent = MacCollectionPager(count: 9, selectedIndex: selected, selected: { selected = $0 },
      page: { index, _ in AnyView(Text("fixture \(index)")) })
    let coordinator = MacCollectionPager.Coordinator(parent)
    let controller = MediaPageController()
    controller.view = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 550))
    controller.transitionStyle = .horizontalStrip; controller.delegate = coordinator
    coordinator.install(controller)
    let directory = controller.arrangedObjects.compactMap { $0 as? Int }
    for index in [4, 5, 6, 5, 4, 3] {
      coordinator.pageControllerWillStartLiveTransition(controller)
      controller.selectedIndex = index
      coordinator.pageController(controller, didTransitionTo: index)
      coordinator.pageControllerDidEndLiveTransition(controller)
      XCTAssertEqual(selected, index)
      XCTAssertEqual(controller.arrangedObjects.compactMap { $0 as? Int }, directory)
      XCTAssertEqual(controller.selectedIndex, index)
      XCTAssertFalse(coordinator.transitioning)
    }
    for index in [4, 5, 4, 3] {
      let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
        wheel1: 0, wheel2: index > selected ? -1 : 1, wheel3: 0))
      controller.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
      XCTAssertEqual(selected, index)
      XCTAssertEqual(controller.selectedIndex, index)
    }
    controller.delegate = nil
  }

  func testCollectionLeftSwipeAndRightCommandSelectTheSameNativeNeighbor() {
    var selected = 3
    var animatedStep: Int?
    let parent = MacCollectionPager(count: 9, selectedIndex: selected, selected: { selected = $0 },
      page: { index, _ in AnyView(Text("fixture \(index)")) })
    let coordinator = MacCollectionPager.Coordinator(parent)
    let controller = MediaPageController()
    controller.view = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 550))
    controller.transitionStyle = .horizontalStrip; controller.delegate = coordinator
    coordinator.install(controller)
    let paging = MacCollectionPaging(index: 3, count: 9,
      move: { selected += $0 }, native: true, swipe: { selected += $0; animatedStep = $0 })
    func applySelection() {
      coordinator.parent.selectedIndex = selected
      coordinator.install(controller)
    }
    paging.move(1) // Right-arrow command in Folder, History and recent photos.
    applySelection()
    let rightNeighbor = controller.selectedIndex
    XCTAssertEqual(rightNeighbor, 4)
    selected = 3; applySelection()
    paging.moveForHorizontalMotion(-1) // The raw sign delivered by a left mouse drag.
    applySelection()
    XCTAssertEqual(animatedStep, 1)
    XCTAssertEqual(controller.selectedIndex, rightNeighbor,
      "File and PhotoKit collection leaves must reveal the same item for Left swipe and Right command")
    paging.moveForHorizontalMotion(1); applySelection()
    XCTAssertEqual(controller.selectedIndex, 3, "Reversing the media drag returns to its original neighbor")
    XCTAssertEqual(controller.arrangedObjects.compactMap { $0 as? Int }, Array(0..<9))
    controller.delegate = nil
  }

  func testColdFileEntryKeepsItsSourcePosterUntilValidationOrFailure() async throws {
    let photo = FolderPhoto(relative: "original.jpg", source_id: "original", revision: "revision-1", size: 100,
      media_type: "image/jpeg", modified_ms: 1, folder_id: "unavailable-fixture", capture_ms: 1,
      date_source: "metadata", backup: "saved", saved_at_ms: nil)
    let folders = FolderSources(backup: BackupModel.shared)
    let seed = NSImage(cgImage: try bitmap(CGSize(width: 80, height: 80)), size: .zero)
    let directory = MacFolderMediaDirectory()
    let media = directory.model(for: photo, keeping: [photo], folders: folders, poster: seed)
    XCTAssertTrue(media.image === seed, "The first native leaf must choose media, not a full-page loading branch")
    XCTAssertFalse(media.entryReady, "A grid crop cannot start or complete the full-aspect entry flight")
    XCTAssertFalse(media.failure)
    media.prepare(photo: photo, folders: folders,
      target: MacDetailPosterTarget(pixels: CGSize(width: 800, height: 600), profile: "test"), poster: seed)
    for _ in 0..<20 where !media.failure { try await Task.sleep(for: .milliseconds(5)) }
    XCTAssertTrue(media.failure, "A missing source must become actionable rather than waiting indefinitely")
    XCTAssertTrue(media.entryReady, "An explicit failure releases entry to the retained poster and recovery action")
    XCTAssertTrue(media.image === seed)
    directory.stop()
  }

  func testFilePagePixelsSurviveNativeCompletionAndHostingControllerReuse() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let folders = FolderSources(backup: BackupModel.shared)
    let photos = (0..<7).map { index in
      FolderPhoto(relative: "photo-\(index).jpg", source_id: "\(index)", revision: "1", size: 1,
        media_type: "image/jpeg", modified_ms: 0, folder_id: "fixture", capture_ms: UInt64(index + 1),
        date_source: "metadata", backup: "saved", saved_at_ms: nil)
    }
    let pictures = try photos.map { _ in NSImage(cgImage: try bitmap(CGSize(width: 80, height: 40)), size: .zero) }
    folders.previewRows = photos
    folders.previewImage = { id in photos.firstIndex { $0.id == id }.map { pictures[$0] } }
    let directory = MacFolderMediaDirectory(), navigation = MacLibraryNavigation()
    var selected = 3
    let parent = MacCollectionPager(count: photos.count, selectedIndex: selected, selected: { selected = $0 }, page: { index, _ in
      let model = directory.model(for: photos[index],
        keeping: Array(photos[max(0, selected - 1)...min(photos.count - 1, selected + 1)]), folders: folders)
      return AnyView(MacFolderPreviewPage(photo: photos[index], context: photos, folders: folders,
        navigation: navigation, media: model, close: { _ in }).id(photos[index].id))
    })
    let coordinator = MacCollectionPager.Coordinator(parent)
    let controller = MediaPageController()
    controller.view = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 550))
    controller.transitionStyle = .horizontalStrip; controller.delegate = coordinator
    let window = NSWindow(contentRect: controller.view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = controller
    window.orderFront(nil)
    defer { controller.delegate = nil; window.orderOut(nil); window.contentViewController = nil; directory.stop() }
    coordinator.install(controller)
    try await Task.sleep(for: .milliseconds(100))
    func mediaView(_ view: NSView) -> MacMediaScroll? {
      if let media = view as? MacMediaScroll { return media }
      return view.subviews.lazy.compactMap { mediaView($0) }.first
    }
    let retained = directory.model(for: photos[4], keeping: Array(photos[2...4]), folders: folders)
    for index in [4, 3, 4] {
      selected = index; coordinator.parent.selectedIndex = index
      controller.selectedIndex = index
      coordinator.pageController(controller, didTransitionTo: index)
      coordinator.pageControllerDidEndLiveTransition(controller)
      let host = try XCTUnwrap(controller.selectedViewController)
      host.view.layoutSubtreeIfNeeded()
      let displayed = try XCTUnwrap(mediaView(host.view))
      XCTAssertTrue(displayed.photo.image === pictures[index],
        "Completion must synchronously display retained pixels without waiting for a new leaf task")
      // AppKit may reuse this same host for a different page and then restore
      // it as selected. Force both layouts without yielding an async load turn.
      coordinator.pageController(controller, prepare: host, with: 6)
      host.view.layoutSubtreeIfNeeded()
      coordinator.pageController(controller, prepare: host, with: index)
      host.view.layoutSubtreeIfNeeded()
      XCTAssertTrue(try XCTUnwrap(mediaView(host.view)).photo.image === pictures[index])
      XCTAssertLessThanOrEqual(directory.retainedCount, 3)
    }
    XCTAssertTrue(directory.model(for: photos[4], keeping: Array(photos[3...5]), folders: folders) === retained,
      "A recyclable SwiftUI leaf must not own the file media session")
    _ = directory.model(for: photos[0], keeping: Array(photos[0...1]), folders: folders)
    XCTAssertLessThanOrEqual(directory.retainedCount, 2, "Distant media releases its requests and security scope")
  }

  func testNativeViewerInfoRemainsOpenAcrossWorkspaceSuspension() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let fetch = CatalogLibraryFixture(count: 3).fetch(filter: .all, view: .all)
    let asset = fetch.object(at: 0)
    let library = PhotoLibraryModel(); library.installSyntheticAssets(fetch)
    let navigation = MacLibraryNavigation(); navigation.setInformationPresented(true)
    let host = NSHostingController(rootView: MacPhotoPreview(asset: asset, library: library,
      navigation: navigation, close: { _ in }).environment(\.macWorkspaceActive, true))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    host.sizingOptions = []; window.isReleasedWhenClosed = false; window.contentViewController = host
    window.setContentSize(NSSize(width: 1000, height: 700)); window.orderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(150))
    host.view.layoutSubtreeIfNeeded()
    let info = try XCTUnwrap(MacViewerInfoPanel.existing(for: window))
    XCTAssertTrue(info.panel.isVisible)
    let viewport = host.view.bounds
    host.rootView = MacPhotoPreview(asset: asset, library: library,
      navigation: navigation, close: { _ in }).environment(\.macWorkspaceActive, false)
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(navigation.informationPresented)
    XCTAssertTrue(info.panel.isVisible, "A workspace change cannot close the user's Info window")
    XCTAssertEqual(info.store.target.identity, "selection:0")
    XCTAssertEqual(host.view.bounds, viewport, "Leaving Info never refits the photograph")
    host.rootView = MacPhotoPreview(asset: asset, library: library,
      navigation: navigation, close: { _ in }).environment(\.macWorkspaceActive, true)
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(info.panel.isVisible)
    XCTAssertTrue(MacViewerInfoPanel.existing(for: window) === info)
    XCTAssertEqual(host.view.bounds, viewport)
    info.panel.performClose(nil)
    XCTAssertFalse(navigation.informationPresented, "The native close button changes the window-global choice")
  }

  func testAnimatedInspectorOpenCloseAndReversalLeaveTheHostingGraphResponsive() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let fetch = CatalogLibraryFixture(count: 3).fetch(filter: .all, view: .all)
    let library = PhotoLibraryModel(); library.installSyntheticAssets(fetch)
    let navigation = MacLibraryNavigation()
    let host = NSHostingController(rootView: MacPhotoPreview(asset: fetch.object(at: 0), library: library,
      navigation: navigation, close: { _ in }).environment(\.macWorkspaceActive, true))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    host.sizingOptions = []; window.isReleasedWhenClosed = false; window.contentViewController = host
    window.setContentSize(NSSize(width: 1000, height: 700)); window.orderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(150))
    let info = try XCTUnwrap(MacViewerInfoPanel.existing(for: window))
    let viewport = host.view.bounds
    for _ in 0..<2 {
      withAnimation(.easeInOut(duration: DuckMotion.enter)) { navigation.setInformationPresented(true) }
      try await Task.sleep(for: .milliseconds(150))
      XCTAssertTrue(info.panel.isVisible)
      XCTAssertEqual(host.view.bounds, viewport)
      withAnimation(.easeInOut(duration: DuckMotion.enter)) { navigation.setInformationPresented(false) }
      withAnimation(.easeInOut(duration: DuckMotion.enter)) { navigation.setInformationPresented(true) }
      try await Task.sleep(for: .milliseconds(150))
      XCTAssertTrue(info.panel.isVisible)
      withAnimation(.easeInOut(duration: DuckMotion.enter)) { navigation.setInformationPresented(false) }
      try await Task.sleep(for: .milliseconds(150))
      XCTAssertFalse(info.panel.isVisible)
      XCTAssertEqual(host.view.bounds.width, 1000, accuracy: 1)
    }
    let firstOwner = UUID(), secondOwner = UUID()
    info.store.isPresented = true
    info.store.publish(.selection(2), owner: firstOwner, history: nil)
    info.store.publish(.selection(3), owner: secondOwner, history: nil)
    info.store.withdraw(owner: firstOwner)
    XCTAssertTrue(info.panel.isVisible)
    XCTAssertEqual(info.store.target.identity, "selection:3",
      "A retired contribution cannot clear the new target")
    info.store.withdraw(owner: secondOwner)
    XCTAssertTrue(info.panel.isVisible, "Withdrawing a target never closes Info")
    XCTAssertEqual(info.store.target.identity, "selection:0")
    info.panel.performClose(nil)
    XCTAssertFalse(navigation.informationPresented)
  }

  func testSettingsAlbumGridInfoFollowsSelectedAssetWithoutOpeningDetail() async throws {
    let previousLibrary = BackupEnvironment.usesPhotoLibrary
    let previousModel = BackupEnvironment.activeModel
    BackupEnvironment.usesPhotoLibrary = false
    defer {
      BackupEnvironment.usesPhotoLibrary = previousLibrary
      BackupEnvironment.activeModel = previousModel
    }
    let scenario = try XCTUnwrap(Scenario.loadAll().first { $0.id == "settings.scope.albums" })
    let model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    BackupEnvironment.activeModel = { model }
    await model.open()
    defer { model.stop() }
    let fixture = ScopeCatalogFixture(id: "settings.scope.albums")
    let album = try XCTUnwrap(fixture.albums.albums.first)
    let albumLibrary = PhotoLibraryModel()
    let fetch = CatalogLibraryFixture(count: 6).fetch(filter: .all, view: .all)
    albumLibrary.installSyntheticAssets(fetch)
    let folders = FolderSources(backup: model); folders.previewRows = []
    let host = NSHostingController(rootView: MacWorkspace(model: model, library: PhotoLibraryModel(),
      initialDestination: .settings, folderSources: folders, scopeStore: fixture.store,
      albumsModel: fixture.albums, openInitialSettingsDetail: { navigator in
        navigator.open(DuckSettingsPage(title: Text(verbatim: album.name), content: AnyView(
          MacScopeAlbumBrowser(album: album, store: fixture.store, library: albumLibrary)), usesMediaCanvas: true))
      }))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 740),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    host.sizingOptions = []; window.isReleasedWhenClosed = false; window.contentViewController = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(600))
    albumLibrary.selection = [fetch.object(at: 0).localIdentifier]
    try await Task.sleep(for: .milliseconds(300))
    func anchors(in view: NSView) -> [MacViewerInspectorAnchor] {
      (view as? MacViewerInspectorAnchor).map { [$0] } ?? view.subviews.flatMap { anchors(in: $0) }
    }
    let active = anchors(in: host.view).filter {
      Mirror(reflecting: $0).children.first { $0.label == "active" }?.value as? Bool == true
    }
    XCTAssertEqual(active.count, 1, "Only the visible album can contribute Info in Settings")
    let anchor = try XCTUnwrap(active.first)
    let navigation = try XCTUnwrap(Mirror(reflecting: anchor).children.first { $0.label == "navigation" }?.value as? MacLibraryNavigation)
    navigation.setInformationPresented(true)
    try await Task.sleep(for: .milliseconds(300))
    let info = try XCTUnwrap(MacViewerInfoPanel.existing(for: window))
    XCTAssertTrue(info.panel.isVisible); XCTAssertNotNil(info.panel.contentViewController)
    XCTAssertFalse(navigation.viewerOpen); XCTAssertTrue(navigation.informationPresented)
    XCTAssertNil(navigation.viewerCurrent); XCTAssertNil(navigation.viewerBack)
    XCTAssertEqual(info.store.target.identity, MacPhotoInformationTarget.library(fetch.object(at: 0), albumLibrary, nil).identity)
    let controller = info.panel.contentViewController, frame = info.panel.frame
    albumLibrary.selection = [fetch.object(at: 1).localIdentifier]
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(info.store.target.identity, MacPhotoInformationTarget.library(fetch.object(at: 1), albumLibrary, nil).identity)
    XCTAssertTrue(info.panel.isVisible); XCTAssertEqual(info.panel.frame, frame)
    XCTAssertTrue(info.panel.contentViewController === controller)
    albumLibrary.selection = []
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(info.store.target.identity, "selection:0")
    XCTAssertTrue(info.panel.isVisible, "Clearing selection keeps Info open for the selection instruction")
    XCTAssertTrue(info.panel.contentViewController === controller)
    XCTAssertEqual(info.panel.frame, frame)
    albumLibrary.selection = [fetch.object(at: 2).localIdentifier]
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(info.store.target.identity, MacPhotoInformationTarget.library(fetch.object(at: 2), albumLibrary, nil).identity)
    XCTAssertTrue(info.panel.isVisible)
    albumLibrary.selection = [fetch.object(at: 1).localIdentifier, fetch.object(at: 2).localIdentifier]
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(info.store.target.identity, "selection:2")
    info.panel.performClose(nil)
    XCTAssertFalse(navigation.informationPresented)
  }

  func testWorkspaceFolderInfoFollowsSelectionAndWorkspaceOwnership() async throws {
    let previousLibrary = BackupEnvironment.usesPhotoLibrary
    let previousModel = BackupEnvironment.activeModel
    let previousFolders = FolderSources.catalog
    BackupEnvironment.usesPhotoLibrary = false
    defer {
      BackupEnvironment.usesPhotoLibrary = previousLibrary
      BackupEnvironment.activeModel = previousModel; FolderSources.catalog = previousFolders
    }
    let scenario = try XCTUnwrap(Scenario.loadAll().first { $0.id == "folders.sections" })
    let model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    BackupEnvironment.activeModel = { model }
    let folders = FolderSources(backup: model)
    FolderSources.catalog = folders
    FolderCatalog.install("folders.sections", folders: folders, sheet: nil)
    await model.open()
    defer { model.stop() }
    let library = PhotoLibraryModel()
    library.installSyntheticAssets(CatalogLibraryFixture(count: 90).fetch(filter: .all, view: .all))
    let host = NSHostingController(rootView: MacWorkspace(model: model, library: library,
      initialDestination: .sources, folderSources: folders))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 740),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    host.sizingOptions = []; window.isReleasedWhenClosed = false; window.contentViewController = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(800))
    let photo = try XCTUnwrap(folders.browser.sections.flatMap(\.photos).first { $0.relative == "Coast/IMG_1000.jpg" })
    folders.browser.selection = [photo.id]
    try await Task.sleep(for: .milliseconds(400))
    func anchors(in view: NSView) -> [MacViewerInspectorAnchor] {
      (view as? MacViewerInspectorAnchor).map { [$0] } ?? view.subviews.flatMap { anchors(in: $0) }
    }
    let contributors = anchors(in: host.view)
    let active = contributors.filter { Mirror(reflecting: $0).children.first { $0.label == "active" }?.value as? Bool == true }
    print("Grid Info actual contributors: total=\(contributors.count), active=\(active.count)")
    XCTAssertEqual(active.count, 1)
    let anchor = try XCTUnwrap(active.first)
    let navigation = try XCTUnwrap(Mirror(reflecting: anchor).children.first { $0.label == "navigation" }?.value as? MacLibraryNavigation)
    XCTAssertFalse(navigation.viewerOpen)
    navigation.setInformationPresented(true)
    try await Task.sleep(for: .milliseconds(400))
    let info = try XCTUnwrap(MacViewerInfoPanel.existing(for: window))
    print("Grid Info integration: visible=\(info.panel.isVisible), key=\(info.panel.isKeyWindow), frame=\(info.panel.frame), controller=\(String(describing: info.panel.contentViewController))")
    XCTAssertTrue(info.panel.isVisible, "The real workspace must keep the selected grid's panel visible")
    XCTAssertNotNil(info.panel.contentViewController)
    let frame = info.panel.frame
    let controller = info.panel.contentViewController
    let next = try XCTUnwrap(folders.browser.sections.flatMap(\.photos).first { $0.id != photo.id })
    folders.browser.selection = [next.id]
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertTrue(info.panel.isVisible); XCTAssertEqual(info.panel.frame, frame)
    XCTAssertTrue(info.panel.contentViewController === controller)
    folders.browser.selection = []
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertTrue(info.panel.isVisible, "The folder Info panel stays open with selection guidance")
    XCTAssertTrue(info.panel.contentViewController === controller)
    XCTAssertEqual(info.panel.frame, frame)
    folders.browser.selection = [next.id]
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertTrue(info.panel.isVisible)
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowTransfers"), object: nil)
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertTrue(info.panel.isVisible)
    XCTAssertEqual(info.store.target.identity, "selection:0")
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowFolders"), object: nil)
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertTrue(info.panel.isVisible, "Returning updates the existing window to the grid selection")
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
      timestamp: 0, windowNumber: info.panel.windowNumber, context: nil, characters: "i",
      charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
    XCTAssertTrue(info.panel.performKeyEquivalent(with: event))
    XCTAssertFalse(info.panel.isVisible)
  }

  func testGridInspectorFollowsSelectionWithoutEnteringViewerAndClosesFromPanel() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let fetch = CatalogLibraryFixture(count: 3).fetch(filter: .all, view: .all)
    let library = PhotoLibraryModel(); library.installSyntheticAssets(fetch)
    let navigation = MacLibraryNavigation()
    let toolbar = MacGridToolbarState()
    let host = NSHostingController(rootView: GridInspectorTestSurface(library: library, navigation: navigation, toolbar: toolbar))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    host.sizingOptions = []; window.isReleasedWhenClosed = false; window.contentViewController = host
    window.orderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(toolbar.hasSource); XCTAssertTrue(toolbar.canInspect)
    XCTAssertTrue(library.selection.isEmpty)
    toolbar.showInformation()
    try await Task.sleep(for: .milliseconds(150))
    let info = try XCTUnwrap(MacViewerInfoPanel.existing(for: window))
    XCTAssertTrue(info.panel.isVisible, "The parent Info action opens selection guidance before a photo is selected")
    XCTAssertEqual(info.panel.contentLayoutRect.width, 320, accuracy: 1)
    XCTAssertEqual(info.panel.contentLayoutRect.height, 480, accuracy: 1)
    info.panel.setContentSize(NSSize(width: 420, height: 570))
    let panelFrame = info.panel.frame
    let controller = info.panel.contentViewController
    library.selection = [fetch.object(at: 1).localIdentifier]
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(info.panel.isVisible)
    XCTAssertTrue(info.panel.contentViewController === controller)
    XCTAssertEqual(info.panel.frame, panelFrame)
    XCTAssertFalse(navigation.viewerOpen); XCTAssertTrue(navigation.informationPresented)
    XCTAssertNil(navigation.viewerCurrent); XCTAssertNil(navigation.viewerBack)
    library.selection = []
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(info.panel.isVisible, "Clearing selection keeps Info open for the selection instruction")
    XCTAssertTrue(info.panel.contentViewController === controller)
    XCTAssertEqual(info.panel.frame, panelFrame)
    XCTAssertTrue(navigation.informationPresented)
    library.selection = [fetch.object(at: 0).localIdentifier, fetch.object(at: 1).localIdentifier]
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(info.panel.isVisible)
    navigation.level = .years
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(info.panel.isVisible, "Calendar navigation cannot close Info")
    XCTAssertEqual(info.store.target.identity, "selection:0", "Calendar covers do not inspect a hidden All Photos selection")
    navigation.level = .all
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(info.panel.isVisible)
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
      timestamp: 0, windowNumber: info.panel.windowNumber, context: nil, characters: "i",
      charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
    XCTAssertTrue(info.panel.performKeyEquivalent(with: event))
    XCTAssertFalse(navigation.informationPresented)
    XCTAssertFalse(info.panel.isVisible)
  }

  func testWorkspaceInfoKeepsCurrentPhotoThroughViewerReturnAndTabChange() async throws {
    let previousLibrary = BackupEnvironment.usesPhotoLibrary
    let previousModel = BackupEnvironment.activeModel, previousFolders = FolderSources.catalog
    BackupEnvironment.usesPhotoLibrary = false
    defer {
      BackupEnvironment.usesPhotoLibrary = previousLibrary
      BackupEnvironment.activeModel = previousModel; FolderSources.catalog = previousFolders
    }
    let scenario = try XCTUnwrap(Scenario.loadAll().first { $0.id == "folders.sections" })
    let model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    BackupEnvironment.activeModel = { model }
    let folders = FolderSources(backup: model); FolderSources.catalog = folders
    FolderCatalog.install("folders.sections", folders: folders, sheet: nil)
    await model.open(); defer { model.stop() }
    let photos = try XCTUnwrap(folders.previewRows)
    let photo = try XCTUnwrap(photos.first)
    let request = MacViewerRequest.folder(photo, photos, folders, nil, navigation: nil)
    let host = NSHostingController(rootView: MacWorkspace(model: model, library: PhotoLibraryModel(),
      initialDestination: .sources, folderSources: folders, initialViewer: request, initialViewerInfo: true))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 740),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    host.sizingOptions = []; window.isReleasedWhenClosed = false; window.contentViewController = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close(); window.contentViewController = nil }
    try await Task.sleep(for: .milliseconds(600))
    let info = try XCTUnwrap(MacViewerInfoPanel.existing(for: window))
    XCTAssertTrue(info.panel.isVisible)
    let expected = MacPhotoInformationTarget.folder(photo, folders, nil).identity
    XCTAssertEqual(info.store.target.identity, expected)
    let controller = info.panel.contentViewController, frame = info.panel.frame
    func anchors(in view: NSView) -> [MacViewerInspectorAnchor] {
      (view as? MacViewerInspectorAnchor).map { [$0] } ?? view.subviews.flatMap { anchors(in: $0) }
    }
    let active = try XCTUnwrap(anchors(in: host.view).first {
      Mirror(reflecting: $0).children.first { $0.label == "active" }?.value as? Bool == true
    })
    let navigation = try XCTUnwrap(Mirror(reflecting: active).children.first { $0.label == "navigation" }?.value as? MacLibraryNavigation)
    let close = try XCTUnwrap(navigation.viewerBack)
    close()
    for _ in 0..<40 where folders.browser.selection != [photo.id] || info.store.target.identity != expected {
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(folders.browser.selection, [photo.id])
    XCTAssertTrue(info.panel.isVisible); XCTAssertTrue(info.panel.contentViewController === controller)
    XCTAssertEqual(info.panel.frame, frame); XCTAssertEqual(info.store.target.identity, expected)
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowTransfers"), object: nil)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertTrue(info.panel.isVisible); XCTAssertEqual(info.store.target.identity, "selection:0")
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowFolders"), object: nil)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertTrue(info.panel.isVisible); XCTAssertEqual(info.store.target.identity, expected)
    info.panel.performClose(nil)
    NotificationCenter.default.post(name: Notification.Name("BackupDuckShowTransfers"), object: nil)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertFalse(info.panel.isVisible, "Changing position cannot reopen a user-closed panel")
  }

  func testInformationSourceFactoriesAndActionsAreSharedByGridAndViewer() async throws {
    let previousLibrary = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = previousLibrary }
    let fetch = CatalogLibraryFixture(count: 2).fetch(filter: .all, view: .all)
    let library = PhotoLibraryModel(); library.installSyntheticAssets(fetch)
    let source = MacPhotoLibrarySource(library)
    let id = try XCTUnwrap(source.identifiers.first)
    let asset = try XCTUnwrap(source.asset(id))
    let grid = source.informationTarget(id)
    let viewer = MacPhotoInformationTarget.library(asset, library, nil)
    XCTAssertEqual(grid.identity, viewer.identity)
    guard case let .library(gridAsset, gridLibrary, _) = grid else { return XCTFail("Both surfaces must use the library information factory") }
    XCTAssertEqual(gridAsset.localIdentifier, asset.localIdentifier); XCTAssertTrue(gridLibrary === library)
    let scenario = try XCTUnwrap(Scenario.loadAll().first { $0.id == "folders.sections" })
    let model = scenario.makeModel(core: MacCatalogApp.core, credentials: MacCatalogApp.credentials)
    let folders = FolderSources(backup: model)
    FolderCatalog.install("folders.sections", folders: folders, sheet: nil)
    let photo = try XCTUnwrap(folders.previewRows?.first)
    await folders.browser.reload(folders)
    let folderSource = MacFolderGridSource(folders: folders, browser: folders.browser)
    let folderGrid = folderSource.informationTarget(photo.id)
    XCTAssertEqual(folderGrid.identity, MacPhotoInformationTarget.folder(photo, folders, nil).identity)
    guard case let .folder(gridPhoto, gridFolders, _) = folderGrid else { return XCTFail("Both surfaces must use the file information factory") }
    XCTAssertEqual(gridPhoto.id, photo.id); XCTAssertTrue(gridFolders === folders)
    XCTAssertEqual(MacPhotoInformationAction.resolve(loaded: true, unavailable: false,
      state: "photo_viewer_not_backed_up", paired: true, canBackUp: true, hasJob: false), .backup)
    XCTAssertEqual(MacPhotoInformationAction.resolve(loaded: true, unavailable: false,
      state: "photo_viewer_failed", paired: true, canBackUp: true, hasJob: false), .retry)
    XCTAssertEqual(MacPhotoInformationAction.resolve(loaded: true, unavailable: false,
      state: "photo_viewer_failed", paired: false, canBackUp: false, hasJob: true), .retry)
    XCTAssertEqual(MacPhotoInformationAction.resolve(loaded: false, unavailable: false,
      state: "photo_viewer_not_backed_up", paired: true, canBackUp: true, hasJob: false), .none)
    XCTAssertEqual(MacPhotoInformationAction.resolve(loaded: true, unavailable: true,
      state: "photo_viewer_failed", paired: true, canBackUp: true, hasJob: true), .none)
  }

  func testGridAndViewerShareOneWindowInfoLifetimeAndDismissal() throws {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.orderFront(nil)
    defer { window.close() }
    let info = MacViewerInfoPanel.forWindow(window)
    let grid = MacLibraryNavigation(), viewer = MacLibraryNavigation()
    grid.bindInformation(info.store); viewer.bindInformation(info.store)
    let gridOwner = UUID(), viewerOwner = UUID()
    grid.setInformationPresented(true)
    info.store.publish(.selection(2), owner: gridOwner, history: nil)
    let controller = info.panel.contentViewController
    info.store.publish(.selection(1), owner: viewerOwner, history: nil)
    info.store.withdraw(owner: gridOwner)
    XCTAssertTrue(info.panel.isVisible); XCTAssertEqual(info.store.target.identity, "selection:1")
    XCTAssertTrue(grid.informationPresented); XCTAssertTrue(viewer.informationPresented)
    info.store.withdraw(owner: viewerOwner)
    XCTAssertTrue(info.panel.isVisible); XCTAssertEqual(info.store.target.identity, "selection:0")
    XCTAssertTrue(info.panel.contentViewController === controller)
    info.panel.performClose(nil)
    XCTAssertFalse(grid.informationPresented); XCTAssertFalse(viewer.informationPresented)
    info.store.publish(.selection(3), owner: gridOwner, history: nil)
    XCTAssertFalse(info.panel.isVisible, "Navigation must not reopen a user-closed Info window")
  }

}


private struct GridInspectorTestSurface: View {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var navigation: MacLibraryNavigation
  let toolbar: MacGridToolbarState
  var body: some View {
    Color.clear.modifier(MacGridInspector(navigation: navigation, source: MacPhotoLibrarySource(library)))
      .environment(\.macGridToolbarState, toolbar)
      .toolbar { ToolbarItem { MacGridInfoButton(state: toolbar) } }
  }
}

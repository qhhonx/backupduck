import XCTest
import Photos

@testable import BackupDuck

final class CalendarGridTests: XCTestCase {
  @MainActor func testDenseCanvasRetainsSynchronousArrivalsAndPublishedPixels() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let photo = UIGraphicsImageRenderer(size: CGSize(width: 64,height: 64),format: format).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0,y: 0,width: 64,height: 64))
    }
    let canvas = CalendarDenseCanvas(frame: CGRect(x: 0,y: 0,width: 402,height: 874))
    let assets = (0..<12000).map { CalendarGridAsset(id: "photo-\($0)",date: nil,aspect: 1) }
    let geometry = CalendarGridGeometry(assets: assets,level: .all,width: 402,columns: 31,originalAspect: false)
    var cache: [Int: UIImage] = [:]
    canvas.cachedImage = { cache[$0] }
    canvas.request = { asset,_,done in cache[asset] = photo; done(photo); return {} }
    canvas.reset(geometry,columns: 31,fill: true)
    canvas.update(visible: canvas.bounds,scale: 1)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in canvas.isReady(in: canvas.bounds) },object: nil)
    await fulfillment(of: [ready],timeout: 5)
    // A cached completion can precede context creation. Publication alone is
    // insufficient: the bitmap must actually contain those completed tiles.
    let painted = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in canvas.displayedImage(500) != nil },object: nil)
    await fulfillment(of: [painted],timeout: 5)
    cache = [:]
    let retained = try XCTUnwrap(canvas.displayedImage(500))
    XCTAssertGreaterThan(retained.cgImage?.width ?? 0,0,"Eviction must not erase pixels already displayed by the canvas")
    // Reuse strips while their old publication is still queued. A publication
    // from one generation cannot suppress the new generation's bitmap.
    for y: CGFloat in [2000,0,2400,0] { canvas.update(visible: canvas.bounds.offsetBy(dx: 0,dy: y),scale: 1) }
    let recycled = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
      canvas.isReady(in: canvas.bounds) && canvas.displayedImage(500) != nil
    },object: nil)
    await fulfillment(of: [recycled],timeout: 5)
    canvas.stop()
  }

  @MainActor func testDenseHandoffWaitsForBitmapAndNextGestureSurvivesCacheEviction() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let photo = UIGraphicsImageRenderer(size: CGSize(width: 64,height: 64),format: format).image { ctx in
      UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0,y: 0,width: 64,height: 64))
    }
    let c = controller(6000,image: photo)
    c.place(40000)
    c.denseCanvas.renderQueue.suspend()
    var suspended = true
    defer { if suspended { c.denseCanvas.renderQueue.resume() }; c.stopMotion() }
    c.density(columns: 31,at: 3000)
    c.completeStage()
    try await Task.sleep(for: .milliseconds(60))
    XCTAssertNotNil(c.adoptionCover,"A delayed bitmap renderer must not expose empty strips after the animation ends")
    XCTAssertFalse(c.denseCanvas.isReady(in: c.grid.bounds))
    c.denseCanvas.renderQueue.resume(); suspended = false
    let adopted = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
      c.denseCanvas.isReady(in: c.grid.bounds) && c.adoptionCover == nil
    },object: nil)
    await fulfillment(of: [adopted],timeout: 5)
    c.transitionImages.removeAllObjects(); c.transitionSmallImages.removeAllObjects()
    c.requestImage = { _,_,done in done(nil,false); return {} }
    c.beginStage(point: CGPoint(x: 201,y: c.grid.contentOffset.y+437),item: nil,distance: 300)
    let stage = try XCTUnwrap(c.stage),face = try XCTUnwrap(stage.faces[31])
    XCTAssertGreaterThan(stage.loaded(face),0.95,"The new gesture takes its source from the displayed bitmap, even when all image caches miss")
    let tile = try XCTUnwrap(face.tiles.values.first { $0.convert($0.bounds,to: stage.layer).intersects(stage.bounds) })
    let before = tile.convert(tile.bounds,to: stage.layer)
    stage.pitch *= 1.00001; stage.layoutAll()
    let after = tile.convert(tile.bounds,to: stage.layer)
    XCTAssertEqual(after.width/before.width,1.00001,accuracy: 0.000001,"Grouped dense scaling follows the fingers continuously")
  }

  @MainActor func testSingleColumnKeepsAvailableFallbackUntilUncroppedRenditionArrives() throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    func bitmap(_ size: CGSize) -> UIImage { UIGraphicsImageRenderer(size: size,format: format).image { _ in } }
    let fallback = bitmap(CGSize(width: 64,height: 64)), full = bitmap(CGSize(width: 768,height: 1024))
    let c = controller(1)
    c.assets = [CalendarGridAsset(id: "portrait",date: nil,aspect: 0.75)]
    c.columns = 1
    var deliver: ((UIImage?,Bool)->Void)?
    c.requestUncroppedImage = { _,_,done in deliver = done; done(fallback,false); return {} }
    c.layout.geometry = CalendarGridGeometry(assets: c.assets,level: .all,width: 402,columns: 1,originalAspect: false)
    let cell = try XCTUnwrap(c.collectionView(c.grid,cellForItemAt: IndexPath(item: 0,section: 0)) as? CalendarGridCell)
    XCTAssertTrue(cell.image.image === fallback,"A cropped fallback is usable while full-aspect pixels are pending")
    XCTAssertTrue(cell.placeholder.isHidden)
    deliver?(full,false); deliver?(fallback,false); deliver?(nil,true)
    XCTAssertTrue(cell.image.image === full,"Late fallback/nil results cannot erase or downgrade the visible photo")
    XCTAssertTrue(cell.placeholder.isHidden)
    let tile = CalendarZoomStage.Tile(); tile.columns = 1
    c.rememberImage(bitmap(CGSize(width: 1024,height: 1024)),for: "portrait")
    deliver = nil
    _ = c.stageTile(tile.photo,asset: 0,pixels: 512)
    XCTAssertNotNil(deliver,"The one-column target requests its own crop before it becomes the current density")
    deliver?(full,false)
    XCTAssertTrue(tile.presentedImage === full)
  }


  @MainActor func testSelectedVideoDurationDoesNotOverlapSelectionAtOrdinaryDensities() {
    for side: CGFloat in [80, 132, 440] {
      let decorations = CalendarTileDecorations(frame: CGRect(x: 0,y: 0,width: side,height: side))
      decorations.duration.text = "1:23"
      decorations.selection(true, enabled: true)
      decorations.setNeedsLayout(); decorations.layoutIfNeeded()
      XCTAssertFalse(decorations.duration.isHidden)
      XCTAssertLessThanOrEqual(decorations.duration.frame.maxX,decorations.check.frame.minX-6)
    }
  }

  @MainActor func testMediaRingHasOneLoadingOwnerAndOnlyRealProgress() {
    let ring = MediaLoadingIndicator(frame: CGRect(x: 0,y: 0,width: 36,height: 36))
    ring.layoutIfNeeded(); ring.update(loading: true,progress: 0,cloud: false,failure: false)
    XCTAssertFalse(ring.isHidden); XCTAssertNil(ring.accessibilityValue)
    XCTAssertFalse(ring.isUserInteractionEnabled)
    ring.update(loading: true,progress: 0.62,cloud: false,failure: false)
    XCTAssertEqual(ring.arc.strokeEnd,0.62,accuracy: 0.001)
    XCTAssertEqual(ring.accessibilityValue,"62%")
    XCTAssertNil(ring.arc.animation(forKey: "loading.rotation"))
    ring.update(loading: false,progress: 0,cloud: false,failure: true)
    XCTAssertFalse(ring.isHidden); XCTAssertTrue(ring.isUserInteractionEnabled)
    XCTAssertTrue(ring.arc.isHidden); XCTAssertFalse(ring.symbol.isHidden)
    ring.update(loading: false,progress: 1,cloud: false,failure: false)
    XCTAssertTrue(ring.isHidden)
  }

  @MainActor func testNativePageExistsBeforeImageArrivalAndKeepsFlightPose() throws {
    let fetch = PHAsset.fetchAssets(with: .image,options: photoLibraryFetchOptions())
    guard let asset = fetch.firstObject else { throw XCTSkip("Import synthetic fixtures") }
    let library = PhotoLibraryModel(), model = MediaPreviewModel(asset: asset)
    let session = MediaPreviewSession(asset: asset,library: library)
    let page = NativeMediaPage(model: model,session: session)
    page.loadViewIfNeeded(); page.view.frame = CGRect(x: 0,y: 0,width: 402,height: 874); page.view.layoutIfNeeded()
    let surface = page.surface, bounds = surface.bounds
    XCTAssertGreaterThan(bounds.width,0,"An empty poster cannot skip the entry animation")
    page.flightLocked = true
    let pose = CGAffineTransform(translationX: -60,y: -120).scaledBy(x: 0.2,y: 0.2)
    surface.transform = pose
    page.refresh(); page.view.setNeedsLayout(); page.view.layoutIfNeeded()
    XCTAssertTrue(page.surface === surface); XCTAssertEqual(surface.transform,pose)
    XCTAssertEqual(surface.bounds,bounds,"Readiness and layout must not replace the animated rectangle")
  }

  @MainActor func testVideoReadinessKeepsPosterAndSameNodeThroughFlight() async throws {
    let fetch = PHAsset.fetchAssets(with: .video,options: photoLibraryFetchOptions())
    guard let asset = fetch.firstObject else { throw XCTSkip("Import synthetic video") }
    let poster = UIGraphicsImageRenderer(size: CGSize(width: 160,height: 90)).image { c in UIColor.orange.setFill(); c.fill(CGRect(x: 0,y: 0,width: 160,height: 90)) }
    let library = PhotoLibraryModel(), model = MediaPreviewModel(asset: asset,poster: poster)
    let session = MediaPreviewSession(asset: asset,library: library)
    let page = NativeMediaPage(model: model,session: session), window = UIWindow(frame: CGRect(x: 0,y: 0,width: 402,height: 874))
    window.rootViewController = page; window.makeKeyAndVisible(); page.view.layoutIfNeeded()
    defer { model.cancel(); window.isHidden = true }
    let surface = page.surface, rect = surface.bounds
    page.flightLocked = true; model.load(promptForCloud: false)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in page.videoReady },object: nil)
    await fulfillment(of: [ready],timeout: 10)
    XCTAssertTrue(page.surface === surface); XCTAssertEqual(surface.bounds,rect)
    XCTAssertNotNil(page.scroll.photo.image); XCTAssertEqual(page.video.view.alpha,0,"Readiness must not swap the face during a flight")
    page.flightLocked = false
    XCTAssertEqual(page.video.view.alpha,1); XCTAssertTrue(page.video.parent === page)
  }

  @MainActor func testMediaDragKeepsGrabbedPointUnderFingerWhileScaling() {
    let center = CGPoint(x: 201,y: 437), origin = CGPoint(x: 130,y: 350)
    for point in [CGPoint(x: 48,y: 183),CGPoint(x: -65,y: 120),CGPoint(x: 20,y: -30)] {
      let pose = MediaFlightGeometry.drag(origin: origin,center: center,translation: point)
      let local = CGPoint(x: origin.x-center.x,y: origin.y-center.y).applying(pose)
      XCTAssertEqual(local.x+center.x,origin.x+point.x,accuracy: 0.001)
      XCTAssertEqual(local.y+center.y,origin.y+point.y,accuracy: 0.001)
    }
  }
  @MainActor func testMediaFlightCropMeetsPortraitAndLandscapeGridTargets() {
    for size in [CGSize(width: 402,height: 302),CGSize(width: 402,height: 750)] {
      let bounds = CGRect(origin: .zero,size: size)
      let fitted = CGRect(x: 0,y: (874-size.height)/2,width: size.width,height: size.height)
      for thumbnail in [CGRect(x: 90,y: 150,width: 78,height: 78),CGRect(x: 0,y: 470,width: 134,height: 90)] {
        let flight = MediaFlightGeometry(bounds: bounds,fitted: fitted,thumbnail: thumbnail)
        XCTAssertTrue(bounds.insetBy(dx: -0.001,dy: -0.001).contains(flight.crop))
        let scale = flight.transform.a
        XCTAssertEqual(flight.transform.d,scale)
        XCTAssertEqual(flight.crop.width*scale,thumbnail.width,accuracy: 0.001)
        XCTAssertEqual(flight.crop.height*scale,thumbnail.height,accuracy: 0.001)
        XCTAssertEqual(fitted.midX+flight.transform.tx,thumbnail.midX,accuracy: 0.001)
        XCTAssertEqual(fitted.midY+flight.transform.ty,thumbnail.midY,accuracy: 0.001)
      }
    }
  }

  @MainActor func testFilmstripFractionalFocusIsContinuousAndLookupRemainsBounded() throws {
    let source = MediaStripTestSource(), layout = MediaFilmstripLayout()
    let strip = UICollectionView(frame: CGRect(x: 0,y: 0,width: 402,height: 46),collectionViewLayout: layout)
    strip.register(UICollectionViewCell.self,forCellWithReuseIdentifier: "tile")
    strip.dataSource = source; strip.reloadData(); strip.layoutIfNeeded()
    layout.current = 25000; layout.aspect = 4/3; layout.neighborAspects = [25000: 4/3,25001: 0.75]
    layout.focus = 25000.5
    let first = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 25000,section: 0)))
    let next = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 25001,section: 0)))
    XCTAssertGreaterThan(first.frame.width,20); XCTAssertGreaterThan(next.frame.width,20)
    XCTAssertGreaterThan(next.frame.minX,first.frame.maxX)
    let visible = layout.layoutAttributesForElements(in: CGRect(x: layout.focusCenter-201,y: 0,width: 402,height: 46)) ?? []
    XCTAssertLessThan(visible.count,25,"Only visible filmstrip cells are visited in a 55k library")
    layout.focus = 25001-0.000001
    let before = layout.focusCenter
    layout.current = 25001; layout.focus = nil; layout.aspect = 0.75
    XCTAssertEqual(layout.focusCenter,before,accuracy: 0.001,"Adopting page identity must not recenter the strip discontinuously")
    layout.expansion = 0; layout.invalidateLayout()
    for index in [0,25000,54999] { XCTAssertEqual(layout.nearest(layout.center(index)),index) }
  }

  /// The launch density is remembered; fixtures start from the default three columns.
  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: CalendarGridController.densityKey)
  }
  @MainActor private func settle(_ controller: CalendarGridController) {
    guard let animator = controller.spring else { return }
    if animator.state == .inactive { animator.startAnimation() }
    animator.stopAnimation(false); animator.finishAnimation(at:.end)
  }

  @MainActor func testRapidHierarchyReplacementCancelsWithoutCommittingOldCompletion() {
    let c = CalendarGridController()
    let assets = (0..<55000).map { CalendarGridAsset(id:"stress-\($0)",
      date:Date(timeIntervalSince1970:1577836800+Double($0)*2700),aspect:1) }
    c.assets = assets; c.loadViewIfNeeded()
    c.view.frame = CGRect(x:0,y:0,width:402,height:874); c.view.layoutIfNeeded()
    for step in 0..<120 {
      c.changeLevel(step % 2 == 0 ? .months : .years,asset:assets.count-10,from:nil)
      if step % 10 == 0 { c.replaceAssets(assets) }
    }
    c.stopMotion()
    XCTAssertNil(c.spring); XCTAssertNil(c.transitionOverlay)
    XCTAssertFalse(c.changing); XCTAssertEqual(c.grid.alpha,1)
    XCTAssertTrue(c.grid.visibleCells.allSatisfy { !$0.isHidden })
  }
  @MainActor func testSmallerLatePosterCannotReplacePreparedSharperPixels() {
    let c = CalendarGridController()
    let image: (CGFloat)->UIImage = { side in
      let f = UIGraphicsImageRendererFormat(); f.scale = 1
      return UIGraphicsImageRenderer(size:CGSize(width:side,height:side),format:f).image { _ in }
    }
    let sharp = image(512),small = image(64)
    c.rememberImage(sharp,for:"photo"); c.rememberImage(small,for:"photo")
    XCTAssertTrue(c.transitionImages.object(forKey:"photo") === sharp)
    XCTAssertTrue(c.transitionSmallImages.object(forKey:"photo") === small)
    c.assets = [CalendarGridAsset(id: "photo", date: nil, aspect: 1)]
    let layer = CALayer()
    _ = c.stageTile(layer, asset: 0, pixels: 64)
    XCTAssertEqual((layer.contents as! CGImage).width, 64, "Dense tiles use their small tier while sharper return pixels remain cached")
  }

  @MainActor func testMediaPosterReplacementKeepsAssetFittedRectangle() {
    let media = MediaZoomScroll(frame: CGRect(x: 0,y: 0,width: 390,height: 650))
    media.mediaSize = CGSize(width: 3024,height: 4032)
    media.photo.image = UIGraphicsImageRenderer(size: CGSize(width: 128,height: 128)).image { _ in }
    media.layoutIfNeeded()
    let original = media.media.frame, originalInset = media.contentInset
    media.photo.image = UIGraphicsImageRenderer(size: CGSize(width: 600,height: 800)).image { _ in }
    media.setNeedsLayout(); media.layoutIfNeeded()
    XCTAssertEqual(media.media.frame,original,"The cropped grid poster cannot determine the detail aspect ratio")
    XCTAssertEqual(media.contentInset,originalInset)
    XCTAssertEqual(media.media.bounds.width/media.media.bounds.height,0.75,accuracy: 0.001)
    media.media.transform = CGAffineTransform(translationX: 30,y: 80).scaledBy(x: 0.92,y: 0.92)
    XCTAssertEqual(media.frame,CGRect(x: 0,y: 0,width: 390,height: 650),"Only media moves; the letterboxed viewport stays fixed")
    XCTAssertEqual(media.media.transform.ty,80)
  }
  func testCalendarHierarchyKeepsEveryMemberAndCoverWithinItsPeriod() {
    let calendar = Calendar(identifier: .gregorian)
    let assets = (0..<120).map { i in
      CalendarGridAsset(
        id: "asset-\(i)",
        date: calendar.date(
          from: DateComponents(year: 2023 + i / 60, month: 1 + i % 60 / 10, day: 1 + i % 10 / 2)),
        aspect: 1.5)
    }
    for level in [CalendarGridLevel.years, .months, .all] {
      let g = CalendarGridGeometry(
        assets: assets, level: level, width: 390, columns: 5, originalAspect: false)
      XCTAssertEqual(g.tiles.flatMap { Array($0.members) }.sorted(), Array(assets.indices))
      XCTAssertTrue(g.tiles.allSatisfy { $0.members.contains($0.asset) })
      XCTAssertTrue(g.tiles.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= 391 })
      for y in stride(from: 0.0, to: Double(g.height), by: 500) {
        let viewport = CGRect(x: 0, y: y, width: 390, height: 500)
        let range = g.visible(in: viewport)
        for i in g.tiles.indices where g.tiles[i].frame.intersects(viewport) {
          XCTAssertTrue(
            range.contains(i), "A tall hero tile must remain visible alongside shorter mosaic tiles"
          )
        }
      }
    }
  }
  func testMonthSamplingCapsCoversAndRetainsEveryDayMember() {
    let calendar = Calendar(identifier:.gregorian)
    let assets = (0..<62).map { i in CalendarGridAsset(id:"day-\(i)",
      date:calendar.date(from:DateComponents(year:2026,month:1+6*(i/31),day:1+i%31)),aspect:1) }
    let g = CalendarGridGeometry(assets:assets,level:.months,width:402,columns:3,originalAspect:false)
    XCTAssertEqual(g.tiles.count,12)
    XCTAssertEqual(g.headings.count,2)
    XCTAssertEqual(g.tiles.flatMap { Array($0.members) }.sorted(),Array(assets.indices))
    XCTAssertTrue(g.tiles.allSatisfy { $0.members.contains($0.asset) })
    XCTAssertTrue(g.tiles.contains { $0.members.contains(61) })
  }
  @MainActor func testPeriodButtonsAdoptDestinationSizeBeforeLatestAnchor() {
    let c = CalendarGridController()
    let calendar = Calendar(identifier:.gregorian)
    c.assets = (0..<7000).map { i in CalendarGridAsset(id:"day-\(i)",
      date:calendar.date(byAdding:.day,value:i,to:Date(timeIntervalSince1970:1200000000)),aspect:1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    for level in [CalendarGridLevel.months,.years,.all,.years] {
      c.changeLevel(level,asset:6990,from:nil)
      settle(c)
      let tile = c.layout.geometry.tiles.firstIndex { $0.members.contains(6990) }!
      let frame = c.layout.frame(tile).offsetBy(dx:0,dy:-c.grid.contentOffset.y)
      XCTAssertTrue(frame.intersects(c.grid.frame),"Period controls keep the recent photo's period visible")
      XCTAssertGreaterThan(c.grid.contentOffset.y,1000)
      XCTAssertEqual(c.grid.contentSize.height,c.layout.geometry.height,accuracy:0.1)
    }
  }
  @MainActor func testButtonChainKeepsItsFocalPhotoWhenYearCardsCannotCenterAtEnd() {
    let c = CalendarGridController()
    c.assets = (0..<55000).map { i in CalendarGridAsset(id:"photo-\(i)",
      date:Date(timeIntervalSince1970:1577836800+Double(i)*2700),aspect:1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    let focal = c.focusedAsset()
    c.dock.selectedSegmentIndex = CalendarGridLevel.months.rawValue; c.levelChosen()
    settle(c)
    XCTAssertEqual(c.focusedAsset(),focal)
    c.dock.selectedSegmentIndex = CalendarGridLevel.years.rawValue; c.levelChosen()
    settle(c)
    XCTAssertEqual(c.focusedAsset(),focal,"End-clamped year cards must not replace the navigation context with the previous year")
    c.dock.selectedSegmentIndex = CalendarGridLevel.all.rawValue; c.levelChosen()
    settle(c)
    XCTAssertTrue(c.grid.indexPathsForVisibleItems.contains { c.layout.geometry.tiles[$0.item].asset > 54000 })
  }
  @MainActor func testLoadingHeaderAdoptsMediaContrastWithoutWaitingForResize() {
    let c = CalendarGridController(); c.loadViewIfNeeded()
    c.view.frame = CGRect(x:0,y:0,width:402,height:874); c.view.layoutIfNeeded()
    c.replaceAssets([CalendarGridAsset(id:"photo",date:nil,aspect:1)])
    XCTAssertEqual(c.titleLabel.textColor,UIColor.white)
    XCTAssertEqual(c.subtitleLabel.textColor,UIColor.white.withAlphaComponent(0.92))
    c.view.layoutIfNeeded()
    XCTAssertEqual(c.subtitleLabel.frame.minX,c.titleLabel.convert(c.titleLabel.bounds,to:c.view).minX,accuracy:0.1)
  }
  func testDensityChangesKeepIdentityAndOriginalAspectDoesNotChangeMembership() {
    let assets = (0..<900).map {
      CalendarGridAsset(id: "asset-\($0)", date: nil, aspect: $0 % 2 == 0 ? 0.7 : 1.8)
    }
    for columns in [1, 3, 5, 15, 31] {
      for aspect in [false, true] {
        let g = CalendarGridGeometry(
          assets: assets, level: .all, width: 390, columns: columns, originalAspect: aspect)
        XCTAssertEqual(g.tiles.map(\.id), assets.map(\.id))
        XCTAssertEqual(g.tiles.map(\.members.lowerBound), Array(assets.indices))
        XCTAssertTrue(g.height > 0)
      }
    }
  }
  func testAnchoredColumnsRetainEveryAssetAndBoundHorizontalTravel() {
    let assets = (0..<1200).map { CalendarGridAsset(id: "asset-\($0)", date: nil, aspect: 1) }
    let anchor = 609
    let width: CGFloat = 402
    let source = CalendarGridGeometry(
      assets: assets, level: .all, width: width, columns: 3, originalAspect: false)
    let point = source.tiles[anchor].frame.midX
    let side = (width - 8) / 5
    let column = Int(round((point - side * 0.5) / (side + 2)))
    let leading = (column - anchor % 5 + 5) % 5
    let destination = CalendarGridGeometry(
      assets: assets, level: .all, width: width, columns: 5, originalAspect: false,
      leadingSlots: leading)
    XCTAssertEqual(destination.tiles.map(\.id), assets.map(\.id))
    XCTAssertLessThanOrEqual(abs(destination.tiles[anchor].frame.midX - point), side * 0.5 + 2)
    XCTAssertNotEqual(
      CalendarGridController.geometryKey(.all, width: width, columns: 5, aspect: false),
      CalendarGridController.geometryKey(
        .all, width: width, columns: 5, aspect: false, leading: leading))
  }
  @MainActor func testSelectionMarksOnlySelectedMediaAndKeepsZeroPromptCompact() {
    let cell = CalendarGridCell(frame: CGRect(x: 0, y: 0, width: 130, height: 130))
    cell.selection(false, enabled: true)
    XCTAssertTrue(cell.check.isHidden)
    cell.selection(true, enabled: true)
    XCTAssertFalse(cell.check.isHidden)
    cell.selection(true, enabled: false)
    XCTAssertTrue(cell.check.isHidden)
    let controls = CalendarSelectionControls(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
    controls.countButton.setTitle("Select Items", for: .normal)
    controls.layoutIfNeeded()
    XCTAssertLessThan(controls.countButton.frame.width, 300)
    XCTAssertEqual(controls.countButton.frame.midX, 201)
  }
  /// The live stage settles on a display link; tests finish it directly.
  @MainActor private func finishStage(_ c: CalendarGridController, cancelled: Bool = false) {
    c.finishStage(cancelled: cancelled)
    if c.stage != nil { c.completeStage() }
  }
  @MainActor private func controller(_ count: Int, image: UIImage? = nil) -> CalendarGridController {
    let c = CalendarGridController()
    c.assets = (0..<count).map { CalendarGridAsset(id: "photo-\($0)", date: nil, aspect: 1) }
    if let image { c.requestImage = { _, _, done in done(image, false); return {} } }
    c.loadViewIfNeeded()
    c.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    c.view.setNeedsLayout()
    c.view.layoutIfNeeded()
    return c
  }
  @MainActor func testStageReleaseAdoptsCollectionOnlyAfterSettle() throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let c = controller(300, image: image)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    c.updateStage(distance: 200)
    let stage = try XCTUnwrap(c.stage)
    XCTAssertEqual(stage.shownColumns, 5, "A third of the way toward five columns previews them")
    XCTAssertEqual(c.columns, 3, "The collection keeps its density while fingers are down")
    c.finishStage(cancelled: false)
    XCTAssertEqual(c.columns, 3, "The collection is adopted when the settle ends")
    c.completeStage()
    XCTAssertEqual(c.columns, 5)
    XCTAssertNil(c.stage)
    XCTAssertTrue(c.grid.panGestureRecognizer.isEnabled)
    XCTAssertTrue(c.grid.visibleCells.allSatisfy { ($0 as? CalendarGridCell)?.image.image === image })
  }
  @MainActor func testStageKeepsFocalPhotoInMidLibrary() throws {
    for (distance, expected) in [(CGFloat(420), 1), (CGFloat(240), 5)] {
      let c = controller(10000)
      c.place(c.clampedOffset(60000))
      let point = CGPoint(x: 201, y: c.grid.contentOffset.y + 400)
      c.beginStage(point: point, item: nil, distance: 300)
      let photo = c.pinchTrack.asset
      c.updateStage(distance: distance)
      finishStage(c)
      XCTAssertEqual(c.columns, expected)
      let tile = try XCTUnwrap(c.layout.geometry.tiles.firstIndex { $0.asset == photo })
      let f = c.layout.frame(tile)
      XCTAssertEqual(f.minY + f.height * c.anchorFraction.y - c.grid.contentOffset.y, 400, accuracy: 1)
      XCTAssertGreaterThan(c.grid.contentOffset.y, 10000, "Release never scrolls toward the oldest edge")
    }
  }
  @MainActor func testShortPinchInsideDeadZoneStepsOneStopLikeAButton() {
    let c = controller(1000)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    c.updateStage(distance: 288)
    XCTAssertEqual(c.stage?.pitch, c.stopPitch(3), "The dead zone shows no scale")
    finishStage(c)
    XCTAssertEqual(c.columns, 5)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    c.updateStage(distance: 302)
    finishStage(c)
    XCTAssertEqual(c.columns, 5, "Incidental finger movement does not change density")
  }

  @MainActor func testSnapshotPaintsResolvedImagesBeforeHiddenLayersCommit() throws {
    let c = CalendarGridController()
    c.assets = (0..<100).map { CalendarGridAsset(id:"asset-\($0)",date:nil,aspect:1) }
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let green = UIGraphicsImageRenderer(size:CGSize(width:64,height:64),format:format).image { ctx in
      UIColor.green.setFill(); ctx.fill(CGRect(x:0,y:0,width:64,height:64))
    }
    c.requestImage = { _,_,done in done(green,false); return {} }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x:0,y:0,width:402,height:874)
    c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    for case let cell as CalendarGridCell in c.grid.visibleCells {
      cell.image.layer.contents = nil
      XCTAssertNotNil(cell.image.image)
    }
    let image = c.sceneImage().cgImage!, bytes = image.dataProvider!.data! as Data
    let offset = image.height/2*image.bytesPerRow+image.width/2*4
    XCTAssertGreaterThan(bytes[offset+1],240,"Snapshot pixels do not depend on a hidden view's pending layer display")
    XCTAssertLessThan(bytes[offset],15)
    c.stopMotion()
  }

  func testMonthMosaicsCoverOneThroughSixAndMirrorWithoutOverlap() {
    let calendar = Calendar(identifier: .gregorian)
    for month in [1, 2] {
      for count in 1...31 {
        let assets = (1...count).map { day in
          CalendarGridAsset(
            id: "day-\(day)",
            date: calendar.date(from: DateComponents(year: 2026, month: month, day: day)), aspect: 1
          )
        }
        let g = CalendarGridGeometry(
          assets: assets, level: .months, width: 402, columns: 3, originalAspect: false)
        XCTAssertEqual(g.tiles.flatMap { Array($0.members) }.sorted(), Array(assets.indices))
        for (i, tile) in g.tiles.enumerated() {
          XCTAssertGreaterThanOrEqual(tile.frame.minX, 19.999)
          XCTAssertLessThanOrEqual(tile.frame.maxX, 382.1)
          for other in g.tiles.dropFirst(i + 1) {
            XCTAssertFalse(tile.frame.intersects(other.frame))
          }
        }
        if count == 2 {
          XCTAssertEqual(g.tiles[0].frame.height / g.tiles[0].frame.width, 4.0 / 3, accuracy: 0.01)
        }
        if count == 3 {
          let hero = g.tiles.max { $0.frame.width < $1.frame.width }!
          XCTAssertEqual(hero.asset, month == 1 ? 0 : 2)
        }
      }
    }
  }
  @MainActor func testDensePeriodCaptionsAvoidOverlapAtShortBoundaries() {
    let assets = (0..<100).map { i in
      CalendarGridAsset(
        id: "year-\(i)",
        date: Calendar.current.date(from: DateComponents(year: 2000 + i / 5, month: 1, day: 1)),
        aspect: 1)
    }
    let layout = CalendarGridLayout()
    layout.geometry = CalendarGridGeometry(
      assets: assets, level: .all, width: 402, columns: 31, originalAspect: false)
    let grid = UICollectionView(
      frame: CGRect(x: 0, y: 0, width: 402, height: 874), collectionViewLayout: layout)
    _ = grid
    let captions = layout.visibleHeadings(in: CGRect(x: 0, y: 0, width: 402, height: 874))
      .compactMap { layout.heading($0)?.frame }
    for i in 1..<captions.count {
      XCTAssertGreaterThanOrEqual(captions[i].minY, captions[i - 1].maxY + 10)
    }
    XCTAssertLessThan(captions.count, layout.geometry.headings.count)
  }
  @MainActor func testHeldPinchCrossesSeveralStopsAndReversesAroundOneAsset() throws {
    let c = controller(500)
    let offset = c.grid.contentOffset
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    let photo = c.pinchTrack.asset
    c.updateStage(distance: 30)
    let stage = try XCTUnwrap(c.stage)
    XCTAssertEqual(stage.shownColumns, c.columnStops.last)
    XCTAssertEqual(c.pinchTrack.asset, photo)
    c.updateStage(distance: 261)
    XCTAssertEqual(stage.shownColumns, 3)
    XCTAssertLessThanOrEqual(stage.faces.count, 5)
    finishStage(c, cancelled: true)
    XCTAssertEqual(c.columns, 3)
    XCTAssertEqual(c.grid.contentOffset, offset)
    XCTAssertNil(c.stage)
    XCTAssertEqual(c.columnStops.last, 31, "The year overview is the terminal zoom level")
  }
  @MainActor func testStageReleasePreservesPreviewIncludingFartherStops() {
    let c = controller(500)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    c.updateStage(distance: 240)
    finishStage(c)
    XCTAssertEqual(c.columns, 5, "Visible progress commits the adjacent stop")
    let d = controller(500)
    d.beginStage(point: CGPoint(x: 201, y: d.grid.contentOffset.y + 437), item: nil, distance: 300)
    d.updateStage(distance: 110)
    XCTAssertEqual(d.stage?.shownColumns, 15)
    finishStage(d)
    XCTAssertEqual(d.columns, 15, "Release keeps the preview even when five is nearer in size")
  }

  @MainActor func testHeldPreviewReversesWithoutReturningToSourceSize() throws {
    let c = controller(10000)
    c.density(columns: 5, at: 5000); c.completeStage()
    c.place(c.clampedOffset(20000))
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    c.updateStage(distance: 339 * 1.45)
    let stage = try XCTUnwrap(c.stage)
    XCTAssertEqual(stage.shownColumns, 3)
    c.updateStage(distance: 339 * 1.42)
    XCTAssertEqual(stage.shownColumns, 5, "A small reversal changes photos while tiles remain enlarged")
    XCTAssertEqual(c.pinchTrack.headerColumns, 3, "The date density remains independent of the mixture")
    XCTAssertGreaterThan(stage.pitch, c.stopPitch(5) * 1.4)
    finishStage(c)
    XCTAssertEqual(c.columns, 5, "Release follows the reversed preview rather than nearest size")
  }

  @MainActor func testHeldOverviewReversesAndReturnsWithoutLifting() throws {
    let c = controller(10000)
    c.density(columns: 5, at: 5000); c.completeStage()
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    c.updateStage(distance: 261 * 0.82)
    let stage = try XCTUnwrap(c.stage)
    let photo = c.pinchTrack.asset
    XCTAssertEqual(stage.shownColumns, 15)
    c.updateStage(distance: 261 * 0.84)
    XCTAssertEqual(stage.shownColumns, 5)
    c.updateStage(distance: 261 * 0.82)
    XCTAssertEqual(stage.shownColumns, 15)
    XCTAssertEqual(c.pinchTrack.asset, photo)
    finishStage(c)
    XCTAssertEqual(c.columns, 15)
  }

  @MainActor func testNewestBoundaryIsConstrainedBeforeRelease() throws {
    let c = controller(10000)
    let offset = c.grid.contentOffset
    c.beginStage(point: CGPoint(x: 201, y: offset.y + 400), item: nil, distance: 300)
    c.updateStage(distance: 220)
    let stage = try XCTUnwrap(c.stage)
    let bottom = stage.bounds.height - c.gridInsets(showsInterval: true).bottom
    XCTAssertEqual(stage.focus.y + c.pinchTrack.boundaryDistance * stage.pitch, bottom, accuracy: 0.5)
    XCTAssertGreaterThan(stage.focus.y, c.pinchTrack.startFocus.y)
    XCTAssertEqual(c.grid.contentOffset, offset, "Held motion belongs to the live stage")
    finishStage(c, cancelled: true)
    XCTAssertEqual(c.grid.contentOffset, offset, "Cancellation restores the original scroll offset")
  }

  @MainActor func testPartialFadeReversalPreservesCompositeAndContinuesDuringHold() throws {
    let c = controller(300)
    let stage = CalendarZoomStage(frame: c.grid.frame, columns: 5, pitch: c.stopPitch(5),
      focus: CGPoint(x: 201, y: 400), displayScale: 1)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
      UIColor.systemYellow.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    }
    stage.configureTile = { layer, _, _ in layer.contents = image.cgImage; return nil }
    for count in [5, 3] {
      stage.addFace(columns: count, geometry: c.allGeometry(count), focus: .zero,
        pitch: c.stopPitch(count), opacity: count == 5 ? 1 : 0)
    }
    stage.show(3, animated: true, at: 10)
    stage.advance(to: 10.6)
    let face = try XCTUnwrap(stage.faces[3])
    let weight = face.opacity, alpha = face.container.opacity
    XCTAssertGreaterThan(weight, 0.1); XCTAssertLessThan(weight, 0.9)
    stage.show(5, animated: true, at: 10.6)
    XCTAssertEqual(face.opacity, weight, accuracy: 0.0001)
    XCTAssertEqual(face.container.opacity, alpha, accuracy: 0.0001, "Reversal never reorders the blended layers")
    let pitch = stage.pitch
    stage.advance(to: 10.9)
    XCTAssertLessThan(face.opacity, weight, "The fade continues with no new finger input")
    XCTAssertEqual(stage.pitch, pitch)
    XCTAssertEqual(stage.faces.values.reduce(0) { $0 + $1.opacity }, 1, accuracy: 0.0001)
    stage.stop()
  }

  @MainActor func testSelectionKeepsHierarchyAndPinchInputOwnership() {
    let c = CalendarGridController(); c.assets = (0..<60).map { CalendarGridAsset(id: "photo-\($0)",date: nil,aspect: 1) }
    c.loadViewIfNeeded(); c.view.frame = CGRect(x: 0,y: 0,width: 402,height: 874); c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    c.level = .months; c.toggleSelection()
    XCTAssertEqual(c.level,.months); XCTAssertTrue(c.selecting)
    c.level = .all; c.columns = 31; c.toggleSelection(); c.toggleSelection()
    XCTAssertEqual(c.columns,31); XCTAssertTrue(c.selecting)
    XCTAssertTrue(c.gestureRecognizerShouldBegin(UIPinchGestureRecognizer()))
    c.density(columns: 5,at: 30); if c.stage != nil { c.completeStage() }
    XCTAssertEqual(c.columns,5); XCTAssertTrue(c.selecting)
  }

  @MainActor func testScaledFaceFillsBothSidesWithChronologicalNeighbors() throws {
    let c = controller(10000)
    c.place(40000)
    c.beginStage(point: CGPoint(x: 103, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage)
    let face = try XCTUnwrap(stage.faces[3])
    for ratio: CGFloat in [0.65, 0.4] {
      stage.pitch = face.pitch * ratio
      stage.layoutAll()
      let row = try XCTUnwrap(face.tiles.keys.first { key in
        guard let frame = face.tiles[key]?.frame else { return false }
        return frame.minY > 200 && frame.maxY < 700
      }).row
      let tiles = face.tiles.filter { $0.key.row == row }.sorted { $0.value.frame.minX < $1.value.frame.minX }
      XCTAssertLessThanOrEqual(try XCTUnwrap(tiles.first).value.frame.minX, 0)
      XCTAssertGreaterThanOrEqual(try XCTUnwrap(tiles.last).value.frame.maxX, stage.bounds.width)
      for (left, right) in zip(tiles, tiles.dropFirst()) {
        XCTAssertLessThanOrEqual(right.value.frame.minX - left.value.frame.maxX, 2.01)
        let asset = try XCTUnwrap(left.value.photo.name).split(separator: "-").last.flatMap { Int($0) }
        let next = try XCTUnwrap(right.value.photo.name).split(separator: "-").last.flatMap { Int($0) }
        XCTAssertEqual(next, asset.map { $0 + 1 }, "Extended row slots retain chronological identity")
      }
      XCTAssertLessThan(face.tiles.count, 600, "Only the viewport is materialized")
    }
    stage.stop()
  }

  @MainActor func testReleaseKeepsChosenRowPhaseAcrossReversalAndCollectionHandoff() throws {
    let c = controller(10000)
    c.place(40000)
    let point = CGPoint(x: 105, y: c.grid.contentOffset.y + 400)
    c.beginStage(point: point, item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage), asset = c.pinchTrack.asset
    c.updateStage(distance: 261 * 0.62)
    let five = try XCTUnwrap(stage.faces[5])
    let phase = five.geometry.leadingSlots
    XCTAssertNotEqual(phase, 0, "This fixture requires a different row phase")
    XCTAssertLessThanOrEqual(abs(five.focus.x - stage.focus.x), c.stopPitch(5) / 2)
    c.updateStage(distance: 261 * 0.64)
    XCTAssertEqual(stage.shownColumns, 3)
    c.updateStage(distance: 261 * 0.62)
    XCTAssertEqual(stage.shownColumns, 5)
    XCTAssertEqual(stage.faces[5]?.geometry.leadingSlots, phase)
    c.finishStage(cancelled: false)
    let now = CACurrentMediaTime()
    for step in 0...120 { stage.advance(to: now + Double(step) / 60) }
    XCTAssertNil(c.stage)
    XCTAssertEqual(c.leadingSlots, phase)
    let f = try XCTUnwrap(c.layout.geometry.tiles.first { $0.asset == asset }).frame
    XCTAssertLessThanOrEqual(abs(f.minX + f.width * c.pinchTrack.fraction.x - 105), c.stopPitch(5) / 2)
    XCTAssertEqual(f.minY + f.height * c.pinchTrack.fraction.y - c.grid.contentOffset.y, 400, accuracy: 0.25)
  }

  @MainActor func testLiveStageUsesNativeDurationLiveSelectionAndStateBadges() throws {
    let c = controller(1000)
    c.assets = c.assets.map { CalendarGridAsset(id: $0.id, date: nil, aspect: 1, videoDuration: "1:23", live: true) }
    c.grid.reloadData(); c.view.layoutIfNeeded()
    c.selected = Set(c.assets.map(\.id)); c.selecting = true
    c.refreshSelection()
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage), face = try XCTUnwrap(stage.faces[3])
    let tile = try XCTUnwrap(face.tiles.values.first), badges = try XCTUnwrap(tile.decorations)
    let cell = CalendarGridCell(frame: tile.bounds)
    cell.duration.text = "1:23"; cell.liveMark.image = UIImage(systemName: "livephoto")
    cell.selection(true, enabled: true); cell.layoutIfNeeded()
    XCTAssertEqual(badges.duration.text, cell.duration.text)
    XCTAssertFalse(badges.duration.isHidden); XCTAssertFalse(badges.liveMark.isHidden)
    XCTAssertFalse(badges.check.isHidden)
    for (a, b) in [(badges.duration.frame, cell.duration.frame), (badges.liveMark.frame, cell.liveMark.frame)] {
      XCTAssertEqual(a.minX, b.minX, accuracy: 0.001); XCTAssertEqual(a.minY, b.minY, accuracy: 0.001)
      XCTAssertEqual(a.width, b.width, accuracy: 0.001); XCTAssertEqual(a.height, b.height, accuracy: 0.001)
    }
    XCTAssertEqual(tile.photo.opacity, Float(cell.image.alpha))
    c.finishStage(cancelled: true); c.completeStage()
    c.selecting = false; c.photoStates = Dictionary(uniqueKeysWithValues: c.assets.map { ($0.id, "received") })
    c.grid.reloadData(); c.grid.layoutIfNeeded()
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    let status = try XCTUnwrap(c.stage?.faces[3]?.tiles.values.first?.decorations)
    XCTAssertFalse(status.stateMark.isHidden); XCTAssertNotNil(status.stateMark.image)
    c.stage?.stop()
  }

  @MainActor func testHeldOverviewFadeDoesNotMoveFocusToFillTargetBottom() throws {
    let c = controller(10000)
    c.density(columns: 5, at: 9999); c.completeStage()
    c.place(.greatestFiniteMagnitude)
    c.beginStage(point: CGPoint(x: 105, y: c.grid.contentOffset.y + 500), item: nil, distance: 300)
    c.updateStage(distance: 210)
    let stage = try XCTUnwrap(c.stage)
    XCTAssertEqual(stage.shownColumns, 15)
    let heldFocus = stage.focus
    stage.advance(to: CACurrentMediaTime() + 2)
    XCTAssertEqual(stage.focus, heldFocus, "A held photo crossfade cannot reposition the anchor to fill the incoming face's bottom")
    let face = try XCTUnwrap(stage.faces[15])
    let renderedBottom = stage.focus.y + (face.geometry.height - face.focus.y) * stage.pitch / face.pitch
    let bottom = stage.bounds.height - c.gridInsets(showsInterval: true).bottom
    XCTAssertLessThan(renderedBottom, bottom - 20, "The incoming overview may end above the bottom while fingers are held")
    c.finishStage(cancelled: false)
    let now = CACurrentMediaTime()
    for step in 0...120 { stage.advance(to: now + Double(step) / 60) }
    XCTAssertNil(c.stage)
    XCTAssertEqual(c.grid.contentOffset.y, c.clampedOffset(.greatestFiniteMagnitude), accuracy: 0.5)
  }

  @MainActor func testAdoptionRetainsPresentedPixelsAfterEvictionAndRejectsLateFallback() throws {
    func image(_ edge: CGFloat) -> UIImage {
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      return UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format).image { ctx in
        UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
      }
    }
    let sharp = image(512), small = image(64), fallback = image(40)
    for columns in [5, 15] {
      let c = controller(1000)
      c.requestImage = { _, pixels, done in done(pixels <= 128 ? small : sharp, false); return {} }
      c.place(10000)
      c.density(columns: columns, at: 500)
      let stage = try XCTUnwrap(c.stage), face = try XCTUnwrap(stage.faces[columns])
      stage.show(columns, animated: false)
      stage.pitch = face.pitch
      stage.focus = CGPoint(x: face.focus.x, y: face.focus.y - c.pinchTrack.finalOffset)
      stage.layoutAll()
      let shown = stage.presentations(columns)
      XCTAssertFalse(shown.isEmpty)
      c.transitionImages.removeAllObjects(); c.transitionSmallImages.removeAllObjects()
      var callbacks: [(UIImage?, Bool) -> Void] = []
      c.requestImage = { _, _, done in callbacks.append(done); done(fallback, false); return {} }
      c.completeStage()
      XCTAssertNil(c.stage)
      if columns >= 10 {
        // Dense overviews draw strips from the adopted pixels instead of cells.
        XCTAssertTrue(c.grid.visibleCells.isEmpty)
        XCTAssertFalse(c.denseCanvas.isHidden)
        XCTAssertGreaterThan(c.denseCanvas.layer.sublayers?.count ?? 0, 0)
      } else {
        var compared = 0
        for case let cell as CalendarGridCell in c.grid.visibleCells {
          guard let expected = shown[cell.assetID]?.image else { continue }
          XCTAssertTrue(cell.image.image === expected,
            "The exact displayed image must survive cache eviction and synchronous fallbacks")
          compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
      }
      callbacks.forEach { $0(nil, true); $0(fallback, false) }
      for case let cell as CalendarGridCell in c.grid.visibleCells {
        guard let expected = shown[cell.assetID]?.image else { continue }
        XCTAssertTrue(cell.image.image === expected, "Delayed preview callbacks cannot downgrade adopted pixels")
      }
      XCTAssertTrue(c.adoptingTiles.isEmpty, "Only visible cells retain the handoff pixels")
      c.stopMotion()
      XCTAssertNil(c.adoptionCover)
    }
  }

  @MainActor func testOverviewToOrdinaryGapShowsBackgroundBeforeOutgoingFaceDisappears() throws {
    let c = controller(1000)
    let stage = CalendarZoomStage(frame: c.grid.frame, columns: 15, pitch: c.stopPitch(5),
      focus: CGPoint(x: 201, y: 400), displayScale: 1)
    stage.backgroundColor = .magenta
    let blue = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
      UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    }
    stage.configureTile = { layer, _, _ in layer.contents = blue.cgImage; return nil }
    for count in [15, 5] {
      let g = c.allGeometry(count)
      stage.addFace(columns: count, geometry: g,
        focus: c.stageFocus(g, asset: 500, fraction: CGPoint(x: 0.5, y: 0.5)),
        pitch: c.stopPitch(count), opacity: count == 15 ? 1 : 0)
    }
    stage.show(5, animated: true, at: 10)
    stage.advance(to: 10.8)
    let five = try XCTUnwrap(stage.faces[5]), source = try XCTUnwrap(stage.faces[15])
    XCTAssertGreaterThan(source.opacity, 0)
    XCTAssertLessThan(five.opacity, 1)
    let row = five.tiles.filter { $0.value.frame.midY > 200 && $0.value.frame.midY < 700 }
      .sorted { $0.key.row == $1.key.row ? $0.key.column < $1.key.column : $0.key.row < $1.key.row }
    let left = try XCTUnwrap(row.first { entry in
      let r = entry.value.frame
      return r.minX > 0 && r.maxX < stage.bounds.width - stage.pitch
    })
    let right = try XCTUnwrap(five.tiles[.init(row: left.key.row, column: left.key.column + 1)])
    let point = CGPoint(x: (left.value.frame.maxX + right.frame.minX) / 2, y: left.value.frame.midY)
    XCTAssertGreaterThan(right.frame.minX - left.value.frame.maxX, 1)
    let scale = 4
    let width = Int(stage.bounds.width) * scale, height = Int(stage.bounds.height) * scale
    let bitmap = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    bitmap.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    stage.layer.render(in: bitmap)
    let data = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
    let offset = (Int(point.y * CGFloat(scale)) * width + Int(point.x * CGFloat(scale))) * 4
    XCTAssertGreaterThan(Int(data[offset]), 220, "The gap reveals magenta background even while the old photo face remains opaque")
    XCTAssertLessThan(Int(data[offset + 1]), 40)
    stage.stop()
  }

  @MainActor func testBadgesScaleWithCellAndDoNotToggleAtDisplayedWidthThreshold() throws {
    let c = controller(1000)
    c.view.frame.size.width = 440; c.view.setNeedsLayout(); c.view.layoutIfNeeded()
    let stage = CalendarZoomStage(frame: c.grid.frame, columns: 5, pitch: c.stopPitch(5),
      focus: CGPoint(x: 220, y: 400), displayScale: 3)
    stage.configureDecorations = { badges, _ in
      badges.duration.text = "1:23"; badges.liveMark.image = UIImage(systemName: "livephoto")
    }
    let g = c.allGeometry(5)
    let face = stage.addFace(columns: 5, geometry: g,
      focus: c.stageFocus(g, asset: 500, fraction: CGPoint(x: 0.5, y: 0.5)),
      pitch: c.stopPitch(5), opacity: 1)
    for ratio: CGFloat in [1.5, 0.7] {
      stage.pitch = face.pitch * ratio; stage.layoutAll()
      let tile = try XCTUnwrap(face.tiles.values.first), badges = try XCTUnwrap(tile.decorations)
      let duration = badges.layer.convert(badges.duration.frame, to: tile)
      // Tile edges snap to device pixels, so the scale is exact within a pixel.
      XCTAssertEqual(duration.width, 49 * ratio, accuracy: 0.5)
      XCTAssertEqual(badges.layer.convert(badges.liveMark.frame, to: tile).width, 20 * ratio, accuracy: 0.5)
      XCTAssertFalse(badges.duration.isHidden)
      XCTAssertFalse(badges.liveMark.isHidden)
    }
    stage.stop()
  }

  @MainActor func testCompactExpansionDoesNotScheduleReturnToLatest() async throws {
    let c = controller(1000)
    c.active = true; c.place(6000)
    let offset = c.grid.contentOffset
    c.nativeBarCompact = true
    c.nativeBarMorphed(minimized: false)
    let forwarding = CalendarTabReselection(); forwarding.owner = c
    forwarding.returnToLatest(afterExpanding: true)
    try await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertEqual(c.grid.contentOffset, offset)
    XCTAssertFalse(c.scrollingToLatest)
    forwarding.returnToLatest(afterExpanding: false)
    XCTAssertEqual(c.grid.contentOffset.y, c.clampedOffset(.greatestFiniteMagnitude), accuracy: 0.5,
      "Reselecting the expanded Library tab still returns to newest")
  }

  @MainActor func testPinchEntryRetainsNativePixelsWhenTransitionCachesAreEmpty() throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 320), format: format).image { ctx in
      UIColor.systemGreen.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
    }
    let c = controller(1000, image: image)
    let native = Dictionary(uniqueKeysWithValues: c.grid.visibleCells.compactMap { cell -> (String, UIImage)? in
      guard let cell = cell as? CalendarGridCell, let image = cell.image.image else { return nil }
      return (cell.assetID, image)
    })
    XCTAssertFalse(native.isEmpty)
    c.transitionImages.removeAllObjects(); c.transitionSmallImages.removeAllObjects()
    c.requestImage = { _, _, done in done(nil, false); return {} }
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 400), item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage)
    let shown = stage.presentations(c.columns)
    for (id, image) in native where shown[id] != nil {
      XCTAssertTrue(shown[id]?.image === image, "Entering pinch transfers visible images even when every cache misses")
    }
    XCTAssertTrue(stage.seedTiles.isEmpty, "Face-construction seeds do not accumulate outside visible tile ownership")
    c.stopMotion()
  }


  @MainActor func testDividersFollowShownFaceAndSnapToUniformPixels() throws {
    let c = controller(1000)
    c.beginStage(point: CGPoint(x: 201, y: c.grid.contentOffset.y + 437), item: nil, distance: 300)
    let stage = try XCTUnwrap(c.stage)
    c.updateStage(distance: 240)
    XCTAssertEqual(stage.shownColumns, 5)
    stage.advance(to: CACurrentMediaTime() + 0.05)
    // Mid-crossfade the divider is the shown face's full scaled gap, never a blend.
    XCTAssertEqual(stage.displayedGap, CalendarGridGeometry.gap(columns: 5) * stage.pitch / c.stopPitch(5),
      accuracy: 0.0001)
    for face in stage.faces.values {
      let rows = Dictionary(grouping: face.tiles.values.filter { $0.frame.intersects(stage.bounds) }) {
        Int(($0.frame.minY * stage.displayScale).rounded())
      }
      for row in rows.values {
        let sorted = row.sorted { $0.frame.minX < $1.frame.minX }
        let gaps = zip(sorted, sorted.dropFirst()).map {
          (($1.frame.minX - $0.frame.maxX) * stage.displayScale).rounded()
        }
        XCTAssertLessThanOrEqual(Set(gaps).count, 1, "Every divider in a row has one pixel width")
        for tile in sorted {
          XCTAssertEqual(tile.frame.minX * stage.displayScale, (tile.frame.minX * stage.displayScale).rounded(),
            accuracy: 0.001)
        }
      }
    }
    // Reversing toward the dense overview drops dividers in one step.
    c.updateStage(distance: 120)
    if stage.shownColumns >= 10 { XCTAssertEqual(stage.displayedGap, 0) }
    c.stopMotion()
  }

  @MainActor func testIdenticalLibraryRebuildKeepsPixelsAndPosition() {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let c = controller(5000, image: image)
    c.place(30000)
    let offset = c.grid.contentOffset
    let cached = c.transitionImages.object(forKey: c.assets[c.layout.geometry.tiles[c.grid.indexPathsForVisibleItems[0].item].asset].id as NSString)
    c.replaceAssets(c.assets)
    XCTAssertEqual(c.grid.contentOffset, offset)
    if let cached {
      let id = c.assets[c.layout.geometry.tiles[c.grid.indexPathsForVisibleItems[0].item].asset].id
      XCTAssertTrue(c.transitionImages.object(forKey: id as NSString) === cached)
    }
  }

  @MainActor func testLibraryChangeWaitsForMotionAndKeepsFocalScreenPosition() throws {
    let c = controller(5000)
    c.place(30000)
    let probe = CGPoint(x: 201, y: c.grid.contentOffset.y + 400)
    let path = try XCTUnwrap(c.grid.indexPathForItem(at: probe))
    let id = c.assets[c.layout.geometry.tiles[path.item].asset].id
    c.beginStage(point: probe, item: nil, distance: 300)
    var values = c.assets
    values.insert(CalendarGridAsset(id: "inserted", date: nil, aspect: 1), at: 2500)
    c.replaceAssets(values)
    XCTAssertEqual(c.assets.count, 5000, "A library change never interrupts a running pinch")
    XCTAssertNotNil(c.pendingAssets)
    c.stopMotion()
    let before = c.grid.convert(c.layout.frame(path.item), to: c.view).minY
    c.replaceAssets(values)
    XCTAssertEqual(c.assets.count, 5001)
    let index = try XCTUnwrap(c.assets.firstIndex { $0.id == id })
    let tile = try XCTUnwrap(c.layout.geometry.tiles.firstIndex { $0.members.contains(index) })
    let after = c.grid.convert(c.layout.frame(tile), to: c.view).minY
    XCTAssertEqual(after, before, accuracy: CalendarGridGeometry.pitch(width: c.width, columns: c.columns),
      "The focused photo stays on screen in the same row band")
  }

  @MainActor func testPrependedHistoryKeepsRowComposition() {
    let c = controller(1500)
    let column = { (c: CalendarGridController, id: String) -> CGFloat in
      let i = c.assets.firstIndex { $0.id == id }!
      return c.layout.frame(c.layout.geometry.tiles.firstIndex { $0.members.contains(i) }!).minX
    }
    let ids = c.assets.suffix(20).map(\.id)
    let before = ids.map { column(c, $0) }
    let older = (0..<4001).map { CalendarGridAsset(id: "older-\($0)", date: nil, aspect: 1) }
    c.replaceAssets(older + c.assets)
    XCTAssertEqual(ids.map { column(c, $0) }, before, "Indexing older history keeps newest rows unchanged")
    XCTAssertEqual(c.grid.contentOffset.y, c.clampedOffset(.greatestFiniteMagnitude), accuracy: 0.5)
  }

  @MainActor func testLaunchDensityFollowsLastBrowsingDensity() {
    let c = controller(100)
    c.level = .all; c.columns = 1
    XCTAssertEqual(CalendarGridController.rememberedColumns, 3)
    c.columns = 15
    XCTAssertEqual(CalendarGridController.rememberedColumns, 5)
    c.columns = 3
    XCTAssertEqual(CalendarGridController.rememberedColumns, 3)
    c.level = .years
    XCTAssertEqual(CalendarGridController.rememberedColumns, 5)
    XCTAssertEqual(CalendarGridController().columns, 5)
  }

  @MainActor func testDenseOverviewDrawsCanvasWithoutPerPhotoCells() throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
      UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let c = controller(6000, image: image)
    c.density(columns: 31, at: nil)
    if c.stage != nil { c.completeStage() }
    c.grid.layoutIfNeeded()
    XCTAssertEqual(c.columns, 31)
    XCTAssertTrue(c.grid.visibleCells.isEmpty, "Dense overviews draw strips, not thousands of cells")
    XCTAssertFalse(c.denseCanvas.isHidden)
    XCTAssertGreaterThan(c.denseCanvas.layer.sublayers?.count ?? 0, 0)
    // Hit testing and pinch anchoring work from geometry alone.
    let point = CGPoint(x: 201, y: c.grid.contentOffset.y + 400)
    let item = try XCTUnwrap(c.item(at: point))
    XCTAssertTrue(c.layout.frame(item).contains(point))
    c.beginStage(point: point, item: nil, distance: 300)
    XCTAssertNotNil(c.stage, "A pinch from the dense overview anchors on a photo")
    c.finishStage(cancelled: true); if c.stage != nil { c.completeStage() }
    XCTAssertEqual(c.columns, 31)
    c.select(item: item)
    if c.stage != nil { c.completeStage() }
    XCTAssertEqual(c.columns, 15, "A tap drills into the month overview")
    XCTAssertTrue(c.grid.visibleCells.isEmpty)
    c.density(columns: 5, at: item)
    if c.stage != nil { c.completeStage() }
    XCTAssertTrue(c.denseCanvas.isHidden)
    XCTAssertFalse(c.grid.visibleCells.isEmpty)
  }

  @MainActor func testZoomMenuStaysOpenAndChainsFromSettlingDensity() throws {
    let c = controller(1000)
    let options = try XCTUnwrap(c.displayMenu().children.compactMap { $0 as? UIMenu }.last)
    let actions = options.children.compactMap { $0 as? UIAction }
    XCTAssertEqual(actions.count, 2)
    XCTAssertTrue(actions.allSatisfy { $0.attributes.contains(.keepsMenuPresented) })
    c.stepDensity(by: 1)
    XCTAssertEqual(c.pinchTrack.target.map { c.columnStops[$0] }, 5)
    c.stepDensity(by: 1)
    XCTAssertEqual(c.pinchTrack.target.map { c.columnStops[$0] }, 15,
      "A repeated tap steps from the density being settled toward")
    if c.stage != nil { c.completeStage() }
    XCTAssertEqual(c.columns, 15)
  }

  @MainActor func testCoverLevelPinchTriggersOneLevelChangeWithoutFollowingFingers() {
    let c = controller(3000)
    c.changeLevel(.years, asset: 2000, from: nil); c.stopMotion()
    let pinch = UIPinchGestureRecognizer()
    pinch.scale = 1.03
    c.triggerCoverPinch(pinch)
    XCTAssertEqual(c.level, .years, "A pinch below the threshold does nothing")
    pinch.scale = 1.2
    c.triggerCoverPinch(pinch)
    XCTAssertEqual(c.level, .months, "Pinching out of Years opens Months once")
    c.stopMotion()
    pinch.scale = 2
    c.triggerCoverPinch(pinch)
    XCTAssertEqual(c.level, .months, "One gesture triggers at most one change")
    c.coverPinchTriggered = false
    pinch.scale = 0.8
    c.triggerCoverPinch(pinch)
    XCTAssertEqual(c.level, .years)
    c.stopMotion()
  }

  @MainActor func testLaunchSnapshotRoundTripsForTheSameLayout() throws {
    try XCTSkipUnless(CalendarGridController.usesLaunchSnapshot, "The launch cover is disabled")
    CalendarGridController.clearLaunchSnapshot()
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
      UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    let c = controller(500, image: image)
    let window = UIWindow(frame: c.view.frame); window.rootViewController = c; window.isHidden = false
    c.view.frame = window.bounds; c.view.layoutIfNeeded()
    c.saveLaunchSnapshot()
    let deadline = Date().addingTimeInterval(2)
    while !FileManager.default.fileExists(atPath: CalendarGridController.launchSnapshotInfoURL.path),
      Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: CalendarGridController.launchSnapshotURL.path))
    let next = CalendarGridController()
    next.loadViewIfNeeded()
    XCTAssertNotNil(next.launchCover, "The next launch shows the snapshot in its first frame")
    next.view.frame = c.view.frame; next.view.setNeedsLayout(); next.view.layoutIfNeeded()
    XCTAssertEqual(next.launchCover?.frame, next.view.bounds)
    next.removeLaunchCover(animated: false)
    XCTAssertNil(next.launchCover)
    CalendarGridController.clearLaunchSnapshot()
    let none = CalendarGridController(); none.loadViewIfNeeded()
    XCTAssertNil(none.launchCover)
    window.isHidden = true
  }
}

@MainActor private final class MediaStripTestSource: NSObject, UICollectionViewDataSource {
  func collectionView(_ view: UICollectionView, numberOfItemsInSection section: Int) -> Int { 55000 }
  func collectionView(_ view: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
    view.dequeueReusableCell(withReuseIdentifier: "tile",for: path)
  }
}

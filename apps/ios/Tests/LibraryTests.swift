import Photos
import ImageIO
import SwiftUI
import UIKit
import XCTest

@testable import BackupDuck

/// Run only on a disposable simulator; fixtures remain available for UI checks.
@MainActor final class LibraryTests: XCTestCase {
  func testLongLensMetadataRendersInNarrowAndAccessibleInformationPanels() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("Synthetic metadata fixture only")
    #endif
    let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 320,height: 480)).image { context in
      UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0,y: 0,width: 320,height: 480))
    }
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes,"public.jpeg" as CFString,1,nil))
    let lens = "iPhone 5s back camera 4.15mm f/2.2 - full synthetic lens description"
    CGImageDestinationAddImage(destination,try XCTUnwrap(bitmap.cgImage),[
      kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone 5s"],
      kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: lens]
    ] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    var identifier: String?
    try await PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions(); options.originalFilename = "lens-fixture.jpg"
      request.addResource(with: .photo,data: bytes as Data,options: options)
      identifier = request.placeholderForCreatedAsset?.localIdentifier
    }
    let asset = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [try XCTUnwrap(identifier)],options: nil).firstObject)
    let model = MediaPreviewModel(asset: asset)
    model.loadMetadata()
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
      model.metadata.contains { $0.0 == "preview_lens" && $0.1.hasSuffix("full synthetic lens description") }
    },object: nil)
    await fulfillment(of: [ready],timeout: 5)
    for width: CGFloat in [320,440] {
      let root = VStack(alignment: .leading) {
        PhotoMetadataPanel(preview: model).padding(20)
        Spacer(minLength: 0)
      }.frame(width: width,height: 1400,alignment: .topLeading)
        .background(Color(DuckRole.background))
        .environment(\.dynamicTypeSize,width == 320 ? .large : .accessibility3).environment(\.colorScheme,.dark)
      let renderer = ImageRenderer(content: root); renderer.scale = 2
      _ = renderer.uiImage
      let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
        !model.metadataLoading && model.metadata.contains { $0.0 == "preview_lens" && $0.1 == lens }
      },object: nil)
      await fulfillment(of: [rendered],timeout: 5)
      let image = try XCTUnwrap(renderer.uiImage)
      let attachment = XCTAttachment(image: image); attachment.name = "Full lens information — \(Int(width)) pt"; attachment.lifetime = .keepAlways; add(attachment)
    }
    model.cancelMetadata()
  }

  func testVisibleGridFindsTinyLocalPhotoBeforeBoundedAutomaticCloudUpgrade() async throws {
    func check(cancelled: Bool) async throws {
      let fetch = PHAsset.fetchAssets(with: .image,options: photoLibraryFetchOptions())
      let asset = try XCTUnwrap(fetch.firstObject)
      let manager = ControlledThumbnailManager(), pipeline = ThumbnailPipeline(manager: manager)
      pipeline.disk = nil
      let local = expectation(description: "Large local request")
      let tiny = expectation(description: "Tiny local fallback request")
      let cloud = expectation(description: "Automatic cloud upgrade")
      manager.onStart = { _,id in
        if manager.network[id] == true { cloud.fulfill() }
        else if manager.targets[id]?.width == 64 { tiny.fulfill() }
        else { local.fulfill() }
      }
      let visible = expectation(description: "The grid receives its available local cover")
      let upgraded = expectation(description: "The grid upgrades to its requested tier")
      pipeline.request(asset,pixels: 320) { image,_ in
        guard let image else { return }
        if max(image.size.width,image.size.height)*image.scale <= 64 { visible.fulfill() }
        else { upgraded.fulfill() }
      }
      await fulfillment(of: [local],timeout: 3)
      manager.handlers[manager.started[0].1]?(nil,[cancelled ? PHImageCancelledKey : PHImageResultIsInCloudKey: true])
      await fulfillment(of: [tiny],timeout: 3)
      manager.handlers[manager.started[0].1]?(nil,[PHImageCancelledKey: true])
      let small = UIGraphicsImageRenderer(size: CGSize(width: 64,height: 64)).image { _ in }
      manager.complete(manager.started[1].1,image: small,degraded: true)
      await fulfillment(of: [visible,cloud],timeout: 3)
      XCTAssertEqual(manager.targets[manager.started[2].1]?.width,320)
      let full = UIGraphicsImageRenderer(size: CGSize(width: 320,height: 320)).image { _ in }
      manager.complete(manager.started[2].1,image: full,degraded: false)
      await fulfillment(of: [upgraded],timeout: 3)
      var cached: UIImage?
      pipeline.request(asset,pixels: 320) { image,_ in cached = image }
      XCTAssertGreaterThan((cached?.size.width ?? 0)*(cached?.scale ?? 1),64,"Tiny fallback must never occupy the large rendition's cache key")
      pipeline.clear()

    }
    try await check(cancelled: false)
    try await check(cancelled: true)
  }

  func testDetailLoadingDoesNotDowngradeDisplayedSourcePoster() async throws {
    let assets = PHAsset.fetchAssets(with: .image,options: photoLibraryFetchOptions())
    guard let asset = assets.firstObject else { throw XCTSkip("Import synthetic photo fixtures") }
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    func bitmap(_ edge: CGFloat) -> UIImage { UIGraphicsImageRenderer(size: CGSize(width: edge*0.75,height: edge),format: format).image { _ in } }
    let source = bitmap(1024), degraded = bitmap(128), full = bitmap(2400)
    let manager = ControlledThumbnailManager()
    let model = MediaPreviewModel(asset: asset,poster: source,manager: manager)
    var delivered: [UIImage] = []
    let observation = model.$image.sink { if let value = $0 { delivered.append(value) } }
    defer { observation.cancel(); model.cancel() }
    model.load(promptForCloud: false)
    let id = try XCTUnwrap(manager.started.first?.1)
    manager.complete(id,image: degraded,degraded: true)
    manager.complete(id,image: full,degraded: false)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in model.image === full },object: nil)
    await fulfillment(of: [ready],timeout: 3)
    XCTAssertFalse(delivered.contains { $0 === degraded },"The opening animation must retain the sharper source poster")
    XCTAssertTrue(model.image === full)
  }

  func testSelectedPreviewSessionKeepsBatchOrderAndLibraryContext() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("Synthetic PhotoKit fixture only")
    #endif
    let library = PhotoLibraryModel(); await library.open()
    let fetch = PHAsset.fetchAssets(with: .image,options: photoLibraryFetchOptions())
    guard fetch.count > 9 else { throw XCTSkip("Import synthetic photo fixtures first") }
    let batch = [1,4,9].map { fetch.object(at: $0) }
    library.selection = Set(batch.map(\.localIdentifier))
    let total = library.total, loaded = library.loaded, selected = library.selection, filter = library.filter
    let session = MediaPreviewSession(asset: batch[1],library: library,reviewAssets: batch)
    XCTAssertEqual(session.count,3)
    XCTAssertEqual(session.index(of: batch[1]),1)
    XCTAssertEqual(session.adjacent(to: batch[1],direction: -1)?.localIdentifier,batch[0].localIdentifier)
    XCTAssertEqual(session.adjacent(to: batch[1],direction: 1)?.localIdentifier,batch[2].localIdentifier)
    XCTAssertNil(session.adjacent(to: batch[0],direction: -1))
    XCTAssertNil(session.adjacent(to: batch[2],direction: 1))
    XCTAssertNil(session.index(of: fetch.object(at: 2)))
    library.selection.remove(batch[1].localIdentifier)
    XCTAssertEqual(session.asset(at: 1)?.localIdentifier,batch[1].localIdentifier,"Selection editing must not shift the current page")
    XCTAssertEqual(library.total,total); XCTAssertEqual(library.loaded,loaded); XCTAssertEqual(library.filter,filter)
    XCTAssertEqual(library.selection,selected.subtracting([batch[1].localIdentifier]))
    session.stop()
  }

  func testThumbnailDiskCacheKeepsTiersAndRevisionsAndClearRejectsLateWrites() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "thumbnail-tests-"+UUID().uuidString
    let defaults = UserDefaults(suiteName:suite)!
    defer { try? FileManager.default.removeItem(at:directory); defaults.removePersistentDomain(forName:suite) }
    let disk = ThumbnailDiskCache(directory:directory,defaults:defaults)
    let image = UIGraphicsImageRenderer(size:CGSize(width:64,height:64)).image { ctx in
      UIColor.green.setFill(); ctx.fill(CGRect(x:0,y:0,width:64,height:64))
    }
    let (_,generation) = await disk.read("asset|revision1|64|fill")
    await disk.store(image,key:"asset|revision1|64|fill",generation:generation)
    let reopened = ThumbnailDiskCache(directory:directory,defaults:defaults)
    let (cached,_) = await reopened.read("asset|revision1|64|fill")
    XCTAssertNotNil(cached,"Cached renditions survive a pipeline restart")
    let (larger,_) = await reopened.read("asset|revision1|320|fill")
    let (edited,_) = await reopened.read("asset|revision2|64|fill")
    XCTAssertNil(larger); XCTAssertNil(edited)
    let used = await disk.usage(); XCTAssertGreaterThan(used,0)
    await disk.removeAll()
    await disk.store(image,key:"asset|revision1|64|fill",generation:generation)
    let (cleared,_) = await disk.read("asset|revision1|64|fill")
    XCTAssertNil(cleared,"A completion from before clearing cannot restore the cleared pixels")
    let empty = await disk.usage(); XCTAssertEqual(empty,0)
  }
  func testSharedThumbnailRequestKeepsRemainingSubscriberAfterCancellation() async throws {
    let fetch = PHAsset.fetchAssets(with:.image,options:photoLibraryFetchOptions())
    guard fetch.count > 0 else { throw XCTSkip("Import synthetic fixtures first") }
    let manager = FastDegradedImageManager(),pipeline = ThumbnailPipeline(manager:manager)
    pipeline.disk = nil
    let received = expectation(description:"Remaining subscriber receives the shared result")
    var cancelledCallbacks = 0
    let first = pipeline.request(fetch.object(at:0),pixels:64) { _,_ in cancelledCallbacks += 1 }
    let second = pipeline.request(fetch.object(at:0),pixels:64) { image,_ in if image != nil { received.fulfill() } }
    XCTAssertNotEqual(first,second)
    pipeline.cancel(first)
    await fulfillment(of:[received],timeout:5)
    XCTAssertEqual(manager.started,1); XCTAssertEqual(cancelledCallbacks,0)
    pipeline.clear()
  }
  func testDiskWriteBurstRetainsEveryRenditionAndClearInvalidatesWaiters() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let disk = ThumbnailDiskCache(directory:directory)
    let image = UIGraphicsImageRenderer(size:CGSize(width:64,height:64)).image { _ in }
    let (_,generation) = await disk.read("missing")
    await withTaskGroup(of:Void.self) { group in
      for i in 0..<120 { group.addTask { await disk.store(image,key:"burst-\(i)",generation:generation) } }
    }
    for i in 0..<120 {
      let (cached,_) = await disk.read("burst-\(i)"); XCTAssertNotNil(cached)
    }
    await withTaskGroup(of:Void.self) { group in
      for i in 0..<120 { group.addTask { await disk.store(image,key:"late-\(i)",generation:generation) } }
      await disk.removeAll()
    }
    let empty = await disk.usage(); XCTAssertEqual(empty,0)
  }
  func testFastDegradedResultsReleaseEverySlotAndCacheTheirSizeTier() async throws {
    let fetch = PHAsset.fetchAssets(with: .image,options: photoLibraryFetchOptions())
    guard fetch.count >= 60 else { throw XCTSkip("Import synthetic fixtures first") }
    let manager = FastDegradedImageManager(), pipeline = ThumbnailPipeline(manager: manager)
    pipeline.disk = nil
    let completed = expectation(description: "All fast results complete beyond the concurrency limit")
    completed.expectedFulfillmentCount = 60
    for i in 0..<60 {
      pipeline.request(fetch.object(at: i),pixels: 64) { image,_ in
        if image != nil { completed.fulfill() }
      }
    }
    await fulfillment(of: [completed],timeout: 5)
    XCTAssertEqual(manager.started,60)
    var cached: UIImage?
    let repeatRequest = pipeline.request(fetch.object(at: 0),pixels: 64) { image,_ in cached = image }
    XCTAssertEqual(repeatRequest,PHInvalidImageRequestID)
    XCTAssertNotNil(cached)
    XCTAssertEqual(manager.started,60,"A fast degraded image is final for its small size tier")
    pipeline.clear()
  }

  func testVisibleThumbnailOvertakesHeldPrefetchRequests() async throws {
    let fetch = PHAsset.fetchAssets(with: .image, options: photoLibraryFetchOptions())
    guard fetch.count >= 61 else { throw XCTSkip("Synthetic Photos fixtures required") }
    let manager = ControlledThumbnailManager(), pipeline = ThumbnailPipeline(manager: manager)
    pipeline.disk = nil
    let primed = expectation(description: "Four speculative native requests start")
    primed.expectedFulfillmentCount = 4
    manager.onStart = { _,_ in primed.fulfill() }
    for i in 0..<60 { pipeline.request(fetch.object(at: i), pixels: 320, priority: .prefetch) { _,_ in } }
    await fulfillment(of: [primed], timeout: 5)
    XCTAssertEqual(manager.started.count, 4, "Speculation leaves capacity for the viewport")
    let visible = fetch.object(at: 60), started = expectation(description: "Visible request starts before background completion")
    manager.onStart = { asset,_ in if asset.localIdentifier == visible.localIdentifier { started.fulfill() } }
    pipeline.request(visible, pixels: 320) { _,_ in }
    await fulfillment(of: [started], timeout: 5)
    XCTAssertEqual(manager.started.last?.0, visible.localIdentifier)
    XCTAssertEqual(manager.started.count, 5)
    pipeline.clear()
  }

  func testVisibleSubscriberPromotesQueuedPrefetchAndSurvivesItsCancellation() async throws {
    let fetch = PHAsset.fetchAssets(with: .image, options: photoLibraryFetchOptions())
    guard fetch.count >= 60 else { throw XCTSkip("Synthetic Photos fixtures required") }
    let manager = ControlledThumbnailManager(), pipeline = ThumbnailPipeline(manager: manager)
    pipeline.disk = nil
    // Small mosaic renditions allow wider speculation; asset 50 stays queued.
    let primed = expectation(description: "Speculative native requests start"); primed.expectedFulfillmentCount = 24
    manager.onStart = { _,_ in primed.fulfill() }
    var tickets: [PHImageRequestID] = [], cancelledCallbacks = 0
    for i in 0..<60 {
      tickets.append(pipeline.request(fetch.object(at: i), pixels: 64, priority: .prefetch) { _,_ in
        if i == 50 { cancelledCallbacks += 1 }
      })
    }
    await fulfillment(of: [primed], timeout: 5)
    let asset = fetch.object(at: 50), started = expectation(description: "Shared queued owner is promoted")
    manager.onStart = { photo,_ in if photo.localIdentifier == asset.localIdentifier { started.fulfill() } }
    let received = expectation(description: "Visible subscriber receives the promoted owner's result")
    pipeline.request(asset, pixels: 64) { image,_ in if image != nil { received.fulfill() } }
    await fulfillment(of: [started], timeout: 5)
    XCTAssertEqual(manager.started.last?.0, asset.localIdentifier)
    pipeline.cancel(tickets[50])
    let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { _ in }
    manager.complete(manager.started.last!.1, image: image, degraded: true)
    await fulfillment(of: [received], timeout: 5)
    XCTAssertEqual(cancelledCallbacks, 0)
    pipeline.clear()
  }

  func testBackgroundPreparationBoundsPixelsAndPreservesPreviewBeforeFinalNil() async throws {
    let fetch = PHAsset.fetchAssets(with: .image, options: photoLibraryFetchOptions())
    guard let asset = fetch.firstObject else { throw XCTSkip("Synthetic Photos fixtures required") }
    let manager = ControlledThumbnailManager(), pipeline = ThumbnailPipeline(manager: manager)
    pipeline.disk = nil
    let started = expectation(description: "Native request starts")
    manager.onStart = { _,_ in started.fulfill() }
    let received = expectation(description: "Prepared preview survives final nil")
    let blank = expectation(description: "Final nil must not erase a delivered preview"); blank.isInverted = true
    pipeline.request(asset, pixels: 320) { image,_ in
      if let image {
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height) * image.scale, 320)
        received.fulfill()
      } else { blank.fulfill() }
    }
    await fulfillment(of: [started], timeout: 5)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024)).image { ctx in
      UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }
    let native = manager.started[0].1
    manager.complete(native, image: image, degraded: true)
    manager.complete(native, image: nil, degraded: false)
    await fulfillment(of: [received], timeout: 5)
    await fulfillment(of: [blank], timeout: 0.1)
    pipeline.clear()
  }

  func testThumbnailFallbackIsSmallAndDoesNotReplaceRequestedSizeTier() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("Synthetic PhotoKit fixture only")
    #endif
    let fetch = PHAsset.fetchAssets(with: .image,options: photoLibraryFetchOptions())
    guard fetch.count > 0 else { throw XCTSkip("Import synthetic photo fixtures first") }
    let asset = fetch.object(at: 0), pipeline = ThumbnailPipeline()
    let available = expectation(description: "Local medium thumbnail")
    var fulfilled = false
    let first = pipeline.request(asset,pixels: 320) { image,_ in
      if image != nil && !fulfilled { fulfilled = true; available.fulfill() }
    }
    await fulfillment(of: [available],timeout: 5)
    pipeline.cancel(first)
    var synchronous: UIImage?
    let second = pipeline.request(asset,pixels: 64) { image,_ in synchronous = image }
    XCTAssertNotNil(synchronous,"Revisiting a cached asset has immediate fallback pixels")
    XCTAssertLessThanOrEqual(synchronous?.size.width ?? .infinity,64)
    XCTAssertLessThanOrEqual(synchronous?.size.height ?? .infinity,64)
    XCTAssertEqual(pipeline.size(40),CGSize(width: 64,height: 64))
    XCTAssertEqual(pipeline.size(120),CGSize(width: 128,height: 128))
    XCTAssertEqual(pipeline.size(320),CGSize(width: 320,height: 320))
    pipeline.cancel(second); pipeline.clear()
    XCTAssertNil(pipeline.poster(for: asset),"Cache clearing releases both size tiers and fallback posters")
  }

  func testBackupScopeUsesActualAlbumMembershipAndFrozenSnapshot() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("This fixture is simulator-only")
    #endif
    guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
      throw XCTSkip("Authorize only the disposable simulator's synthetic library first")
    }
    let images = PHAsset.fetchAssets(with: .image, options: photoLibraryFetchOptions())
    let videos = PHAsset.fetchAssets(with: .video, options: photoLibraryFetchOptions())
    guard images.count > 0, videos.count > 0 else { throw XCTSkip("Synthetic image/video fixtures required") }
    let photo = images.object(at: 0), video = videos.object(at: 0)
    var albumIDs: [String] = []
    try await PHPhotoLibrary.shared().performChanges {
      let a = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Scope fixture A")
      a.addAssets([photo, video] as NSArray)
      let b = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Scope fixture B")
      b.addAssets([photo] as NSArray)
      let c = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Scope fixture C")
      c.addAssets([video] as NSArray)
      albumIDs = [a.placeholderForCreatedAssetCollection.localIdentifier, b.placeholderForCreatedAssetCollection.localIdentifier]
    }
    // Keep these synthetic albums for subsequent native settings inspection.
    var rule = BackupScopeRule(types: [.photo], restrictAlbums: true, albums: Set(albumIDs))
    let union = await Task.detached { rule.selectedIDs() }.value
    XCTAssertEqual(union, [photo.localIdentifier], "Overlapping albums must not duplicate the asset")
    rule.types = [.video]; rule.albums = [albumIDs[1]]
    let excluded = await Task.detached { rule.selectedIDs() }.value
    XCTAssertTrue(excluded.isEmpty)
    rule.albums = [albumIDs[0]]
    let store = BackupScopeStore.shared, previous = store.rule
    store.save(rule); defer { store.save(previous) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("scope-snapshot-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let id = try await HistoricalScanCursor.capture(root: root, receiver: "scope-fixture")
    store.save(BackupScopeRule(types: []))
    let cursor = try await HistoricalScanCursor.load(root: root, receiver: "scope-fixture", run: 1, snapshotID: id)
    XCTAssertEqual(cursor.ids, [video.localIdentifier], "Changing settings cannot change an existing frozen scan")
  }

  func testAlbumScopedLibraryBrowsesOnlyThatAlbumWithoutChangingScope() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("This fixture is simulator-only")
    #endif
    guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
      throw XCTSkip("Authorize only the disposable simulator's synthetic library first")
    }
    let images = PHAsset.fetchAssets(with: .image, options: photoLibraryFetchOptions())
    guard images.count >= 600 else { throw XCTSkip("At least 600 synthetic images required") }
    let members = images.objects(at: IndexSet(integersIn: 0..<600))
    var albumID = ""
    try await PHPhotoLibrary.shared().performChanges {
      let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Scope fixture browse")
      album.addAssets(members as NSArray)
      albumID = album.placeholderForCreatedAssetCollection.localIdentifier
    }
    // Keep this synthetic album for native scrolling inspection.
    let store = BackupScopeStore.shared, rule = store.rule
    let library = PhotoLibraryModel(collection: albumID)
    await library.open()
    XCTAssertEqual(library.total, 600, "The album fetch pages its own membership, not the library")
    let ids = Set(members.map(\.localIdentifier))
    for index in 0..<library.loaded {
      let asset = try XCTUnwrap(library.asset(at: index))
      XCTAssertTrue(ids.contains(asset.localIdentifier))
    }
    let missing = PhotoLibraryModel(collection: "missing-album-fixture")
    await missing.open()
    XCTAssertEqual(missing.total, 0, "A missing album reads as empty, never as the whole library")
    if case .empty? = missing.placeholder {} else { XCTFail("A missing album shows the empty state") }
    XCTAssertEqual(store.rule, rule, "Browsing an album never changes the backup scope")
  }

  func testPhotoKitPredicatesIncludeImportedStillFixtures() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("Synthetic PhotoKit fixture only")
    #endif
    let all = PHAsset.fetchAssets(with: .image, options: photoLibraryFetchOptions())
    var expected: Set<String> = []
    all.enumerateObjects { asset,_,_ in if BackupMediaKind.kind(of: asset) == .photo { expected.insert(asset.localIdentifier) } }
    XCTAssertGreaterThan(expected.count, 1, "Import synthetic still photos before this integration check")
    let fetched = PHAsset.fetchAssets(with: photoLibraryFetchOptions(for: .photo))
    var actual: Set<String> = []
    fetched.enumerateObjects { asset,_,_ in actual.insert(asset.localIdentifier) }
    XCTAssertEqual(actual, expected)
  }

  func testLibraryAndScopeTypesShareDisjointPhotoMembership() async throws {
    #if !targetEnvironment(simulator)
      throw XCTSkip("PhotoKit acceptance is simulator-only")
    #endif
    let access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard access == .authorized else { throw XCTSkip("Photos authorization required") }
    let photoPredicate = try XCTUnwrap(photoLibraryFetchOptions(for: .photo).predicate)
    let livePredicate = try XCTUnwrap(photoLibraryFetchOptions(for: .motion).predicate)
    for subtype in [UInt(0), PHAssetMediaSubtype.photoLive.rawValue,
      PHAssetMediaSubtype.photoLive.union(.photoHDR).rawValue] {
      let metadata: [String: Any] = ["mediaType": PHAssetMediaType.image.rawValue, "mediaSubtype": subtype]
      XCTAssertEqual(photoPredicate.evaluate(with: metadata), subtype == 0, "Library Photos and backup Photos use the same still-only category")
      XCTAssertEqual(livePredicate.evaluate(with: metadata), subtype != 0)
    }
    XCTAssertFalse(photoPredicate.evaluate(with: ["mediaType": PHAssetMediaType.video.rawValue]))
    let expected = PHAsset.fetchAssets(with: photoLibraryFetchOptions(for: .photo))
    let model = PhotoLibraryModel()
    await model.open()
    await model.changeFilter(.photo)
    XCTAssertEqual(model.total, expected.count)
    XCTAssertEqual(model.total, model.fetch?.count)
    for index in 0..<model.loaded { XCTAssertEqual(model.asset(at: index)?.mediaType, .image) }
    await model.changeFilter(.motion)
    XCTAssertGreaterThanOrEqual(model.total, 0)
    XCTAssertEqual(model.total, model.fetch?.count)
    for index in 0..<model.loaded { XCTAssertTrue(model.asset(at: index)?.mediaSubtypes.contains(.photoLive) == true) }
    let pending = Task { await model.changeFilter(.video) }
    await Task.yield()
    XCTAssertEqual(model.total, model.fetch?.count, "Pending filter must retain one coherent result/count")
    await model.changeFilter(.photo)
    await pending.value
    XCTAssertEqual(model.filter, .photo)
    XCTAssertEqual(model.total, expected.count)
  }

  /// Persist genuine pending/history records for the subsequent UI drilldown
  /// checks. Only the dedicated simulator's synthetic PhotoKit library is used.
  func testSeedPausedSourceDrilldownsForUIAcceptance() async throws {
    #if !targetEnvironment(simulator)
    throw XCTSkip("Acceptance fixtures are simulator-only")
    #endif
    XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .readWrite), .authorized)
    let model = BackupModel.shared
    await model.open()
    let paused = await model.setPaused(true)
    XCTAssertTrue(paused)
    if model.pairing == nil {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("ui-receiver-" + UUID().uuidString)
      let data = try await Bridge.call(["op": "start_receiver", "root": root.path,
        "listen": "127.0.0.1:18489", "capacity": 32 * 1024 * 1024])
      try Keychain.save(data)
      model.pairing = try JSONDecoder().decode(Pairing.self, from: data)
      _ = try await Bridge.call(["op": "stop_receiver"])
    }
    let target = try XCTUnwrap(model.pairing)
    let options = photoLibraryFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    options.fetchLimit = 2
    let assets = PHAsset.fetchAssets(with: .image, options: options)
    XCTAssertEqual(assets.count, 2, "Synthetic image fixtures are required")
    let ids = (0..<assets.count).map { assets.object(at: $0).localIdentifier }
    _ = try await Bridge.call(["op": "schedule_sources", "receiver_id": target.receiverID, "sources": ids])
    let dates = await PhotoBackupOrder.captureDates(ids)
    _ = try await Bridge.call(["op": "source_dates", "receiver_id": target.receiverID,
      "dates": ids.map { [$0, dates[$0] ?? Int64.min] as [Any] }])
    await model.refreshPendingImportCount()
    XCTAssertGreaterThanOrEqual(model.pendingImports, 2)
    await model.controlHistoricalImport("restart")
    XCTAssertNotNil(model.historicalImport)
    XCTAssertNil(model.historyError)
    XCTAssertTrue(model.paused, "Seeding must never start a photo transfer")
  }

  func testBackupCaptureOrderIgnoresIdentifierAndSelectionOrder() async throws {
    #if !targetEnvironment(simulator)
      throw XCTSkip("Synthetic library acceptance is simulator-only")
    #endif
    let access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard access == .authorized else { throw XCTSkip("Photos authorization required") }
    let ids = try await createPhotos(count: 8, date: Date())
    let shuffled = [ids[3], ids[0], ids[6], ids[2], ids[7], ids[1], ids[5], ids[4]]
    let dates = await PhotoBackupOrder.captureDates(shuffled)
    XCTAssertEqual(dates.count, ids.count)
    let ordered = shuffled.sorted {
      PhotoBackupOrder.precedes($0, dates[$0] ?? Int64.min, $1, dates[$1] ?? Int64.min)
    }
    XCTAssertEqual(ordered, Array(ids.reversed()))
    XCTAssertTrue(PhotoBackupOrder.precedes("a", 1, "b", 1))
    XCTAssertTrue(PhotoBackupOrder.precedes("new", 1, "missing", Int64.min))
  }

  func testSelectionAcrossPaginationInsertionAndViewRecreation() async throws {
    #if !targetEnvironment(simulator)
      throw XCTSkip("Synthetic library acceptance is simulator-only")
    #endif
    // Resolve the simulator's pre-granted authorization through PhotoKit before
    // querying metadata; its initial cached status may still be notDetermined.
    let access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard access == .authorized else {
      XCTFail("Grant Photos to the test host on the disposable simulator (status \(access.rawValue))")
      return
    }
    // Prior runs intentionally leave synthetic fixtures available for UI review.
    // Put this run after their inserted dates so its pagination is deterministic.
    let latestOptions = photoLibraryFetchOptions()
    latestOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    latestOptions.fetchLimit = 1
    let latest = PHAsset.fetchAssets(with: latestOptions).firstObject?.creationDate ?? Date()
    let base = max(Date(), latest).addingTimeInterval(1_000)
    let ids = try await createPhotos(count: 260, date: base)
    let model = PhotoLibraryModel()
    await model.open()
    XCTAssertEqual(model.loaded, 240)
    let chosen = Set([ids[0], ids[238], ids[259]])
    model.selection = chosen
    XCTAssertEqual(model.selectedIndexPaths().count, 2)

    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    func host() {
      window.rootViewController = UIHostingController(rootView:
        IOSLibraryGrid(library: model, queueRevision: 0, receiverID: nil, showSupplementaryContent: true))
      window.makeKeyAndVisible()
    }
    defer { window.isHidden = true; window.rootViewController = nil }
    host()
    try await waitUntil("initial host: " + String(describing: collection(in: window)?.bounds)) {
      self.collection(in: window)?.indexPathsForSelectedItems?.count == 2
    }
    let grid = try XCTUnwrap(collection(in: window))
    XCTAssertEqual(selectedIDs(grid, model), chosen.subtracting([ids[0]]))
    let stableGeneration = model.generation
    let oldContentGeneration = model.contentGeneration
    let firstPath = try XCTUnwrap(grid.indexPathsForVisibleItems.sorted().first)
    let stableCell = try XCTUnwrap(grid.cellForItem(at: firstPath))
    let changedAsset = try XCTUnwrap(model.asset(at: firstPath.item))
    try await PHPhotoLibrary.shared().performChanges {
      PHAssetChangeRequest(for: changedAsset).isFavorite = !changedAsset.isFavorite
    }
    try await waitUntil("metadata update without grid rebuild") { model.contentGeneration > oldContentGeneration }
    XCTAssertEqual(model.generation, stableGeneration)
    XCTAssertTrue(grid.cellForItem(at: firstPath) === stableCell)

    model.loadMore()
    try await waitUntil("loaded selection") { self.selectedIDs(grid, model) == chosen }

    let originalIndex = try XCTUnwrap(model.selectedIndexPaths().map(\.item).min())
    _ = try await createPhotos(count: 1, date: base.addingTimeInterval(10))
    await model.reload()
    XCTAssertEqual(model.selection, chosen)
    XCTAssertEqual(model.selectedIndexPaths().map(\.item).min(), originalIndex + 1)
    model.loadMore()
    try await waitUntil("loaded selection") { self.selectedIDs(grid, model) == chosen }

    // Recreate the native collection with the same durable presentation model.
    host()
    try await waitUntil("recreated selection") {
      guard let recreated = self.collection(in: window) else { return false }
      return recreated !== grid && self.selectedIDs(recreated, model) == chosen
    }
    let recreated = try XCTUnwrap(collection(in: window))
    let extra = IndexPath(item: 5, section: 0)
    let extraID = try XCTUnwrap(model.asset(at: extra.item)?.localIdentifier)
    recreated.selectItem(at: extra, animated: false, scrollPosition: [])
    recreated.delegate?.collectionView?(recreated, didSelectItemAt: extra)
    XCTAssertEqual(model.selection, chosen.union([extraID]))
    recreated.deselectItem(at: extra, animated: false)
    recreated.delegate?.collectionView?(recreated, didDeselectItemAt: extra)
    XCTAssertEqual(model.selection, chosen)
    model.selection.removeAll()
    try await waitUntil("cleared selection") { recreated.indexPathsForSelectedItems?.isEmpty != false }

    // Preserve the same visible photo and partial-row inset, rather than only
    // the old pixel distance, across navigation and concurrent insertions.
    let scrollPath = IndexPath(item: 160, section: 0)
    let scrollFrame = try XCTUnwrap(recreated.collectionViewLayout.layoutAttributesForItem(at: scrollPath)?.frame)
    recreated.setContentOffset(CGPoint(x: 0, y: scrollFrame.minY + 17), animated: false)
    try await waitUntil("settled scroll bookmark") {
      guard let id = model.scrollAnchorID else { return false }
      return self.anchorIsVisible(id, inset: model.scrollAnchorInset, grid: recreated, model: model)
        && abs(model.scrollAnchorInset) < scrollFrame.height
    }
    let anchor = try XCTUnwrap(model.scrollAnchorID)
    let inset = model.scrollAnchorInset
    let position = try XCTUnwrap(model.index(of: anchor))
    host()
    try await waitUntil("navigation scroll anchor") {
      guard let grid = self.collection(in: window), grid !== recreated else { return false }
      return self.anchorIsVisible(anchor, inset: inset, grid: grid, model: model)
    }
    let afterNavigation = try XCTUnwrap(collection(in: window))
    // More than one page of insertions exercises expansion of the metadata
    // window when the visible photo moves beyond its previous boundary.
    _ = try await createPhotos(count: 250, date: base.addingTimeInterval(1_000))
    await model.reload()
    XCTAssertEqual(model.index(of: anchor), position + 250)
    XCTAssertGreaterThan(model.loaded, position + 250)
    try await waitUntil("insertion scroll anchor", details: {
      let index = model.index(of: anchor)
      let frame = index.flatMap { afterNavigation.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame }
      return "index=\(String(describing: index)), frame=\(String(describing: frame)), offset=\(afterNavigation.contentOffset), content=\(afterNavigation.contentSize), loaded=\(model.loaded), hasMore=\(model.hasMoreRows)"
    }) {
      self.anchorIsVisible(anchor, inset: inset, grid: afterNavigation, model: model)
    }

    await model.changeFilter(.video)
    XCTAssertEqual(model.scrollOffset, .zero)
    XCTAssertNil(model.scrollAnchorID)
    await model.changeFilter(.all)
    try await waitUntil("filter resets scroll", details: {
      "offset=\(afterNavigation.contentOffset), inset=\(afterNavigation.adjustedContentInset), anchor=\(String(describing: model.index(of: model.scrollAnchorID)))"
    }) {
      abs(afterNavigation.contentOffset.y) < 1
        && (model.index(of: model.scrollAnchorID) ?? 0) < 3
    }

    model.selection = chosen
    model.scrollOffset = CGPoint(x: 0, y: 500)
    let oldGeneration = model.generation
    XCTAssertFalse(model.applyAuthorization(.denied))
    XCTAssertEqual(model.authorizationStatus, .denied)
    guard case .permission(.denied)? = model.placeholder else {
      return XCTFail("Denied access must show the recovery action instead of an empty library")
    }
    XCTAssertNil(model.fetch)
    XCTAssertEqual(model.loaded, 0)
    XCTAssertEqual(model.total, 0)
    XCTAssertFalse(model.loading)
    XCTAssertTrue(model.selection.isEmpty)
    XCTAssertEqual(model.scrollOffset, .zero)
    XCTAssertNil(model.scrollAnchorID)
    XCTAssertGreaterThan(model.generation, oldGeneration)
    await model.reload()
    XCTAssertNil(model.fetch, "Denied models must not reload metadata")
    XCTAssertTrue(model.applyAuthorization(.authorized))
    XCTAssertEqual(model.authorizationStatus, .authorized)
    guard case .loading? = model.placeholder else {
      return XCTFail("The initial fetch must show loading instead of an empty library")
    }
    await model.reload()
    XCTAssertGreaterThanOrEqual(model.total, 261)
    XCTAssertTrue(model.selection.isEmpty, "Restoring permission must not restore a stale selection")
  }

  private func selectedIDs(_ grid: UICollectionView, _ model: PhotoLibraryModel) -> Set<String> {
    Set((grid.indexPathsForSelectedItems ?? []).compactMap { model.asset(at: $0.item)?.localIdentifier })
  }
  private func anchorIsVisible(_ id: String, inset: CGFloat, grid: UICollectionView,
    model: PhotoLibraryModel) -> Bool {
    guard let index = model.index(of: id),
      let frame = grid.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame,
      let cell = grid.cellForItem(at: IndexPath(item: index, section: 0)) as? PhotoCell
    else { return false }
    return cell.assetID == id && abs(grid.contentOffset.y - frame.minY - inset) < 1
  }
  private func collection(in view: UIView) -> UICollectionView? {
    if let collection = view as? UICollectionView { return collection }
    return view.subviews.lazy.compactMap { self.collection(in: $0) }.first
  }
  private func waitUntil(_ stage: String, details: () -> String = { "" },
    _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(10)
    while !condition() {
      guard Date() < deadline else {
        XCTFail("Native collection did not converge: \(stage) \(details())")
        throw NSError(domain: "LibraryTests", code: 1)
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
  }
  private func createPhotos(count: Int, date: Date) async throws -> [String] {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    }
    let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
    var ids: [String] = []
    try await PHPhotoLibrary.shared().performChanges {
      for offset in 0..<count {
        let request = PHAssetCreationRequest.forAsset()
        request.creationDate = date.addingTimeInterval(Double(offset - count))
        request.addResource(with: .photo, data: data, options: nil)
        if let id = request.placeholderForCreatedAsset?.localIdentifier { ids.append(id) }
      }
    }
    XCTAssertEqual(ids.count, count)
    return ids
  }
  /// A centre-cropped grid poster keeps its true place inside the photo frame,
  /// so a later full-aspect image adds the sides without magnifying the centre.
  /// An iCloud original can download for seconds. The device's local full-aspect
  /// rendition must replace the square grid crop at once, even though smaller.
  @MainActor func testViewerAdoptsLocalFullAspectRenditionOverSquareCrop() async throws {
    let fetch = PHAsset.fetchAssets(with: .image, options: photoLibraryFetchOptions())
    var landscape: PHAsset?
    fetch.enumerateObjects { asset, _, stop in
      if asset.pixelWidth > asset.pixelHeight, asset.mediaSubtypes.isEmpty { landscape = asset; stop.pointee = true }
    }
    guard let asset = landscape else { throw XCTSkip("A landscape synthetic photo is required") }
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let square = UIGraphicsImageRenderer(size: CGSize(width: 448, height: 448), format: format).image { _ in }
    let aspect = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    let local = UIGraphicsImageRenderer(size: CGSize(width: 300, height: (300 / aspect).rounded()), format: format).image { _ in }
    let manager = ControlledThumbnailManager()
    let model = MediaPreviewModel(asset: asset, poster: square, manager: manager)
    model.load()
    let localRequest = try XCTUnwrap(manager.started.first { manager.network[$0.1] == false })
    XCTAssertTrue(manager.started.contains { manager.network[$0.1] == true }, "The large request still runs")
    manager.complete(localRequest.1, image: local, degraded: false)
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(model.image === local, "A smaller full-aspect rendition replaces the square crop")
    model.cancel()
  }
  @MainActor func testViewerShowsCroppedPosterAtItsTruePlaceInPhotoFrame() {
    let scroll = MediaZoomScroll(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    scroll.mediaSize = CGSize(width: 4032, height: 3024)
    scroll.layoutIfNeeded()
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let square = UIGraphicsImageRenderer(size: CGSize(width: 352, height: 352), format: format).image { _ in }
    let full = UIGraphicsImageRenderer(size: CGSize(width: 352, height: 264), format: format).image { _ in }
    scroll.display(square)
    XCTAssertEqual(scroll.photo.contentMode, .scaleAspectFit)
    XCTAssertFalse(scroll.showsFullAspect)
    scroll.display(full)
    XCTAssertEqual(scroll.photo.contentMode, .scaleAspectFill)
    XCTAssertTrue(scroll.showsFullAspect)
    XCTAssertTrue(MediaZoomScroll.matchesAspect(CGSize(width: 1600, height: 1201), CGSize(width: 4032, height: 3024)))
  }

  // MARK: Decoded thumbnail tables

  private func tableURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("table-tests-\(UUID().uuidString)")
      .appendingPathComponent(name)
  }
  private func solid(_ color: UIColor, _ size: CGSize) -> CGImage {
    UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
      .image { context in color.setFill(); context.fill(CGRect(origin: .zero, size: size)) }.cgImage!
  }
  /// Blue, green and red bytes at a pixel of a BGRX table image.
  private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    let data = image.dataProvider!.data! as Data
    let offset = y * image.bytesPerRow + x * 4
    return Array(data[offset..<offset + 3])
  }

  func testThumbnailTableReturnsStoredSquareFromTheMapping() throws {
    let table = ThumbnailTable(url: tableURL("a.table"), side: 32, capacity: 64)
    XCTAssertTrue(table.available)
    XCTAssertFalse(table.contains("a|1"))
    table.store("a|1", image: solid(.red, CGSize(width: 120, height: 60)))
    XCTAssertTrue(table.contains("a|1"))
    XCTAssertFalse(table.contains("a|2"), "A new revision is a different entry")
    let image = try XCTUnwrap(table.image("a|1"))
    XCTAssertEqual(image.width, 32)
    XCTAssertEqual(image.height, 32)
    XCTAssertEqual(image.bytesPerRow % 64, 0, "Rows stay aligned for Core Animation")
    let center = pixel(image, x: 16, y: 16)
    XCTAssertLessThan(center[0], 8); XCTAssertLessThan(center[1], 8); XCTAssertGreaterThan(center[2], 247)
    XCTAssertNil(table.image("missing|1"))
  }

  func testThumbnailTablePersistsUntilGeometryChangesOrItIsCleared() throws {
    let url = tableURL("b.table")
    do {
      let table = ThumbnailTable(url: url, side: 32, capacity: 64)
      table.store("b|1", image: solid(.green, CGSize(width: 40, height: 40)))
    }
    let reopened = ThumbnailTable(url: url, side: 32, capacity: 64)
    XCTAssertTrue(reopened.contains("b|1"), "Entries survive relaunch")
    XCTAssertGreaterThan(reopened.usage, 0)
    reopened.clear()
    XCTAssertFalse(reopened.contains("b|1"))
    reopened.store("b|1", image: solid(.green, CGSize(width: 40, height: 40)))
    let resized = ThumbnailTable(url: url, side: 48, capacity: 64)
    XCTAssertFalse(resized.contains("b|1"), "A different geometry starts empty")
  }

  func testThumbnailTableReplacesTheLeastRecentlyUsedSlot() {
    let table = ThumbnailTable(url: tableURL("c.table"), side: 32, capacity: 4)
    let image = solid(.blue, CGSize(width: 32, height: 32))
    for key in ["a", "b", "c", "d"] { table.store(key, image: image) }
    _ = table.image("a")
    table.store("e", image: image)
    XCTAssertTrue(table.contains("a"), "A recently read entry stays")
    XCTAssertFalse(table.contains("b"), "The oldest entry gives way")
    XCTAssertTrue(table.contains("e"))
  }

  func testThumbnailTableStaysWithinItsBudgetLimit() {
    let table = ThumbnailTable(url: tableURL("d.table"), side: 32, capacity: 64)
    table.limit = 3
    let image = solid(.blue, CGSize(width: 32, height: 32))
    for i in 0..<20 { table.store("k\(i)", image: image) }
    XCTAssertEqual(table.count, 3)
    XCTAssertTrue(table.isFull)
    XCTAssertEqual(table.usage, 16_384 + 3 * table.entryBytes, "Usage counts header and stored entries")
    table.clear()
    XCTAssertEqual(table.usage, 0)
    XCTAssertFalse(table.isFull)
  }

  func testThumbnailTableSizesFollowThisDevicesGrids() {
    for columns in [3, 5, 15, 31] as [CGFloat] {
      let pixels = ThumbnailTables.tilePixels(columns: columns)
      XCTAssertEqual(pixels % 16, 0)
      XCTAssertGreaterThanOrEqual(pixels, 32)
      let screen = UIScreen.main, width = min(screen.bounds.width, screen.bounds.height)
      if UIDevice.current.userInterfaceIdiom == .phone {
        XCTAssertGreaterThanOrEqual(CGFloat(pixels), width / columns * screen.scale, "Never upscales a tile")
        XCTAssertLessThan(CGFloat(pixels), width / columns * screen.scale + 16)
      }
    }
    XCTAssertLessThanOrEqual(ThumbnailTables.overviewSide, ThumbnailTables.detailSide)
  }
}

private final class FastDegradedImageManager: PHCachingImageManager {
  var started = 0
  override func requestImage(for asset: PHAsset,targetSize: CGSize,contentMode: PHImageContentMode,
    options: PHImageRequestOptions?,resultHandler: @escaping (UIImage?,[AnyHashable:Any]?) -> Void) -> PHImageRequestID {
    started += 1
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: targetSize,format: format).image { context in
      UIColor.systemGreen.setFill(); context.fill(CGRect(origin: .zero,size: targetSize))
    }
    resultHandler(image,[PHImageResultIsDegradedKey:true])
    return PHImageRequestID(started)
  }
  override func cancelImageRequest(_ requestID: PHImageRequestID) {}
}

@MainActor private final class ControlledThumbnailManager: PHCachingImageManager, @unchecked Sendable {
  var started: [(String, PHImageRequestID)] = []
  var targets: [PHImageRequestID:CGSize] = [:]
  var network: [PHImageRequestID:Bool] = [:]
  var handlers: [PHImageRequestID: (UIImage?, [AnyHashable: Any]?) -> Void] = [:]
  var onStart: (PHAsset, PHImageRequestID) -> Void = { _,_ in }
  override func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHImageRequestOptions?, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    let id = PHImageRequestID(started.count + 1)
    targets[id] = targetSize; network[id] = options?.isNetworkAccessAllowed ?? false
    started.append((asset.localIdentifier, id)); handlers[id] = resultHandler
    onStart(asset, id)
    return id
  }
  func complete(_ id: PHImageRequestID, image: UIImage?, degraded: Bool) {
    handlers[id]?(image, [PHImageResultIsDegradedKey: degraded])
  }
  override func cancelImageRequest(_ id: PHImageRequestID) { handlers.removeValue(forKey: id) }

}

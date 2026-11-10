import AppKit
import Photos
import ImageIO
import UniformTypeIdentifiers
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

final class MacDetailPosterTests: XCTestCase {
  private func image(space: CGColorSpace) throws -> CGImage {
    let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 24, bitsPerComponent: 8,
      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(colorSpace: space, components: [0.2, 0.5, 0.8, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
    return try XCTUnwrap(context.makeImage())
  }

  func testFullAspectBitmapRoundTripsProfileAndRejectsWrongIdentityAndCorruption() throws {
    for name in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
      let original = try image(space: XCTUnwrap(CGColorSpace(name: name)))
      let data = try XCTUnwrap(MacDetailBitmap.encode(original, key: "asset|revision|viewport"))
      let decoded = try XCTUnwrap(MacDetailBitmap.decode(data, key: "asset|revision|viewport"))
      XCTAssertEqual(decoded.width, 40); XCTAssertEqual(decoded.height, 24)
      XCTAssertTrue(CFEqual(try XCTUnwrap(original.colorSpace), try XCTUnwrap(decoded.colorSpace)))
      XCTAssertEqual(decoded.bitmapInfo, original.bitmapInfo)
      XCTAssertNil(MacDetailBitmap.decode(data, key: "another revision"))
      XCTAssertNil(MacDetailBitmap.decode(Data(data.prefix(data.count / 2)), key: "asset|revision|viewport"))
    }
  }

  func testExtendedRangeAndHeadroomSurviveRoundTrip() throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
    let flags = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      | CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 32,
      bytesPerRow: 0, space: space, bitmapInfo: flags))
    context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [1.5, 0.5, 0.2, 1])))
    context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
    let source = try XCTUnwrap(context.makeImage())
    let hdr = try XCTUnwrap(CGImageCreateCopyWithContentHeadroom(2, source))
    let data = try XCTUnwrap(MacDetailBitmap.encode(hdr, key: "hdr"))
    let restored = try XCTUnwrap(MacDetailBitmap.decode(data, key: "hdr"))
    XCTAssertEqual(restored.bitsPerComponent, 32)
    XCTAssertEqual(restored.contentHeadroom, 2)
    XCTAssertTrue(CFEqual(try XCTUnwrap(hdr.colorSpace), try XCTUnwrap(restored.colorSpace)))
    XCTAssertEqual(try XCTUnwrap(hdr.dataProvider?.data) as Data,
      try XCTUnwrap(restored.dataProvider?.data) as Data)
  }

  func testSixteenBitComponentsAreNotReduced() throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
    let flags = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
      | CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 16,
      bytesPerRow: 0, space: space, bitmapInfo: flags))
    context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [0.2, 0.5, 0.8, 1])))
    context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
    let original = try XCTUnwrap(context.makeImage())
    let data = try XCTUnwrap(MacDetailBitmap.encode(original, key: "sixteen"))
    let restored = try XCTUnwrap(MacDetailBitmap.decode(data, key: "sixteen"))
    XCTAssertEqual(restored.bitsPerComponent, 16)
    XCTAssertEqual(try XCTUnwrap(original.dataProvider?.data) as Data,
      try XCTUnwrap(restored.dataProvider?.data) as Data)
  }

  func testSmallHDRSeedDoesNotBlockFittedSDRButFittedHDRIsKept() throws {
    func bitmap(width: Int, height: Int, space: CGColorSpace) throws -> CGImage {
      let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      return try XCTUnwrap(context.makeImage())
    }
    func hdr(width: Int, height: Int) throws -> CGImage {
      let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
      let flags = CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue
      let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 32,
        bytesPerRow: 0, space: space, bitmapInfo: flags))
      return try XCTUnwrap(context.makeImage())
    }
    let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let small = try hdr(width: 40, height: 24)
    let fittedHDR = try hdr(width: 400, height: 240)
    let fittedSDR = try bitmap(width: 400, height: 240, space: srgb)
    let target = CGSize(width: 400, height: 240)
    XCTAssertFalse(MacDetailBitmap.keepsCurrentColor(small, incoming: fittedSDR, fitted: target))
    XCTAssertTrue(MacDetailBitmap.keepsCurrentColor(fittedHDR, incoming: fittedSDR, fitted: target))
  }
}

private final class MacDetailAsset: PHAsset, @unchecked Sendable {
  let identifier: String, edited: Double
  init(_ identifier: String, edited: Double = 1) { self.identifier = identifier; self.edited = edited; super.init() }
  override var localIdentifier: String { identifier }
  override var modificationDate: Date? { Date(timeIntervalSince1970: edited) }
  override var pixelWidth: Int { 40 }
  override var pixelHeight: Int { 24 }
}

@MainActor final class MacDetailPosterPersistenceTests: XCTestCase {
  func testReopenEditPermissionAndClearRejectOldPixels() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = ThumbnailCacheStorage(directory: directory)
    let asset = MacDetailAsset("fixture"), target = MacDetailPosterTarget(pixels: CGSize(width: 40, height: 24), profile: "fixture")
    var access = PHAuthorizationStatus.authorized
    var revision: String? = PhotoLibraryModel.revision(asset)
    func makeStore() -> MacDetailPosterCache {
      MacDetailPosterCache(storage: storage, budget: { 1_000_000 }, tableUsage: { 0 },
        authorization: { access }, revision: { _ in revision }, publicationValid: { _, _ in true })
    }
    let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
    let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 40, height: 24))
    let first = makeStore(), oldGeneration = first.accessGeneration
    first.retain(image, asset: asset, target: target, generation: oldGeneration)
    XCTAssertNotNil(first.memoryPoster(asset: asset), "Opening should reuse pixels before disk encoding completes")
    for _ in 0..<100 where MacDetailPosterCache.diskUsage(directory: directory) == 0 {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertGreaterThan(MacDetailPosterCache.diskUsage(directory: directory), 0)
    first.invalidate() // Same eviction used by the memory-pressure handler.
    let reloadedAfterPressure = await first.load(asset: asset, target: target)
    XCTAssertNotNil(reloadedAfterPressure)
    let reopened = makeStore()
    let restored = await reopened.load(asset: asset, target: target)
    XCTAssertNotNil(restored)
    let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .first { $0.pathExtension == "detail" })
    let oldDirectory = directory.appendingPathComponent("expired", isDirectory: true)
    try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
    let oldFile = oldDirectory.appendingPathComponent(file.lastPathComponent)
    try FileManager.default.copyItem(at: file, to: oldFile)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -31 * 24 * 60 * 60)], ofItemAtPath: oldFile.path)
    let oldStore = MacDetailPosterCache(storage: ThumbnailCacheStorage(directory: oldDirectory), budget: { 1_000_000 },
      tableUsage: { 0 }, authorization: { access }, revision: { _ in revision }, publicationValid: { _, _ in true })
    let expired = await oldStore.load(asset: asset, target: target)
    XCTAssertNil(expired)
    revision = "edited"
    XCTAssertNil(first.memoryPoster(asset: asset))
    let stale = await reopened.load(asset: asset, target: target)
    XCTAssertNil(stale)
    revision = nil
    let deleted = await reopened.load(asset: asset, target: target)
    XCTAssertNil(deleted)
    revision = PhotoLibraryModel.revision(asset)
    let beforeRevocation = first.accessGeneration
    access = .denied
    let denied = await reopened.load(asset: asset, target: target)
    XCTAssertNil(denied)
    _ = first.accessGeneration
    access = .authorized
    try FileManager.default.removeItem(at: file)
    first.retain(image, asset: asset, target: target, generation: beforeRevocation)
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(MacDetailPosterCache.diskUsage(directory: directory), 0)
    first.retain(image, asset: asset, target: target, generation: first.accessGeneration)
    for _ in 0..<100 where MacDetailPosterCache.diskUsage(directory: directory) == 0 {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertGreaterThan(MacDetailPosterCache.diskUsage(directory: directory), 0)
    let token = try XCTUnwrap(storage.beginClear())
    await first.removeAll(epoch: token)
    storage.endClear(token)
    XCTAssertEqual(MacDetailPosterCache.diskUsage(directory: directory), 0)
    let cleared = await makeStore().load(asset: asset, target: target)
    XCTAssertNil(cleared)
  }

  func testClearWinsAgainstAWriteAlreadyPrepared() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = ThumbnailCacheStorage(directory: directory), asset = MacDetailAsset("pending")
    let target = MacDetailPosterTarget(pixels: CGSize(width: 40, height: 24), profile: "fixture")
    var release: CheckedContinuation<Void, Never>?
    let prepared = expectation(description: "prepared before clear"), finished = expectation(description: "old writer finished")
    let cache = MacDetailPosterCache(storage: storage, budget: { 1_000_000 }, tableUsage: { 0 },
      authorization: { .authorized }, revision: { PhotoLibraryModel.revision($0) }, beforeCommit: {
        await withCheckedContinuation { continuation in release = continuation; prepared.fulfill() }
      }, didFinish: { finished.fulfill() }, publicationValid: { _, _ in true })
    let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 40, height: 24))
    cache.retain(image, asset: asset, target: target, generation: cache.accessGeneration)
    await fulfillment(of: [prepared], timeout: 5)
    let epoch = try XCTUnwrap(storage.beginClear())
    await cache.removeAll(epoch: epoch)
    storage.endClear(epoch)
    release?.resume()
    await fulfillment(of: [finished], timeout: 5)
    XCTAssertEqual(MacDetailPosterCache.diskUsage(directory: directory), 0)
    let restored = await cache.load(asset: asset, target: target)
    XCTAssertNil(restored)
  }

  func testOtherTemporaryFilesAndReservedTableCapacityCountAgainstBudget() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data(count: 700_000).write(to: directory.appendingPathComponent("old-crash.detailtmp"))
    let storage = ThumbnailCacheStorage(directory: directory), asset = MacDetailAsset("budget")
    let target = MacDetailPosterTarget(pixels: CGSize(width: 40, height: 24), profile: "fixture")
    let finished = expectation(description: "writer finished")
    let cache = MacDetailPosterCache(storage: storage, budget: { 1_000_000 }, tableUsage: { 300_000 },
      authorization: { .authorized }, revision: { PhotoLibraryModel.revision($0) },
      didFinish: { finished.fulfill() }, publicationValid: { _, _ in true })
    let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 40, height: 24))
    cache.retain(image, asset: asset, target: target, generation: cache.accessGeneration)
    await fulfillment(of: [finished], timeout: 5)
    XCTAssertEqual(MacDetailPosterCache.diskUsage(directory: directory), 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("old-crash.detailtmp").path))
  }

  func testInvalidationDoesNotWaitForInFlightRenameAndRetractsItsPublication() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = ThumbnailCacheStorage(directory: directory), asset = MacDetailAsset("slow-publish")
    let target = MacDetailPosterTarget(pixels: CGSize(width: 40, height: 24), profile: "fixture")
    let entered = expectation(description: "rename completed"), finished = expectation(description: "writer completed")
    let resume = DispatchSemaphore(value: 0)
    let cache = MacDetailPosterCache(storage: storage, budget: { 1_000_000 }, tableUsage: { 0 },
      authorization: { .authorized }, revision: { PhotoLibraryModel.revision($0) },
      didFinish: { finished.fulfill() }, afterRename: { entered.fulfill(); resume.wait() },
      publicationValid: { _, _ in true })
    let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 40, height: 24))
    cache.retain(image, asset: asset, target: target, generation: cache.accessGeneration)
    await fulfillment(of: [entered], timeout: 5)
    let start = ProcessInfo.processInfo.systemUptime
    cache.invalidate()
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.2)
    resume.signal()
    await fulfillment(of: [finished], timeout: 5)
    XCTAssertEqual(MacDetailPosterCache.diskUsage(directory: directory), 0)
  }
}


final class MacFileDetailPosterTests: XCTestCase {
  func testFolderDetailPersistsFullAspectAndRejectsChangedFileAndOldEpoch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("photo.png")
    func write(width: Int, height: Int) throws {
      let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(CGColor(red: 0.7, green: 0.2, blue: 0.3, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
    try write(width: 120, height: 60)
    let storage = ThumbnailCacheStorage(directory: root.appendingPathComponent("cache"))
    let photo = FolderPhoto(relative: "photo.png", source_id: "source", revision: "revision", size: 1,
      media_type: "image/png", modified_ms: 1, folder_id: "folder", capture_ms: 1,
      date_source: "file_modified", backup: "not_backed_up", saved_at_ms: nil)
    let target = MacDetailPosterTarget(pixels: CGSize(width: 80, height: 80), profile: "fixture")
    let epoch = try XCTUnwrap(storage.epoch)
    let cache = MacFileDetailPosterCache(storage: storage)
    let firstResult = await cache.load(photo: photo, file: file, root: root, target: target,
      epoch: epoch, budget: 1_000_000, reserved: 0)
    let first = try XCTUnwrap(firstResult)
    XCTAssertEqual(first.width, 80); XCTAssertEqual(first.height, 40)
    XCTAssertGreaterThan(storage.detailUsage, 0)
    let reopened = MacFileDetailPosterCache(storage: storage)
    let secondResult = await reopened.load(photo: photo, file: file, root: root, target: target,
      epoch: epoch, budget: 1_000_000, reserved: 0)
    let second = try XCTUnwrap(secondResult)
    XCTAssertEqual(first.dataProvider?.data as Data?, second.dataProvider?.data as Data?)
    XCTAssertTrue(CFEqual(try XCTUnwrap(first.colorSpace), try XCTUnwrap(second.colorSpace)))
    // Even before the source index supplies a new revision, a changed file
    // must not receive the previous full-aspect image from either cache tier.
    try write(width: 60, height: 120)
    let changedResult = await cache.load(photo: photo, file: file, root: root, target: target,
      epoch: epoch, budget: 1_000_000, reserved: 0)
    let changed = try XCTUnwrap(changedResult)
    XCTAssertEqual(changed.width, 40); XCTAssertEqual(changed.height, 80)
    let clearing = try XCTUnwrap(storage.beginClear())
    XCTAssertNil(storage.clearDetails()); storage.endClear(clearing)
    _ = await cache.load(photo: photo, file: file, root: root, target: target,
      epoch: epoch, budget: 1_000_000, reserved: 0)
    XCTAssertEqual(storage.detailUsage, 0)
    try FileManager.default.removeItem(at: file)
    let unavailable = await cache.load(photo: photo, file: file, root: root, target: target,
      epoch: storage.epoch, budget: 1_000_000, reserved: 0)
    XCTAssertNil(unavailable)
  }
}

@MainActor final class FileThumbnailPipelineTests: XCTestCase {
  private func fixture() throws -> (URL, FolderSource, ThumbnailCacheStorage, CGImage) {
    let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent("disk-grid-\(UUID().uuidString)", isDirectory: true)
    let root = base.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.systemBlue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
    let image = try XCTUnwrap(context.makeImage())
    let file = root.appendingPathComponent("fixture.jpg")
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
    try Data([1]).write(to: root.appendingPathComponent("clip.mp4"))
    let bookmark = try root.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    return (base, FolderSource(id: UUID().uuidString, name: "Fixture", bookmark: bookmark,
      automatic: false, enabled: true, receiver: nil, lastCheck: nil),
      ThumbnailCacheStorage(directory: base.appendingPathComponent("cache", isDirectory: true)), image)
  }

  func testRestartUsesFinalDiskTierWithoutOriginalAndRevisionDoesNotReuseIt() async throws {
    let (base, source, storage, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: base) }
    let first = FileThumbnailPipeline(storage: storage, budget: { 16 * 1024 * 1024 })
    let cold = expectation(description: "persist final tier")
    first.request(id: UUID(), source: source, relative: "fixture.jpg", revision: "one", size: 256) { image in
      XCTAssertNotNil(image); cold.fulfill()
    }
    await fulfillment(of: [cold], timeout: 10)
    while !first.isIdle { try await Task.sleep(for: .milliseconds(10)) }
    try FileManager.default.removeItem(at: base.appendingPathComponent("source/fixture.jpg"))
    var offline = source
    offline.bookmark = Data()
    let restarted = FileThumbnailPipeline(storage: storage, budget: { 16 * 1024 * 1024 })
    let warm = expectation(description: "disk tier survives source absence and new instance")
    restarted.request(id: UUID(), source: offline, relative: "fixture.jpg", revision: "one", size: 64) { image in
      XCTAssertNotNil(image); warm.fulfill()
    }
    await fulfillment(of: [warm], timeout: 10)
    XCTAssertEqual(restarted.statistics.diskHits, 1); XCTAssertEqual(restarted.statistics.originalLoads, 0)
    var immediately: NSImage?
    restarted.request(id: UUID(), source: offline, relative: "fixture.jpg", revision: "one", size: 128) { immediately = $0 }
    XCTAssertNotNil(immediately, "A retained larger tier is immediately available without a bookmark")
    XCTAssertEqual(restarted.statistics.memoryHits, 1)
    let changed = expectation(description: "new revision does not show old pixels")
    restarted.request(id: UUID(), source: offline, relative: "fixture.jpg", revision: "two", size: 64) { image in
      XCTAssertNil(image); changed.fulfill()
    }
    await fulfillment(of: [changed], timeout: 10)
    XCTAssertEqual(restarted.statistics.diskHits, 1)
  }

  func testCoalescingCancellationAndVideoRenditionPersistence() async throws {
    let (base, source, storage, bitmap) = try fixture()
    defer { try? FileManager.default.removeItem(at: base) }
    var calls = 0
    let pipeline = FileThumbnailPipeline(storage: storage, budget: { 16 * 1024 * 1024 }, originalLoader: { _, _ in
      calls += 1; try? await Task.sleep(for: .milliseconds(80)); return bitmap
    })
    let cancelled = expectation(description: "cancelled subscriber is not called"); cancelled.isInverted = true
    let survivor = expectation(description: "surviving subscriber")
    let id = UUID()
    pipeline.request(id: id, source: source, relative: "clip.mp4", revision: "one", size: 256) { _ in cancelled.fulfill() }
    pipeline.request(id: UUID(), source: source, relative: "clip.mp4", revision: "one", size: 256) { image in
      XCTAssertNotNil(image); survivor.fulfill()
    }
    pipeline.cancel(id)
    await fulfillment(of: [survivor, cancelled], timeout: 0.8)
    XCTAssertEqual(calls, 1); XCTAssertEqual(pipeline.statistics.coalescedRequests, 1)
    while !pipeline.isIdle { try await Task.sleep(for: .milliseconds(10)) }
    let restarted = FileThumbnailPipeline(storage: storage, budget: { 16 * 1024 * 1024 }, originalLoader: { _, _ in
      XCTFail("The persisted video rendition must bypass the native generator"); return nil
    })
    let warm = expectation(description: "video uses same durable cache")
    restarted.request(id: UUID(), source: source, relative: "clip.mp4", revision: "one", size: 256) { image in
      XCTAssertNotNil(image); warm.fulfill()
    }
    await fulfillment(of: [warm], timeout: 10)
    XCTAssertEqual(restarted.statistics.originalLoads, 0)
  }

  func testDiskHitDoesNotWaitForBusyOriginalDecoder() async throws {
    let (base, source, storage, bitmap) = try fixture()
    defer { try? FileManager.default.removeItem(at: base) }
    let seed = FileThumbnailPipeline(storage: storage, budget: { 16 * 1024 * 1024 })
    let seeded = expectation(description: "seed disk")
    seed.request(id: UUID(), source: source, relative: "fixture.jpg", revision: "one", size: 256) { _ in seeded.fulfill() }
    await fulfillment(of: [seeded], timeout: 10)
    while !seed.isIdle { try await Task.sleep(for: .milliseconds(10)) }
    var release: CheckedContinuation<CGImage?, Never>?
    let started = expectation(description: "slow generator has started")
    let pipeline = FileThumbnailPipeline(storage: storage, budget: { 16 * 1024 * 1024 }, originalLoader: { _, _ in
      await withCheckedContinuation { continuation in release = continuation; started.fulfill() }
    })
    let slow = expectation(description: "slow work completes after disk hit")
    pipeline.request(id: UUID(), source: source, relative: "clip.mp4", revision: "one", size: 256) { _ in slow.fulfill() }
    await fulfillment(of: [started], timeout: 10)
    let warm = expectation(description: "disk is independent")
    pipeline.request(id: UUID(), source: source, relative: "fixture.jpg", revision: "one", size: 256) { image in
      XCTAssertNotNil(image); XCTAssertNotNil(release); warm.fulfill()
    }
    await fulfillment(of: [warm], timeout: 2)
    XCTAssertEqual(pipeline.statistics.diskHits, 1)
    release?.resume(returning: bitmap); release = nil
    await fulfillment(of: [slow], timeout: 10)
  }

  func testCompletionReentryCannotDeliverOrRemoveAReplacedSubscriber() async throws {
    let (base, source, storage, bitmap) = try fixture()
    defer { try? FileManager.default.removeItem(at: base) }
    var loads = 0
    let pipeline = FileThumbnailPipeline(storage: storage, budget: { 16 * 1024 * 1024 }, originalLoader: { _, _ in
      loads += 1; return loads == 1 ? nil : bitmap
    })
    let first = UUID(), second = UUID()
    var replaced = false
    let ready = expectation(description: "replacement receives its own completion")
    func completion(_ other: UUID) -> (NSImage?) -> Void {
      { image in
        guard !replaced else { XCTFail("The cancelled old subscriber completed"); return }
        replaced = true; XCTAssertNil(image)
        pipeline.request(id: other, source: source, relative: "fixture.jpg", revision: "one", size: 128) { image in
          XCTAssertNotNil(image); ready.fulfill()
        }
      }
    }
    pipeline.request(id: first, source: source, relative: "fixture.jpg", revision: "one", size: 128, completion: completion(second))
    pipeline.request(id: second, source: source, relative: "fixture.jpg", revision: "one", size: 128, completion: completion(first))
    await fulfillment(of: [ready], timeout: 10)
    while !pipeline.isIdle { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(loads, 2)
  }

  func testColdWarmCancellationAndClear() async throws {
    let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent("folder-thumbnail-\(UUID().uuidString)", isDirectory: true)
    let folder = base.appendingPathComponent("source", isDirectory: true)
    let cache = base.appendingPathComponent("cache", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let file = folder.appendingPathComponent("fixture.jpg")
    let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    let source = FolderSource(id: UUID().uuidString, name: "Fixture", bookmark: bookmark,
      automatic: false, enabled: true, receiver: nil, lastCheck: nil)
    let storage = ThumbnailCacheStorage(directory: cache)
    func pipeline() -> FileThumbnailPipeline { FileThumbnailPipeline(storage: storage, budget: { 16 * 1024 * 1024 }) }
    let first = pipeline(), coldReady = expectation(description: "cold target")
    let coldStart = Date()
    var coldSizes: [Int] = []
    first.request(id: UUID(), source: source, relative: "fixture.jpg", revision: "one", size: 256) { image in
      guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
      let edge = max(cg.width, cg.height)
      coldSizes.append(edge)
      if edge > 192 { coldReady.fulfill() }
    }
    await fulfillment(of: [coldReady], timeout: 15)
    print("Folder thumbnails cold target: \(Date().timeIntervalSince(coldStart))s, sizes: \(coldSizes)")
    XCTAssertFalse(coldSizes.isEmpty)
    if coldSizes.count > 1 { XCTAssertLessThanOrEqual(coldSizes[0], coldSizes[1]) }
    for _ in 0..<200 {
      if storage.detailUsage > 0 { break }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertGreaterThan(storage.detailUsage, 0, "The display-sized rendition should be persisted")
    let second = pipeline(), warmReady = expectation(description: "warm low resolution")
    let warmStart = Date()
    var warmSizes: [(Int, Int)] = []
    let warmID = UUID()
    second.request(id: warmID, source: source, relative: "fixture.jpg", revision: "one", size: 256) { image in
      guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
      warmSizes.append((cg.width, cg.height))
      if warmSizes.count == 1 { warmReady.fulfill() }
    }
    await fulfillment(of: [warmReady], timeout: 15)
    print("Folder thumbnails warm first: \(Date().timeIntervalSince(warmStart))s, sizes: \(warmSizes)")
    let warm = try XCTUnwrap(warmSizes.first)
    XCTAssertGreaterThanOrEqual(min(warm.0, warm.1), 512)
    XCTAssertEqual(second.statistics.originalLoads, 0, "A sufficient disk hit must finish without opening the original")
    XCTAssertEqual(Double(warm.0) / Double(warm.1), 1.5, accuracy: 0.03)
    second.cancel(warmID)

    let cancelled = expectation(description: "cancelled request does not deliver")
    cancelled.isInverted = true
    let cancelledID = UUID()
    second.request(id: cancelledID, source: source, relative: "fixture.jpg", revision: "another", size: 256) { _ in cancelled.fulfill() }
    second.cancel(cancelledID)
    await fulfillment(of: [cancelled], timeout: 0.5)

    let clearEpoch = try XCTUnwrap(storage.beginClear())
    XCTAssertNil(storage.clearDetails())
    storage.endClear(clearEpoch)
    let afterClear = expectation(description: "after clear returns asynchronously")
    var returnedSynchronously = false
    var requesting = true, completed = false
    let clearID = UUID()
    first.request(id: clearID, source: source, relative: "fixture.jpg", revision: "one", size: 256) { image in
      if requesting { returnedSynchronously = true }
      if image != nil, !completed { completed = true; afterClear.fulfill() }
    }
    requesting = false
    XCTAssertFalse(returnedSynchronously, "A thumbnail cached before clear must not be returned from memory")
    await fulfillment(of: [afterClear], timeout: 15)
    first.cancel(clearID)
  }
}

private final class DetailCallbackAsset: PHAsset, @unchecked Sendable {
  override var localIdentifier: String { "synthetic-detail-callback-test" }
  override var pixelWidth: Int { 40 }
  override var pixelHeight: Int { 24 }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
}

@MainActor private final class DetailCallbackManager: PHImageManager, @unchecked Sendable {
  typealias Handler = (NSImage?, [AnyHashable: Any]?) -> Void
  private(set) var handlers: [Handler] = []
  override func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHImageRequestOptions?, resultHandler: @escaping (NSImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    handlers.append(resultHandler)
    return PHImageRequestID(handlers.count)
  }
  override func cancelImageRequest(_ requestID: PHImageRequestID) {}
  func deliver(_ index: Int, image: NSImage, degraded: Bool) {
    handlers[index](image, [PHImageResultIsDegradedKey: degraded])
  }
}

@MainActor final class MacDetailCallbackQualityTests: XCTestCase {
  private func image(red: CGFloat, extended: Bool) throws -> NSImage {
    let space = try XCTUnwrap(CGColorSpace(name: extended ? CGColorSpace.extendedLinearSRGB : CGColorSpace.sRGB))
    let flags = extended
      ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
      : CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 24, bitsPerComponent: extended ? 32 : 8,
      bytesPerRow: 0, space: space, bitmapInfo: flags))
    context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [red, 0, 1 - red, 1])))
    context.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
    return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 40, height: 24))
  }
  private func waitForImage(_ image: NSImage, in model: MediaPreviewModel, file: StaticString = #filePath, line: UInt = #line) async throws {
    for _ in 0..<100 {
      if model.image === image { return }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTFail("Expected callback image was not adopted", file: file, line: line)
  }
  func testFinalOutranksSameSizeDegradedAndLateLocalCallbacks() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let asset = DetailCallbackAsset(), manager = DetailCallbackManager()
    let degradedHDR = try image(red: 1, extended: true)
    let finalSDR = try image(red: 0, extended: false)
    let model = MediaPreviewModel(asset: asset, manager: manager)
    model.load()
    defer { model.cancel() }
    XCTAssertEqual(manager.handlers.count, 2)
    guard manager.handlers.count == 2 else { return }
    // Local request is first; the high-resolution opportunistic request is second.
    manager.deliver(1, image: degradedHDR, degraded: true)
    try await waitForImage(degradedHDR, in: model)
    manager.deliver(1, image: finalSDR, degraded: false)
    try await waitForImage(finalSDR, in: model)
    // Both callbacks have the same nominal dimensions; the HDR seed must not
    // veto the final SDR result, and late callbacks must not replace it.
    manager.deliver(0, image: degradedHDR, degraded: false)
    manager.deliver(1, image: degradedHDR, degraded: true)
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(model.image === finalSDR)

    let secondManager = DetailCallbackManager()
    let second = MediaPreviewModel(asset: asset, manager: secondManager)
    second.load()
    defer { second.cancel() }
    XCTAssertEqual(secondManager.handlers.count, 2)
    guard secondManager.handlers.count == 2 else { return }
    secondManager.deliver(1, image: finalSDR, degraded: false)
    try await waitForImage(finalSDR, in: second)
    secondManager.deliver(0, image: degradedHDR, degraded: false)
    secondManager.deliver(1, image: degradedHDR, degraded: true)
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(second.image === finalSDR)
  }
}

final class MacViewerTitleFormattingTests: XCTestCase {
  func testFullDateAndCompactPositionWithOptionalPlace() {
    let date = Date(timeIntervalSince1970: 1_704_067_445) // 2024-01-01 00:04:05 UTC
    let utc = TimeZone(secondsFromGMT: 0)!
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
    let full = MacViewerTitle.fullDate(date, locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: utc)
    XCTAssertTrue(full.contains("2024"))
    XCTAssertTrue(full.contains("04:05"))
    XCTAssertEqual(MacViewerTitle.fullDate(date, locale: Locale(identifier: "zh_CN"), calendar: calendar, timeZone: utc),
      "2024年1月1日00:04:05")
    XCTAssertEqual(MacViewerTitle.date(date), MacViewerTitle.fullDate(date))
    XCTAssertEqual(MacViewerTitle.subtitle(date, index: 3, total: 20), "3/20")
    XCTAssertEqual(MacViewerTitle.date(date, place: "  Shanghai  "), "Shanghai")
    XCTAssertEqual(MacViewerTitle.subtitle(date, index: 3, total: 20, place: "Shanghai"),
      MacViewerTitle.fullDate(date) + "  ·  3/20")
    XCTAssertEqual(MacViewerTitle.subtitle(date, index: 3, total: 20, place: "   "), "3/20")
  }
}

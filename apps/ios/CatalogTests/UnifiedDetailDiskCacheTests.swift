import CoreImage
import CryptoKit
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import BackupDuckCatalog

@MainActor final class UnifiedDetailDiskCacheTests: XCTestCase {
  func testLosslessSDRWideColorAlphaAndAllOrientationsRoundTrip() async throws {
    for space in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
      for orientation in UIImage.Orientation.allCacheCases {
        let image = try bitmap(space: space, orientation: orientation)
        let encoded = try unwrap(await Task.detached { DetailThumbnailCodec.encode(image, key: "roundtrip") }.value)
        let decoded = try unwrap(await Task.detached { DetailThumbnailCodec.decode(encoded, key: "roundtrip") }.value)
        try assertSamePixels(image, decoded)
        expectNil(DetailThumbnailCodec.decode(encoded, key: "other-revision"))
      }
    }
  }

  func testHDRFloatAndImageIOEncodedHDRKeepNativeComponentsAndHeadroom() async throws {
    for bits in [16, 32] {
      let image = try bitmap(space: CGColorSpace.extendedLinearDisplayP3, bits: bits, orientation: .right)
      expectTrue(DetailThumbnailQuality(image).hdr)
      let encoded = try unwrap(await Task.detached { DetailThumbnailCodec.encode(image, key: "hdr") }.value)
      let decoded = try unwrap(DetailThumbnailCodec.decode(encoded, key: "hdr"))
      try assertSamePixels(image, decoded)
      let raw = try unwrap(decoded.cgImage?.dataProvider?.data) as Data
      let value = raw.withUnsafeBytes { bits == 16 ? Float(Float16(bitPattern: $0.load(as: UInt16.self))) : $0.load(as: Float.self) }
      expectGreater(value, 1, "Native values above SDR white must survive persistence")
    }
    let image = try bitmap(space: CGColorSpace.extendedLinearDisplayP3, bits: 16)
    let pq = try unwrap(CGColorSpace(name: CGColorSpace.itur_2100_PQ))
    let png = try unwrap(CIContext().pngRepresentation(of: CIImage(cgImage: image.cgImage!),
      format: .RGBA16, colorSpace: pq, options: [:]))
    var configuration = UIImageReader.Configuration(); configuration.prefersHighDynamicRange = true
    let source = try unwrap(await UIImageReader(configuration: configuration).image(data: png))
    expectTrue(source.isHighDynamicRange)
    let data = try unwrap(DetailThumbnailCodec.encode(source, key: "encoded-hdr"))
    try assertSamePixels(source, unwrap(DetailThumbnailCodec.decode(data, key: "encoded-hdr")))
  }

  func testAdaptiveHDRWithUnavailableAuxiliaryPixelsIsSkipped() async throws {
    let source = try bitmap(space: CGColorSpace.extendedLinearDisplayP3, bits: 16, opaque: true)
    let base = try bitmap(opaque: true)
    let data = try unwrap(CIContext().jpegRepresentation(of: CIImage(cgImage: base.cgImage!),
      colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
      options: [.hdrImage: CIImage(cgImage: source.cgImage!), .hdrGainMapAsRGB: true]))
    let encodedSource = try unwrap(CGImageSourceCreateWithData(data as CFData, nil))
    expectNotNil(CGImageSourceCopyAuxiliaryDataInfoAtIndex(encodedSource, 0, kCGImageAuxiliaryDataTypeISOGainMap))
    var configuration = UIImageReader.Configuration(); configuration.prefersHighDynamicRange = false
    let image = try unwrap(await UIImageReader(configuration: configuration).image(data: data as Data))
    if image.isHighDynamicRange, let space = image.cgImage?.colorSpace,
      !space.isHDR(), !CGColorSpaceUsesExtendedRange(space) {
      expectNil(DetailThumbnailCodec.encode(image, key: "adaptive"))
    } else {
      // UIKit may materialize an explicit HDR bitmap on this OS. That actual
      // representation must pass the same lossless round trip or be skipped.
      if let encoded = DetailThumbnailCodec.encode(image, key: "adaptive") {
        try assertSamePixels(image, unwrap(DetailThumbnailCodec.decode(encoded, key: "adaptive")))
      }
    }
    expectNil(DetailThumbnailCodec.encode(UIImage(ciImage: CIImage(cgImage: source.cgImage!)), key: "deferred"))
    // Probe UIKit's native encoder against the same actual auxiliary-data
    // fixture. The cache codec does not adopt a lossy conversion as a fallback.
    var hdrConfiguration = UIImageReader.Configuration(); hdrConfiguration.prefersHighDynamicRange = true
    let expanded = try unwrap(await UIImageReader(configuration: hdrConfiguration).image(data: data))
    for (label, candidate) in [("adaptive-default", image), ("adaptive-hdr", expanded), ("explicit-float", source)] {
      let encoded = await Task.detached { candidate.heicData() }.value
      guard let encoded, let roundtrip = await UIImageReader(configuration: hdrConfiguration).image(data: encoded),
        let before = candidate.cgImage, let after = roundtrip.cgImage else {
        print("DETAIL_HEIC_PROBE", label, "unavailable"); continue
      }
      print("DETAIL_HEIC_PROBE", label, "bytes", encoded.count,
        "hdr", candidate.isHighDynamicRange, roundtrip.isHighDynamicRange,
        "space", before.colorSpace?.name as Any, after.colorSpace?.name as Any,
        "bits", before.bitsPerComponent, after.bitsPerComponent,
        "headroom", before.contentHeadroom, after.contentHeadroom,
        "orientation", candidate.imageOrientation.rawValue, roundtrip.imageOrientation.rawValue,
        "exactPixels", before.dataProvider?.data as Data? == after.dataProvider?.data as Data?)
    }
  }

  func testCorruptPixelsMetadataAndUnsupportedVersionAreRejected() throws {
    let data = try unwrap(DetailThumbnailCodec.encode(bitmap(), key: "metadata"))
    let original = try unwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    for (field, value) in [("version", 999 as Any), ("key", "wrong"), ("rowBytes", Int.max),
      ("orientation", -1), ("pixels", Data([1, 2, 3])), ("checksum", Data(repeating: 0, count: 32)),
      ("colorName", CGColorSpace.displayP3 as String), ("colorProfile", Data([1, 2, 3]))] {
      var changed = original; changed[field] = value
      let corrupt = try PropertyListSerialization.data(fromPropertyList: changed, format: .binary, options: 0)
      expectNil(DetailThumbnailCodec.decode(corrupt, key: "metadata"), "Field: \(field)")
    }
  }

  func testFreshStoresShareFittedTierAcrossProcessDisplayIdentityAndMemoryPressure() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk(), store = fixture.store(disk: disk)
    let target = DetailPosterTarget(pixels: CGSize(width: 320, height: 240), screen: "process-A", displayProfile: "P3@3-native")
    let asset = DiskPosterAsset("relaunch")
    let pipeline = ThumbnailPipeline(detailStore: store)
    pipeline.retainDetailPoster(try bitmap(width: 640, height: 480), for: asset, target: target)
    let key = identity(asset, target).key
    try await waitForDisk(disk, key: key)
    let bytes = await disk.usage(); expectGreater(bytes, 0)
    NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    expectNil(pipeline.detailPoster(for: asset, target: target))
    expectEqual(await disk.usage(), bytes)
    let otherTarget = DetailPosterTarget(pixels: target.pixels, screen: "process-B", displayProfile: "P3@3-native")
    let freshDisk = fixture.disk(), fresh = fixture.store(disk: freshDisk)
    let loaded = try unwrap(await fresh.loadDetailPoster(for: asset, target: otherTarget))
    expectEqual(loaded.size, CGSize(width: 320, height: 240))
    expectEqual(await freshDisk.usage(), bytes)
    let different = DetailPosterTarget(pixels: CGSize(width: 640, height: 480), screen: "process-B", displayProfile: "P3@3-native")
    expectNil(await fresh.loadDetailPoster(for: asset, target: different))
    let otherProfile = DetailPosterTarget(pixels: target.pixels, screen: "process-B", displayProfile: "sRGB@2-native")
    expectNil(await fresh.loadDetailPoster(for: asset, target: otherProfile))
    let cropped = await disk.read(key); expectNil(cropped.0, "A full-aspect entry is never a grid JPEG")
  }

  func testUserBudgetAccountsGridOverviewAndDetailAndEvictsLeastRecentlyViewed() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk()
    await disk.setBudget(128)
    let epoch = try unwrap(await disk.detailEpoch())
    // Repeatable incompressible bytes make eviction exercise real encoded size.
    let image = try noiseBitmap(width: 3200, height: 2400)
    let first = await disk.storeDetail(image, key: "old-detail", generation: epoch, valid: { true })
    expectTrue(first)
    let second = await disk.storeDetail(image, key: "viewed-detail", generation: epoch, valid: { true })
    expectTrue(second)
    let overview = Data(repeating: 7, count: 24 * 1024 * 1024)
    await disk.storeOverview(overview, generation: epoch, valid: { true })
    await disk.store(try bitmap(), key: "grid", generation: epoch)
    let before = await disk.usage(); expectGreater(before, 64 * 1024 * 1024)
    _ = await disk.readDetail("viewed-detail")
    _ = await disk.readDetail("old-detail", touch: false)
    await disk.setBudget(64)
    expectAtMost(await disk.usage(), 64 * 1024 * 1024)
    expectNil(await disk.readDetail("old-detail").0)
    expectNotNil(await disk.readDetail("viewed-detail").0)
    expectNotNil(await disk.read("grid").0)
    expectNotNil(await disk.readOverview().0)
    let reopened = fixture.disk()
    expectEqual(await reopened.usage(), await disk.usage())
  }

  func testExplicitClearInvalidatesMemoryDiskAndAwaitingPublication() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk(), store = fixture.store(disk: disk)
    let target = DetailPosterTarget(pixels: CGSize(width: 320, height: 240), screen: "phone")
    let asset = DiskPosterAsset("clear")
    let image = try bitmap()
    store.retainDetailPoster(image, for: asset, target: target)
    try await waitForDisk(disk, key: identity(asset, target).key)
    let generation = store.accessGeneration, epoch = try unwrap(await disk.detailEpoch())
    let gate = PublicationGate()
    let pending = Task { await disk.storeDetail(image, key: "late", generation: epoch, valid: { await gate.wait() }) }
    for _ in 0..<200 { if gate.entered { break }; try await Task.sleep(for: .milliseconds(10)) }
    expectTrue(gate.entered, "The write must reach its final permission check before clearing")
    expectTrue(await disk.removeAll())
    gate.release()
    expectFalse(await pending.value)
    store.retainDetailPoster(image, for: asset, target: target, generation: generation)
    expectNil(store.detailPoster(for: asset, target: target))
    expectNil(await fixture.store(disk: fixture.disk()).loadDetailPoster(for: asset, target: target))
    expectFalse(await disk.storeDetail(image, key: "after-clear", generation: epoch, valid: { true }))
    expectEqual(await disk.usage(), 0)
  }

  func testCurrentAccessAndRevisionGateFreshDiskReadersAndWrites() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk(), target = DetailPosterTarget(pixels: CGSize(width: 320, height: 240), screen: "phone")
    let asset = DiskPosterAsset("privacy")
    var access: PHAuthorizationStatus = .limited
    var revision: String? = "1000"
    let makeStore = { DetailPosterStore(disk: disk, authorization: { access }, assetRevision: { _ in revision }) }
    let store = makeStore()
    store.retainDetailPoster(try bitmap(), for: asset, target: target)
    try await waitForDisk(disk, key: identity(asset, target).key)
    access = .denied
    expectNil(await makeStore().loadDetailPoster(for: asset, target: target))
    access = .limited; revision = nil
    expectNil(await makeStore().loadDetailPoster(for: asset, target: target))
    revision = "2000"
    expectNil(await makeStore().loadDetailPoster(for: asset, target: target))
    let edited = DiskPosterAsset("privacy", revision: 2)
    expectNil(await makeStore().loadDetailPoster(for: edited, target: target))
    let epoch = try unwrap(await disk.detailEpoch())
    expectFalse(await disk.storeDetail(try bitmap(), key: "revoked-during-encode", generation: epoch, valid: { false }))
    expectNil(await disk.readDetail("revoked-during-encode").0)
  }

  func testPrefetchDiskReadDoesNotDisplaceViewedMemoryAndLowerQualityCannotReplaceHDR() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk(), target = DetailPosterTarget(pixels: CGSize(width: 320, height: 240), screen: "phone")
    let viewed = DiskPosterAsset("viewed"), neighbour = DiskPosterAsset("neighbour")
    let image = try bitmap(), cost = image.cgImage!.bytesPerRow * image.cgImage!.height
    let store = fixture.store(disk: disk, budget: cost)
    store.retainDetailPoster(image, for: viewed, target: target)
    try await waitForDisk(disk, key: identity(viewed, target).key)
    let epoch = try unwrap(await disk.detailEpoch())
    expectTrue(await disk.storeDetail(image, key: identity(neighbour, target).key, generation: epoch, valid: { true }))
    expectNotNil(await store.loadDetailPoster(for: neighbour, target: target, touch: false))
    expectNotNil(store.detailPoster(for: viewed, target: target))
    expectNil(store.detailPoster(for: neighbour, target: target))
    let hdr = try bitmap(space: CGColorSpace.extendedLinearDisplayP3, bits: 16)
    expectTrue(await disk.storeDetail(hdr, key: "quality", generation: epoch, valid: { true }))
    expectFalse(await disk.storeDetail(image, key: "quality", generation: epoch, valid: { true }))
    expectTrue(DetailThumbnailQuality(try unwrap(await disk.readDetail("quality").0)).hdr)
  }

  func testColdSpeculativeReadPreservesFileRecencyAndMalformedRecordCanBeReplaced() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk(), image = try bitmap(space: CGColorSpace.extendedLinearDisplayP3, bits: 16)
    let epoch = try unwrap(await disk.detailEpoch())
    expectTrue(await disk.storeDetail(image, key: "cold-neighbour", generation: epoch, valid: { true }))
    let url = try unwrap(FileManager.default.contentsOfDirectory(at: fixture.directory,
      includingPropertiesForKeys: nil).first { $0.pathExtension == "detail" })
    let modification = try unwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    for _ in 0..<12 {
      let fresh = fixture.disk()
      expectNotNil(await fresh.readDetail("cold-neighbour", touch: false).0)
      expectGreater(await fresh.usage(), 0)
      expectTrue(FileManager.default.fileExists(atPath: url.path))
      expectEqual(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modification)
    }
    let old = try Data(contentsOf: url)
    var corrupt = try unwrap(PropertyListSerialization.propertyList(from: old, format: nil) as? [String: Any])
    corrupt["pixels"] = Data([1, 2, 3])
    try PropertyListSerialization.data(fromPropertyList: corrupt, format: .binary, options: 0).write(to: url)
    let replacement = try bitmap()
    expectTrue(await disk.storeDetail(replacement, key: "cold-neighbour", generation: epoch, valid: { true }),
      "Malformed HDR metadata cannot block a valid replacement")
    try assertSamePixels(replacement, unwrap(await disk.readDetail("cold-neighbour").0))
    expectEqual(await disk.usage(), try Data(contentsOf: url).count)
  }

  func testLateReadCannotOverwritePublishedQualityOrByteAccounting() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let gate = ReadGate()
    let disk = ThumbnailDiskCache(directory: fixture.directory, defaults: fixture.defaults, detailReader: { url, key in
      let loaded = await ThumbnailDiskCache.loadDetail(url, key: key)
      await gate.pauseFirstRead()
      return loaded
    })
    let epoch = try unwrap(await disk.detailEpoch()), original = try bitmap()
    expectTrue(await disk.storeDetail(original, key: "overlap", generation: epoch, valid: { true }))
    let pendingRead = Task { await disk.readDetail("overlap") }
    for _ in 0..<200 { if await gate.entered { break }; try await Task.sleep(for: .milliseconds(10)) }
    expectTrue(await gate.entered)
    let hdr = try bitmap(space: CGColorSpace.extendedLinearDisplayP3, bits: 16)
    expectTrue(await disk.storeDetail(hdr, key: "overlap", generation: epoch, valid: { true }))
    let publishedBytes = await disk.usage()
    await gate.release()
    expectNil(await pendingRead.value.0, "An old decoded result cannot replace a concurrent publication")
    expectEqual(await disk.usage(), publishedBytes)
    let files = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: [.fileSizeKey])
    let actualBytes = try files.reduce(0) { try $0 + $1.resourceValues(forKeys: [.fileSizeKey]).fileSize! }
    expectEqual(await disk.usage(), actualBytes)
    expectFalse(await disk.storeDetail(original, key: "overlap", generation: epoch, valid: { true }))
    try assertSamePixels(hdr, unwrap(await disk.readDetail("overlap").0))
  }

  func testMoreThanSixViewedImagesPersistWithoutDependingOnDecodedMemory() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk(), store = fixture.store(disk: disk, budget: 1)
    let target = DetailPosterTarget(pixels: CGSize(width: 320, height: 240), screen: "phone")
    let image = try bitmap()
    let assets = (0..<12).map { DiskPosterAsset("durable-\($0)") }
    for asset in assets {
      store.retainDetailPoster(image, for: asset, target: target)
      try await waitForDisk(disk, key: identity(asset, target).key)
      expectNil(store.detailPoster(for: asset, target: target))
    }
    let fresh = fixture.store(disk: fixture.disk(), budget: 1)
    for asset in assets { expectNotNil(await fresh.loadDetailPoster(for: asset, target: target)) }
    let files = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
    expectEqual(files.filter { $0.pathExtension == "detail" }.count, 12)
  }

  func testDegradedTinyHDRDoesNotReplaceClearPixelsOrBlockTheFittedUpgrade() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let asset = DiskPosterAsset("degraded-color"), requests = DiskPosterRequests()
    let store = DetailPosterStore(disk: nil, authorization: { .authorized },
      assetRevision: { PhotoLibraryModel.revision($0) })
    let pipeline = ThumbnailPipeline(detailStore: store)
    let target = DetailPosterTarget(pixels: CGSize(width: 320, height: 240), screen: "phone")
    let clear = try bitmap(width: 640, height: 480)
    let tinySource = try bitmap(width: 16, height: 12, space: CGColorSpace.extendedLinearDisplayP3, bits: 16)
    let fittedSource = try bitmap(space: CGColorSpace.extendedLinearDisplayP3, bits: 16)
    let tiny = try unwrap(await Task.detached { tinySource.preparingForDisplay() }.value)
    let fitted = try unwrap(await Task.detached { fittedSource.preparingForDisplay() }.value)
    expectTrue(DetailThumbnailQuality(tiny).improvesColor(DetailThumbnailQuality(clear)),
      "The prepared fixture must exercise the higher-color callback path")
    expectTrue(DetailThumbnailQuality(fitted).improvesColor(DetailThumbnailQuality(clear)))
    let model = MediaPreviewModel(asset: asset, poster: clear, manager: requests, renditions: pipeline)
    model.setDisplayTarget(target); model.load()
    requests.results[1](tiny, [PHImageResultIsDegradedKey: true])
    try await Task.sleep(for: .milliseconds(100))
    expectTrue(model.image === clear, "A tiny higher-color callback cannot blur an already clear full-aspect image")
    requests.results[1](fitted, [:])
    for _ in 0..<200 {
      if let image = model.image, DetailThumbnailQuality(image).improvesColor(DetailThumbnailQuality(clear)) { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let upgraded = try unwrap(model.image)
    expectTrue(target.isSatisfied(by: upgraded, asset: asset))
    expectTrue(DetailThumbnailQuality(upgraded).improvesColor(DetailThumbnailQuality(clear)))
    requests.results[1](clear, [:])
    try await Task.sleep(for: .milliseconds(100))
    expectTrue(model.image === upgraded, "A late larger SDR callback cannot downgrade the fitted color upgrade")
    model.cancel()

    let recoveryRequests = DiskPosterRequests()
    let recovering = MediaPreviewModel(asset: asset, poster: tiny, manager: recoveryRequests)
    recovering.setDisplayTarget(target); recovering.load()
    recoveryRequests.results[1](clear, [:])
    for _ in 0..<200 {
      if let image = recovering.image, target.isSatisfied(by: image, asset: asset) { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    expectTrue(target.isSatisfied(by: try unwrap(recovering.image), asset: asset),
      "An undersized colored composition seed cannot veto an adequately sized replacement")
    recovering.cancel()
  }

  func testUndersizedHDRCannotPoisonTheFittedMemoryOrDiskIdentity() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk(), store = fixture.store(disk: disk)
    let asset = DiskPosterAsset("fitted-quality"), target = DetailPosterTarget(pixels: CGSize(width: 320, height: 240), screen: "phone")
    let tiny = try bitmap(width: 16, height: 12, space: CGColorSpace.extendedLinearDisplayP3, bits: 16)
    let fitted = try bitmap(), key = identity(asset, target).key
    store.retainDetailPoster(tiny, for: asset, target: target)
    expectNil(store.detailPoster(for: asset), "An undersized image is not inserted under a fitted identity")
    store.retainDetailPoster(fitted, for: asset, target: target)
    expectNotNil(store.detailPoster(for: asset, target: target), "A tiny HDR source cannot veto the fitted SDR preview")
    try await waitForDisk(disk, key: key)
    store.retainDetailPoster(tiny, for: asset, target: target)
    expectTrue(store.detailPoster(for: asset, target: target) === fitted)
    let fresh = fixture.store(disk: fixture.disk())
    try assertSamePixels(fitted, unwrap(await fresh.loadDetailPoster(for: asset, target: target)))
  }

  func testViewerDiskAndNativeCallbacksNeverReplaceBetterColorWithLargerSDR() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk(), target = DetailPosterTarget(pixels: CGSize(width: 320, height: 240), screen: "phone")
    let epoch = try unwrap(await disk.detailEpoch())
    for (space, bits) in [(CGColorSpace.displayP3, 8), (CGColorSpace.extendedLinearDisplayP3, 16)] {
      let asset = DiskPosterAsset("viewer-color-\(bits)")
      let better = try bitmap(space: space, bits: bits)
      expectTrue(await disk.storeDetail(better, key: identity(asset, target).key, generation: epoch, valid: { true }))
      let requests = DiskPosterRequests()
      // Retain the pipeline explicitly: production media sessions own it through
      // their library while the media model's reference is intentionally weak.
      let pipeline = ThumbnailPipeline(detailStore: fixture.store(disk: disk))
      let current = MediaPreviewModel(asset: asset, poster: try bitmap(width: 640, height: 480),
        manager: requests, renditions: pipeline)
      current.setDisplayTarget(target); current.load()
      for _ in 0..<200 {
        if current.image?.cgImage?.colorSpace?.name == space { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      expectEqual(current.image?.cgImage?.colorSpace?.name, space)
      requests.results[1](try bitmap(width: 640, height: 480), [:])
      try await Task.sleep(for: .milliseconds(100))
      expectEqual(current.image?.cgImage?.colorSpace?.name, space, "A larger late SDR response cannot replace the fitted native-color face")
      expectEqual(current.image?.isHighDynamicRange, better.isHighDynamicRange)
      current.cancel()
    }
  }

  func testCancelledDiskDeliveryDoesNotReplaceTheSessionPoster() async throws {
    let fixture = Fixture(); defer { fixture.remove() }
    let disk = fixture.disk(), asset = DiskPosterAsset("cancelled-read")
    let target = DetailPosterTarget(pixels: CGSize(width: 320, height: 240), screen: "phone")
    let epoch = try unwrap(await disk.detailEpoch())
    expectTrue(await disk.storeDetail(try bitmap(), key: identity(asset, target).key, generation: epoch, valid: { true }))
    let pipeline = ThumbnailPipeline(detailStore: fixture.store(disk: disk))
    let seed = try bitmap(width: 40, height: 30)
    let model = MediaPreviewModel(asset: asset, poster: seed, renditions: pipeline)
    model.setDisplayTarget(target)
    model.cancel()
    try await Task.sleep(for: .milliseconds(100))
    expectTrue(model.image === seed)
  }

  private func unwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    try XCTUnwrap(value, file: file, line: line)
  }
  private func expectTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value, message, file: file, line: line)
  }
  private func expectFalse(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(value, message, file: file, line: line)
  }
  private func expectNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(value, message, file: file, line: line)
  }
  private func expectNotNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNotNil(value, message, file: file, line: line)
  }
  private func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a, b, message, file: file, line: line)
  }
  private func expectGreater<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertGreaterThan(a, b, message, file: file, line: line)
  }
  private func expectAtMost<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(a, b, message, file: file, line: line)
  }
  private func identity(_ asset: PHAsset, _ target: DetailPosterTarget) -> DetailThumbnailIdentity {
    let pixels = target.fittedPixels(for: asset)
    return DetailThumbnailIdentity(assetID: asset.localIdentifier, revision: PhotoLibraryModel.revision(asset),
      width: Int(pixels.width), height: Int(pixels.height), screen: target.displayProfile ?? target.screen)
  }
  private func bitmap(width: Int = 320, height: Int = 240, space: CFString = CGColorSpace.sRGB,
    bits: Int = 8, orientation: UIImage.Orientation = .up, opaque: Bool = false) throws -> UIImage {
    let space = try unwrap(CGColorSpace(name: space))
    var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    if bits > 8 { info.insert(.floatComponents); info.insert(bits == 16 ? .byteOrder16Little : .byteOrder32Little) }
    let context = try unwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: bits,
      bytesPerRow: 0, space: space, bitmapInfo: info.rawValue))
    context.setFillColor(CGColor(colorSpace: space, components: [bits > 8 ? 3 : 0.8, 0.1, 0.3, opaque ? 1 : 0.5])!)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var cg = try unwrap(context.makeImage())
    if bits > 8 { cg = try unwrap(CGImageCreateCopyWithContentHeadroom(3, cg)) }
    return UIImage(cgImage: cg, scale: 1, orientation: orientation)
  }
  private func noiseBitmap(width: Int, height: Int) throws -> UIImage {
    var state: UInt64 = 0x123456789abcdef
    var bytes = Data(count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
      let pixels = buffer.bindMemory(to: UInt8.self)
      for index in pixels.indices { state ^= state << 13; state ^= state >> 7; state ^= state << 17; pixels[index] = UInt8(truncatingIfNeeded: state) }
    }
    let provider = try unwrap(CGDataProvider(data: bytes as CFData))
    let cg = try unwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
      decode: nil, shouldInterpolate: true, intent: .defaultIntent))
    return UIImage(cgImage: cg)
  }
  private func assertSamePixels(_ original: UIImage, _ restored: UIImage, file: StaticString = #filePath, line: UInt = #line) throws {
    let a = try unwrap(original.cgImage), b = try unwrap(restored.cgImage)
    expectEqual(original.imageOrientation, restored.imageOrientation, file: file, line: line)
    expectEqual(original.scale, restored.scale, file: file, line: line)
    expectEqual(original.isHighDynamicRange, restored.isHighDynamicRange, file: file, line: line)
    expectEqual(a.width, b.width, file: file, line: line); expectEqual(a.height, b.height, file: file, line: line)
    expectEqual(a.bitsPerComponent, b.bitsPerComponent, file: file, line: line)
    expectEqual(a.bitmapInfo, b.bitmapInfo, file: file, line: line)
    expectEqual(a.colorSpace?.name, b.colorSpace?.name, file: file, line: line)
    expectEqual(a.contentHeadroom, b.contentHeadroom, file: file, line: line)
    expectEqual(a.dataProvider?.data as Data?, b.dataProvider?.data as Data?, file: file, line: line)
  }
  private func waitForDisk(_ disk: ThumbnailDiskCache, key: String) async throws {
    for _ in 0..<200 { if await disk.readDetail(key).0 != nil { return }; try await Task.sleep(for: .milliseconds(20)) }
    XCTFail("Viewed thumbnail was not persisted")
  }
  private struct Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detail-cache-\(UUID())")
    let defaults = UserDefaults(suiteName: "detail-cache-\(UUID())")!
    func disk() -> ThumbnailDiskCache { ThumbnailDiskCache(directory: directory, defaults: defaults) }
    @MainActor func store(disk: ThumbnailDiskCache, budget: Int = 8 * 1024 * 1024) -> DetailPosterStore {
      DetailPosterStore(budget: budget, disk: disk, authorization: { .authorized }, assetRevision: { PhotoLibraryModel.revision($0) })
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
  }
}

private extension UIImage.Orientation {
  static var allCacheCases: [Self] { [.up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored] }
}
private final class DiskPosterAsset: PHAsset, @unchecked Sendable {
  let identifier: String, revision: Int
  init(_ identifier: String, revision: Int = 1) { self.identifier = identifier; self.revision = revision; super.init() }
  override var localIdentifier: String { identifier }
  override var pixelWidth: Int { 640 }
  override var pixelHeight: Int { 480 }
  override var mediaType: PHAssetMediaType { .image }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var modificationDate: Date? { Date(timeIntervalSince1970: Double(revision)) }
}

@MainActor private final class PublicationGate {
  var entered = false
  private var continuation: CheckedContinuation<Bool, Never>?
  func wait() async -> Bool {
    entered = true
    return await withCheckedContinuation { continuation = $0 }
  }
  func release() { continuation?.resume(returning: true); continuation = nil }
}

private final class DiskPosterRequests: PHImageManager, @unchecked Sendable {
  var results: [(UIImage?, [AnyHashable: Any]?) -> Void] = []
  override func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHImageRequestOptions?, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    results.append(resultHandler); return PHImageRequestID(results.count)
  }
  override func cancelImageRequest(_ requestID: PHImageRequestID) {}
}

private actor ReadGate {
  var entered = false
  private var continuation: CheckedContinuation<Void, Never>?
  func pauseFirstRead() async {
    guard !entered else { return }
    entered = true
    await withCheckedContinuation { continuation = $0 }
  }
  func release() { continuation?.resume(); continuation = nil }
}

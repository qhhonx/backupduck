import CoreImage
import AVFoundation
import Photos
import UIKit
import XCTest
@testable import BackupDuckCatalog

@MainActor final class DisplayPosterCacheTests: XCTestCase {
  func testThreeDisplayPostersSurviveRepeatedReopeningWithinTheExistingBudget() async throws {
    let pipeline = cachePipeline()
    let target = DetailPosterTarget(pixels: CGSize(width: 1320, height: 2868), screen: "phone")
    let assets = (0..<3).map { DisplayPosterAsset(identifier: "display-\($0)") }
    for _ in 0..<4 {
      for asset in assets {
        pipeline.retainDetailPoster(bitmap(width: 2400, height: 1800), for: asset, target: target)
        try await wait { pipeline.detailPoster(for: asset, target: target) != nil }
      }
      for asset in assets {
        let poster = try XCTUnwrap(pipeline.detailPoster(for: asset, target: target))
        XCTAssertEqual(poster.size.width * poster.scale, 1320, accuracy: 1)
        XCTAssertEqual(poster.size.height * poster.scale, 990, accuracy: 1)
      }
    }
    let total = assets.compactMap { pipeline.detailPoster(for: $0, target: target)?.cgImage }
      .reduce(0) { $0 + $1.bytesPerRow * $1.height }
    XCTAssertLessThanOrEqual(total, 48 * 1024 * 1024)
  }

  func testReplacementUsesRecencyAndOnlyTheMemoryByteBound() async throws {
    let pipeline = cachePipeline(budget: 4 * 1024 * 1024)
    let assets = (0..<8).map { DisplayPosterAsset(identifier: "pressure-\($0)") }
    let image = bitmap(width: 800, height: 600)
    for asset in assets.prefix(2) { pipeline.retainDetailPoster(image, for: asset) }
    XCTAssertNotNil(pipeline.detailPoster(for: assets[0]))
    pipeline.retainDetailPoster(image, for: assets[2])
    XCTAssertNotNil(pipeline.detailPoster(for: assets[2]))
    // Each image is 1.83 MiB: two fit; touching the first retains it.
    XCTAssertNotNil(pipeline.detailPoster(for: assets[0]))
    XCTAssertNil(pipeline.detailPoster(for: assets[1]))
    let roomy = cachePipeline()
    let small = bitmap(width: 400, height: 300)
    for asset in assets.prefix(6) { roomy.retainDetailPoster(small, for: asset) }
    XCTAssertNotNil(roomy.detailPoster(for: assets[0]))
    roomy.retainDetailPoster(small, for: assets[6])
    XCTAssertNotNil(roomy.detailPoster(for: assets[1]), "Image count is not a retention limit")
    XCTAssertNotNil(roomy.detailPoster(for: assets[0]))
    XCTAssertEqual(assets.filter { roomy.detailPoster(for: $0) != nil }.count, 7)
  }

  func testLargerViewportOtherScreenRevisionAndMemoryWarningAreNotCacheHits() async throws {
    let pipeline = cachePipeline()
    let asset = DisplayPosterAsset(identifier: "scope")
    let phone = DetailPosterTarget(pixels: CGSize(width: 900, height: 1600), screen: "phone")
    pipeline.retainDetailPoster(bitmap(width: 2400, height: 1800), for: asset, target: phone)
    try await wait { pipeline.detailPoster(for: asset, target: phone) != nil }
    let larger = DetailPosterTarget(pixels: CGSize(width: 2400, height: 1800), screen: "phone")
    XCTAssertNil(pipeline.detailPoster(for: asset, target: larger))
    XCTAssertNil(pipeline.detailPoster(for: asset, target: DetailPosterTarget(pixels: phone.pixels, screen: "external")))
    XCTAssertNil(pipeline.detailPoster(for: DisplayPosterAsset(identifier: "scope", revision: 2), target: phone))
    NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    XCTAssertNil(pipeline.detailPoster(for: asset, target: phone))
    pipeline.retainDetailPoster(bitmap(width: 2400, height: 1800), for: asset, target: phone)
    NotificationCenter.default.post(name: Notification.Name("LibraryThumbnailsCleared"), object: nil)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertNil(pipeline.detailPoster(for: asset, target: phone), "An obsolete thumbnail completion cannot undo clearing")
  }

  func testPrefetchedCacheHitDoesNotRefreshForegroundRecency() {
    let pipeline = cachePipeline(budget: 6 * 400 * 300 * 4)
    let assets = (0..<7).map { DisplayPosterAsset(identifier: "prefetch-\($0)") }
    let image = bitmap(width: 400, height: 300)
    for asset in assets.prefix(6) { pipeline.retainDetailPoster(image, for: asset) }
    let neighbour = MediaPreviewModel(asset: assets[0], renditions: pipeline, isCurrent: false)
    XCTAssertNotNil(neighbour.image)
    pipeline.retainDetailPoster(image, for: assets[6])
    XCTAssertNil(pipeline.detailPoster(for: assets[0]), "A speculative read does not count as viewing the page")
    XCTAssertNotNil(neighbour.image, "The session still owns pixels it is preparing to display")
  }

  func testLargerViewportUpgradesOnlyThePosterWithoutRestartingVideo() async throws {
    let previous = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = true
    defer { BackupEnvironment.usesPhotoLibrary = previous }
    let asset = DisplayPosterAsset(identifier: "resizing-video", width: 4800, height: 3600, type: .video)
    let manager = DisplayPosterRequests()
    let model = MediaPreviewModel(asset: asset, manager: manager)
    model.setDisplayTarget(DetailPosterTarget(pixels: CGSize(width: 900, height: 1600), screen: "window"))
    model.load()
    manager.results[1](bitmap(width: 2400, height: 1800), [:])
    try await wait { model.image?.size.width == 2400 && model.player != nil }
    let player = model.player, cancellations = manager.cancellations
    model.setDisplayTarget(DetailPosterTarget(pixels: CGSize(width: 3000, height: 2600), screen: "window"))
    XCTAssertEqual(manager.targets.map(\.width), [512, 2400, 3000])
    XCTAssertEqual(manager.videoRequests, 1)
    XCTAssertEqual(manager.cancellations, cancellations)
    XCTAssertTrue(model.player === player)
    XCTAssertEqual(model.image?.size.width, 2400, "The displayed pixels remain while the larger viewport prepares")
    manager.results[2](bitmap(width: 3000, height: 2250), [:])
    try await wait { model.image?.size.width == 3000 }
    XCTAssertTrue(model.player === player)
    model.cancel()
  }

  func testNativeThumbnailKeepsWideColorHDRAndOrientedFullComposition() async throws {
    let pipeline = cachePipeline()
    let target = DetailPosterTarget(pixels: CGSize(width: 900, height: 1600), screen: "color")
    for (space, bits, float) in [(CGColorSpace.displayP3, 8, false), (CGColorSpace.extendedLinearDisplayP3, 16, true)] {
      let color = try XCTUnwrap(CGColorSpace(name: space))
      let alpha = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
      let info = float ? alpha.union(.floatComponents).union(.byteOrder16Little) : alpha
      let context = try XCTUnwrap(CGContext(data: nil, width: 1800, height: 2400, bitsPerComponent: bits,
        bytesPerRow: 0, space: color, bitmapInfo: info.rawValue))
      context.setFillColor(CGColor(colorSpace: color, components: [float ? 2 : 1, 0, 0, 1])!)
      context.fill(CGRect(x: 0, y: 0, width: 1800, height: 2400))
      let raw = try XCTUnwrap(context.makeImage())
      let tagged = float ? try XCTUnwrap(CGImageCreateCopyWithContentHeadroom(2, raw)) : raw
      let image = UIImage(cgImage: tagged, scale: 1, orientation: .right)
      let asset = DisplayPosterAsset(identifier: "color-\(bits)")
      pipeline.retainDetailPoster(image, for: asset, target: target)
      try await wait { pipeline.detailPoster(for: asset, target: target) != nil }
      let poster = try XCTUnwrap(pipeline.detailPoster(for: asset, target: target))
      let cg = try XCTUnwrap(poster.cgImage)
      XCTAssertEqual(poster.imageOrientation, image.imageOrientation)
      XCTAssertEqual(poster.size.width / poster.size.height, 4 / 3, accuracy: 0.005)
      XCTAssertEqual(poster.isHighDynamicRange, image.isHighDynamicRange)
      XCTAssertEqual(cg.colorSpace?.name, image.cgImage?.colorSpace?.name)
      XCTAssertEqual(cg.bitsPerComponent, bits)
      XCTAssertEqual(cg.contentHeadroom, tagged.contentHeadroom)
      if float {
        let data = try XCTUnwrap(cg.dataProvider?.data) as Data
        let red = data.withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertGreaterThan(Float(Float16(bitPattern: red)), 1.5, "HDR values above SDR white survive resizing")
      }
    }
  }

  func testEncodedHDRRetainsItsNativeColorAndDynamicRange() async throws {
    let color = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
      .union(.floatComponents).union(.byteOrder16Little)
    let context = try XCTUnwrap(CGContext(data: nil, width: 2400, height: 1800, bitsPerComponent: 16,
      bytesPerRow: 0, space: color, bitmapInfo: info.rawValue))
    context.setFillColor(CGColor(colorSpace: color, components: [2, 0, 0, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
    let raw = try XCTUnwrap(context.makeImage())
    let tagged = try XCTUnwrap(CGImageCreateCopyWithContentHeadroom(2, raw))
    let pq = try XCTUnwrap(CGColorSpace(name: CGColorSpace.itur_2100_PQ))
    let data = try XCTUnwrap(CIContext().pngRepresentation(of: CIImage(cgImage: tagged),
      format: .RGBA16, colorSpace: pq, options: [:]))
    var configuration = UIImageReader.Configuration()
    configuration.prefersHighDynamicRange = true
    let decoded = await UIImageReader(configuration: configuration).image(data: data as Data)
    let image = try XCTUnwrap(decoded)
    XCTAssertTrue(image.isHighDynamicRange, "The encoded fixture must actually carry HDR")
    let source = try XCTUnwrap(image.cgImage)
    let pipeline = cachePipeline()
    let asset = DisplayPosterAsset(identifier: "iso-hdr")
    let target = DetailPosterTarget(pixels: CGSize(width: 900, height: 1600), screen: "hdr")
    pipeline.retainDetailPoster(bitmap(width: 900, height: 675), for: asset, target: target)
    XCTAssertFalse(try XCTUnwrap(pipeline.detailPoster(for: asset, target: target)).isHighDynamicRange)
    // A larger SDR source is still preparing when a better HDR source arrives.
    // Equal fitted dimensions must not preserve the old SDR face or its task.
    pipeline.retainDetailPoster(bitmap(width: 2400, height: 1800), for: asset, target: target)
    pipeline.retainDetailPoster(image, for: asset, target: target)
    try await wait { pipeline.detailPoster(for: asset, target: target)?.isHighDynamicRange == true }
    try await Task.sleep(for: .milliseconds(100))
    let retained = try XCTUnwrap(pipeline.detailPoster(for: asset, target: target))
    let cg = try XCTUnwrap(retained.cgImage)
    XCTAssertTrue(retained.isHighDynamicRange)
    XCTAssertEqual(cg.colorSpace?.name, source.colorSpace?.name)
    XCTAssertEqual(cg.bitsPerComponent, source.bitsPerComponent)
    XCTAssertEqual(cg.contentHeadroom, source.contentHeadroom)
    XCTAssertEqual(retained.size.width, 900, accuracy: 1)
    XCTAssertEqual(retained.size.height, 675, accuracy: 1)
    print("DISPLAY_POSTER_HDR", image.size, source.bitsPerPixel, source.colorSpace?.name as Any,
      source.contentHeadroom, retained.size, retained === image)
  }

  private func cachePipeline(budget: Int = 48 * 1024 * 1024) -> ThumbnailPipeline {
    ThumbnailPipeline(detailStore: DetailPosterStore(budget: budget, disk: nil, authorization: { .authorized },
      assetRevision: { PhotoLibraryModel.revision($0) }))
  }

  private func bitmap(width: CGFloat, height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
      UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
  }
  private func wait(_ condition: () -> Bool) async throws {
    for _ in 0..<100 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
    XCTFail("Display poster did not become available")
  }
}

private final class DisplayPosterAsset: PHAsset, @unchecked Sendable {
  let identifier: String
  let revision: Int
  let width: Int, height: Int, type: PHAssetMediaType
  init(identifier: String, revision: Int = 1, width: Int = 2400, height: Int = 1800, type: PHAssetMediaType = .image) {
    self.identifier = identifier; self.revision = revision; self.width = width; self.height = height; self.type = type; super.init()
  }
  override var localIdentifier: String { identifier }
  override var pixelWidth: Int { width }
  override var pixelHeight: Int { height }
  override var mediaType: PHAssetMediaType { type }
  override var mediaSubtypes: PHAssetMediaSubtype { [] }
  override var burstIdentifier: String? { nil }
  override var creationDate: Date? { Date(timeIntervalSince1970: 1) }
  override var modificationDate: Date? { Date(timeIntervalSince1970: Double(revision)) }
}

private final class DisplayPosterRequests: PHImageManager, @unchecked Sendable {
  var targets: [CGSize] = []
  var results: [(UIImage?, [AnyHashable: Any]?) -> Void] = []
  var videoRequests = 0, cancellations = 0
  override func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
    options: PHImageRequestOptions?, resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    targets.append(targetSize); results.append(resultHandler); return PHImageRequestID(results.count)
  }
  override func requestPlayerItem(forVideo asset: PHAsset, options: PHVideoRequestOptions?,
    resultHandler: @escaping (AVPlayerItem?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
    videoRequests += 1; resultHandler(AVPlayerItem(asset: AVMutableComposition()), [:]); return 100
  }
  override func cancelImageRequest(_ requestID: PHImageRequestID) { cancellations += 1 }
}

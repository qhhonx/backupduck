import Photos
import UIKit
import Nuke
@testable import BackupDuck

/// Test-only Photos bridge: use Nuke's direct image resource, not an artificial
/// UIImage -> JPEG -> UIImage conversion on every cold request.
@MainActor final class NukeBenchmarkAdapter {
  let manager: BenchmarkImageManager
  let tuned: Bool
  private var pipeline: ImagePipeline
  private var disk: DataCache?
  private var directory: URL?
  private var sequence: Int32 = 0
  private var tasks: [Int32:ImageTask] = [:]

  init(manager:BenchmarkImageManager,tuned:Bool) {
    self.manager = manager; self.tuned = tuned
    pipeline = Self.makePipeline(tuned:tuned,disk:nil)
  }
  private static func makePipeline(tuned:Bool,disk:DataCache?) -> ImagePipeline {
    var config = ImagePipeline.Configuration()
    config.imageCache = ImageCache(costLimit:64*1024*1024,countLimit:8192)
    config.dataCache = disk
    // Explicitly persist Photos renditions. Default original-data caching cannot
    // persist a UIImage-only input. Verify actual reopened-disk hits in the run.
    config.dataCachePolicy = .storeEncodedImages
    config.makeImageEncoder = { _ in ImageEncoders.ImageIO(type:.jpeg,compressionRatio:0.86) }
    if tuned {
      config.dataLoadingQueue.maxConcurrentOperationCount = 24
      config.imageEncodingQueue.maxConcurrentOperationCount = 6
      config.isUsingPrepareForDisplay = true
    }
    return ImagePipeline(configuration:config)
  }
  func enableDisk(directory:URL) throws {
    self.directory = directory
    disk = try DataCache(path:directory); disk?.sizeLimit = 256*1024*1024
    pipeline.invalidate(); pipeline = Self.makePipeline(tuned:tuned,disk:disk)
  }
  func reopenDisk() throws {
    // Do not mistake DataCache's in-memory write staging for a disk-cache hit.
    disk?.flush()
    if let directory { try enableDisk(directory:directory) }
  }
  func clearMemory() { pipeline.cache.removeAll(caches:.memory) }
  func cancel(_ id:Int32) { tasks.removeValue(forKey:id)?.cancel() }

  func request(_ asset:PHAsset,side:CGFloat,prefetch:Bool = false,completion:@escaping (UIImage?,Bool)->Void) -> Int32 {
    let target = min(1024,max(64,ceil(side/64)*64))
    let key = "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))|\(Int(target))|\(PHImageContentMode.aspectFill.rawValue)"
    let manager = manager
    let request = ImageRequest(id:key,image:{
      let bridge = await PhotosImageAwaiter(manager:manager,asset:asset,side:target)
      return try await withTaskCancellationHandler {
        try await bridge.image()
      } onCancel: {
        Task { @MainActor in bridge.cancel() }
      }
    }, priority:prefetch ? .low : .high)
    if let cached = pipeline.cache.cachedImage(for:request,caches:.memory) {
      completion(cached.image,false); return PHInvalidImageRequestID
    }
    sequence += 1; let id = sequence
    let task = pipeline.loadImage(with:request) { [weak self] result in
      self?.tasks.removeValue(forKey:id)
      switch result {
      case .success(let response): completion(response.image,false)
      case .failure: completion(nil,false)
      }
    }
    tasks[id] = task; return id
  }
}

@MainActor private final class PhotosImageAwaiter {
  let manager:BenchmarkImageManager, asset:PHAsset, side:CGFloat
  var continuation:CheckedContinuation<ImageContainer,Error>?
  var requestID:Int32?, cancelled = false
  init(manager:BenchmarkImageManager,asset:PHAsset,side:CGFloat) {
    self.manager = manager; self.asset = asset; self.side = side
  }
  func image() async throws -> ImageContainer {
    if cancelled || Task.isCancelled { throw CancellationError() }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let options = PHImageRequestOptions(); options.deliveryMode = .highQualityFormat
      requestID = manager.requestImage(for:asset,targetSize:CGSize(width:side,height:side),contentMode:.aspectFill,options:options) { [weak self] image,_ in
        guard let self,let pending = self.continuation else { return }
        self.continuation = nil; self.requestID = nil
        if let image { pending.resume(returning:ImageContainer(image:image)) }
        else { pending.resume(throwing:CancellationError()) }
      }
    }
  }
  func cancel() {
    cancelled = true
    if let requestID { manager.cancelImageRequest(requestID) }
    requestID = nil
    let pending = continuation; continuation = nil
    pending?.resume(throwing:CancellationError())
  }
}

import AVKit
import Combine
import ImageIO
import MapKit
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// Browsing allows PhotoKit to resolve cloud previews by default. This does not
/// register preparation or backup work and ignores obsolete app consent values.
@MainActor final class PreviewNetworkPolicy: ObservableObject {
  static let shared = PreviewNetworkPolicy()
  @Published private(set) var choice = "allow"
  var allowed: Bool { true }
  init(defaults: UserDefaults = .standard) {}
}

/// Synthetic media adapters supply pixels and metadata without calling PhotoKit.
/// Production assets continue through the native resource pipeline.
protocol PreviewSample {
  var previewImage: LibraryImage? { get }
  var previewDownloadState: PreviewDownloadState { get }
  var previewFilename: String { get }
  var previewMetadata: [(String, String)] { get }
}

enum PreviewDownloadState { case available, downloading, failed }
/// A poster remains visible while its full rendition is prepared. Only a
/// reported download fraction is determinate; zero is a valid observation.
enum MediaPreviewIndicatorState: Equatable {
  case hidden, indeterminate, progress(Double), cloud, failed
}
extension PreviewSample {
  var previewDownloadState: PreviewDownloadState { .available }
}

@MainActor final class MediaPreviewModel: ObservableObject {
  @Published private(set) var asset: PHAsset
  @Published private(set) var image: LibraryImage?
  @Published private(set) var livePhoto: PHLivePhoto?
  @Published private(set) var player: AVPlayer?
  @Published private(set) var loading = false
  @Published private(set) var cloudNeeded = false
  @Published private(set) var failure = false
  @Published private(set) var progress: Double?
  var indicatorState: MediaPreviewIndicatorState {
    if failure { return .failed }
    if cloudNeeded { return .cloud }
    guard loading else { return .hidden }
    if let progress, progress.isFinite { return .progress(min(1, max(0, progress))) }
    return image == nil ? .indeterminate : .hidden
  }
  @Published private(set) var metadata: [(String, String)] = []
  @Published private(set) var burstIndex = 0
  @Published private(set) var burstCount = 0
  private var burstFetch: PHFetchResult<PHAsset>?
  @Published private(set) var metadataLoading = false
  @Published private(set) var metadataUnavailable = false
  private var requests: [PHImageRequestID] = []
  private var metadataRequest: PHAssetResourceDataRequestID?
  private var metadataGeneration = UUID()
  private(set) var metadataRequested = false
  private var generation = UUID()
  // Quality belongs to the delivered pixels, not their nominal dimensions.
  private var posterQuality = 0
  private var cloudPoster = false
  private var promptForCloud = true
  private var networkRequested = false
  private let manager: PHImageManager?
  private weak var renditions: ThumbnailPipeline?
  #if os(macOS)
  @Published private(set) var macLocalPosterResolved = false
  /// A crop is usable after the local attempt finishes, including an offline
  /// failure. Network requests never gate the opening flight.
  var macEntryPosterReady: Bool {
    guard let image else { return false }
    let aspect = CGFloat(max(1, asset.pixelWidth)) / CGFloat(max(1, asset.pixelHeight))
    let fullAspect = abs(log((image.size.width / max(1, image.size.height)) / aspect)) < 0.02
    return fullAspect || macLocalPosterResolved || failure || cloudNeeded
  }
  private var macDetailTarget: MacDetailPosterTarget?
  private var macDetailRead: Task<Void, Never>?
  private var macDetailGeneration = 0
  private var macPosterPixelsRequested: CGFloat = 0
  func setMacDisplayTarget(_ target: MacDetailPosterTarget) {
    guard macDetailTarget != target else { return }
    macDetailTarget = target
    readMacDetailPoster()
    if promptForCloud, posterQuality >= 2, let image {
      MacDetailPosterCache.shared.retain(image, asset: asset, target: target, generation: macDetailGeneration)
    }
    let fitted = target.fitted(for: asset)
    let edge = max(fitted.width, fitted.height)
    if promptForCloud, macPosterPixelsRequested > 0, edge > macPosterPixelsRequested, let manager {
      macPosterPixelsRequested = edge
      let expected = generation, options = PHImageRequestOptions()
      options.isNetworkAccessAllowed = PreviewNetworkPolicy.shared.allowed
      options.deliveryMode = .opportunistic; options.resizeMode = .exact
      requests.append(manager.requestImage(for: asset, targetSize: CGSize(width: edge, height: edge),
        contentMode: .aspectFit, options: options) { [weak self] value, info in
        Task { @MainActor in
          guard let self, self.generation == expected, let value else { return }
          self.preparePoster(value, expected: expected, quality: info?[PHImageResultIsDegradedKey] as? Bool == true ? 1 : 2)
        }
      })
    }
  }
  private func readMacDetailPoster() {
    macDetailRead?.cancel()
    guard let target = macDetailTarget else { return }
    let expected = generation, asset = asset
    macDetailRead = Task { [weak self] in
      let image = await MacDetailPosterCache.shared.load(asset: asset, target: target)
      guard let self, !Task.isCancelled, self.generation == expected,
        self.asset.localIdentifier == asset.localIdentifier, self.macDetailTarget == target,
        let image else { return }
      self.adoptPoster(image, retain: false, quality: 2)
    }
  }
  #endif
  #if os(iOS)
  private var detailCacheGeneration: Int?
  private var displayTarget: DetailPosterTarget?
  private var posterPixelsRequested: CGFloat = 0
  private var detailRead: Task<Void, Never>?
  private func readDetailPoster() {
    detailRead?.cancel()
    guard let target = displayTarget, let renditions else { return }
    let expected = generation, asset = asset, viewed = promptForCloud
    detailRead = Task { [weak self] in
      let retained = await renditions.loadDetailPoster(for: asset, target: target, touch: viewed)
      guard let self, !Task.isCancelled, self.generation == expected,
        self.asset.localIdentifier == asset.localIdentifier, self.displayTarget == target,
        let retained else { return }
      self.adoptPoster(retained, retain: false, quality: 2)
    }
  }
  func setDisplayTarget(_ target: DetailPosterTarget) {
    guard displayTarget != target else { return }
    displayTarget = target
    readDetailPoster()
    if let retained = renditions?.detailPoster(for: asset, target: target, touch: promptForCloud) { adoptPoster(retained, retain: false, quality: 2) }
    if let image, promptForCloud, posterQuality >= 2, let detailCacheGeneration {
      renditions?.retainDetailPoster(image, for: asset, target: target, generation: detailCacheGeneration)
    }
    let pixels = target.fittedPixels(for: asset)
    let edge = min(4096, max(2400, pixels.width, pixels.height))
    // A larger window can need more pixels without restarting a playing video
    // or Live Photo. Keep the displayed face while only its poster is upgraded.
    if promptForCloud, posterPixelsRequested > 0, edge > posterPixelsRequested, let manager {
      posterPixelsRequested = edge
      let expected = generation, options = PHImageRequestOptions()
      options.isNetworkAccessAllowed = promptForCloud && PreviewNetworkPolicy.shared.allowed
      options.deliveryMode = .opportunistic; options.resizeMode = .exact
      requests.append(manager.requestImage(for: asset, targetSize: CGSize(width: edge, height: edge),
        contentMode: .aspectFit, options: options) { [weak self] value, info in
        Task { @MainActor in
          guard let self, self.generation == expected, let value else { return }
          self.preparePoster(value, expected: expected, quality: info?[PHImageResultIsDegradedKey] as? Bool == true ? 1 : 2)
        }
      })
    }
  }
  #endif
  init(asset: PHAsset, poster: LibraryImage? = nil, manager: PHImageManager? = nil,
    renditions: ThumbnailPipeline? = nil, isCurrent: Bool = true) {
    self.asset = asset; image = poster; self.manager = BackupEnvironment.usesPhotoLibrary ? (manager ?? .default()) : nil
    self.renditions = renditions
    promptForCloud = isCurrent
    #if os(macOS)
    if let retained = MacDetailPosterCache.shared.memoryPoster(asset: asset) { adoptPoster(retained, retain: false, quality: 2) }
    #endif
    #if os(iOS)
    detailCacheGeneration = renditions?.detailAccessGeneration
    if let retained = renditions?.detailPoster(for: asset, touch: isCurrent) { adoptPoster(retained, retain: false, quality: 2) }
    #endif
  }
  private func adoptPoster(_ incoming: LibraryImage, retain: Bool = true, quality: Int = 0) {
    if let current = image {
      #if os(iOS)
      let edge: (LibraryImage) -> CGFloat = { max($0.size.width,$0.size.height) * $0.scale }
      #else
      let edge: (LibraryImage) -> CGFloat = { image in
        CGFloat(image.representations.map { max($0.pixelsWide,$0.pixelsHigh) }.max() ?? Int(max(image.size.width,image.size.height)))
      }
      #endif
      // A full-aspect image replaces a centre-cropped grid poster even when
      // smaller: the crop cannot show the photo's sides, and leaving it shows
      // a small square with empty bands (worst for wide panoramas).
      let mediaAspect = CGFloat(max(1, asset.pixelWidth)) / CGFloat(max(1, asset.pixelHeight))
      let fullAspect: (LibraryImage) -> Bool = {
        abs(log(($0.size.width / max(1, $0.size.height)) / mediaAspect)) < 0.02
      }
      if fullAspect(current), quality < posterQuality { return }
      #if os(iOS)
      // Once the full composition is visible, a late cropped cover cannot
      // replace it, even when that cover has a larger nominal pixel edge.
      if fullAspect(current), !fullAspect(incoming) { return }
      let incomingFits = displayTarget?.isSatisfied(by: incoming, asset: asset) == true
      let currentFits = displayTarget?.isSatisfied(by: current, asset: asset) == true
      // A small full-aspect seed can establish composition, but its color does
      // not veto a later rendition that actually fills the display target.
      if quality <= posterQuality, fullAspect(current), fullAspect(incoming), !(incomingFits && !currentFits),
        DetailThumbnailQuality(current).improvesColor(DetailThumbnailQuality(incoming)) { return }
      let colorUpgrade = fullAspect(incoming)
        && DetailThumbnailQuality(incoming).improvesColor(DetailThumbnailQuality(current))
        && (incomingFits || edge(incoming) >= edge(current))
      #else
      if fullAspect(current), !fullAspect(incoming) { return }
      let oldBitmap = current.cgImage(forProposedRect: nil, context: nil, hints: nil)
      let newBitmap = incoming.cgImage(forProposedRect: nil, context: nil, hints: nil)
      let fitted = macDetailTarget?.fitted(for: asset)
      if quality <= posterQuality, fullAspect(current), fullAspect(incoming), let oldBitmap, let newBitmap,
        MacDetailBitmap.keepsCurrentColor(oldBitmap, incoming: newBitmap, fitted: fitted) { return }
      let incomingFits = newBitmap.map { bitmap in
        fitted.map { CGFloat(bitmap.width) >= $0.width - 1 && CGFloat(bitmap.height) >= $0.height - 1 } ?? false
      } ?? false
      let colorUpgrade = fullAspect(incoming) && (incomingFits || edge(incoming) >= edge(current))
        && (oldBitmap.flatMap { old in newBitmap.map { MacDetailBitmap.improvesColor($0, over: old) } } ?? false)
      #endif
      if quality <= posterQuality, !colorUpgrade, !(fullAspect(incoming) && !fullAspect(current)), edge(incoming) < edge(current) { return }
    }
    image = incoming
    posterQuality = quality
    #if os(macOS)
    if retain, quality >= 2, promptForCloud, let target = macDetailTarget {
      MacDetailPosterCache.shared.retain(incoming, asset: asset, target: target, generation: macDetailGeneration)
    }
    #endif
    #if os(iOS)
    if retain, quality >= 2, promptForCloud, let detailCacheGeneration {
      renditions?.retainDetailPoster(incoming, for: asset, target: displayTarget, generation: detailCacheGeneration)
    }
    #endif
  }
  private func preparePoster(_ incoming: LibraryImage, expected: UUID, quality: Int = 1,
    completion: (@MainActor (Bool) -> Void)? = nil) {
    #if os(iOS)
    // UIKit prepares the bitmap away from the main thread. Keep the displayed
    // pixels until preparation finishes, and reject obsolete decode callbacks.
    incoming.prepareForDisplay { [weak self] prepared in
      Task { @MainActor in
        guard let self, self.generation == expected else { return }
        if let prepared { self.adoptPoster(prepared, quality: quality) }
        completion?(prepared != nil)
      }
    }
    #else
    adoptPoster(incoming, quality: quality); completion?(true)
    #endif
  }
  var kind: String {
    asset.burstIdentifier != nil ? "burst" : asset.mediaType == .video ? "video"
      : asset.mediaSubtypes.contains(.photoLive) ? "motion" : "photo"
  }
  var filename: String {
    if let sample = asset as? any PreviewSample { return sample.previewFilename }
    guard BackupEnvironment.usesPhotoLibrary else { return "" }
    let resources = PHAssetResource.assetResources(for: asset)
    return resources.first(where: { $0.type == .photo || $0.type == .video })?.originalFilename ?? resources.first?.originalFilename ?? ""
  }
  func load(_ next: PHAsset? = nil, pixels: CGFloat = 2400, promptForCloud: Bool = true) {
    cancel()
    #if os(macOS)
    macLocalPosterResolved = false
    macDetailGeneration = MacDetailPosterCache.shared.accessGeneration
    #endif
    #if os(iOS)
    detailCacheGeneration = renditions?.detailAccessGeneration
    #endif
    self.promptForCloud = promptForCloud
    if let next, next.localIdentifier != asset.localIdentifier { asset = next; image = nil; posterQuality = 0 }
    #if os(macOS)
    readMacDetailPoster()
    #endif
    if let sample = asset as? any PreviewSample {
      image = sample.previewImage
      loading = sample.previewDownloadState == .downloading
      failure = sample.previewDownloadState == .failed || image == nil
      cloudNeeded = false; progress = nil
      #if os(macOS)
      macLocalPosterResolved = true
      #endif
      return
    }
    guard BackupEnvironment.usesPhotoLibrary, let manager else { loading = false; failure = true; return }
    if let burst = asset.burstIdentifier {
      let options = photoLibraryFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
      burstFetch = PHAsset.fetchAssets(withBurstIdentifier: burst, options: options)
      burstCount = burstFetch?.count ?? 0
      let index = burstFetch?.index(of: asset) ?? NSNotFound
      burstIndex = index == NSNotFound ? 0 : index
    } else { burstFetch = nil; burstCount = 0; burstIndex = 0 }
    livePhoto = nil; player = nil; metadata = []
    cloudPoster = false; cloudNeeded = false; failure = false; loading = true; progress = nil
    let expected = generation
    let network = promptForCloud && PreviewNetworkPolicy.shared.allowed
    networkRequested = network
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = network
    options.deliveryMode = .opportunistic; options.resizeMode = .exact
    if asset.mediaType != .video && !asset.mediaSubtypes.contains(.photoLive) {
      options.progressHandler = { [weak self] value, _, _, _ in
        Task { @MainActor in guard self?.generation == expected else { return }; self?.progress = value }
      }
    }
    // The device keeps a small full-aspect rendition even for iCloud-only
    // originals. Request it locally first: the large request below can wait on
    // a download, and until then the only pixels were the grid's square crop.
    let local = PHImageRequestOptions()
    local.isNetworkAccessAllowed = false
    local.deliveryMode = .opportunistic; local.resizeMode = .fast
    requests.append(manager.requestImage(for: asset, targetSize: CGSize(width: 512, height: 512),
      contentMode: .aspectFit, options: local) { [weak self] value, info in
      Task { @MainActor in
        guard let self, self.generation == expected else { return }
        if let value { self.preparePoster(value, expected: expected) }
        #if os(macOS)
        // A terminal local miss is a real readiness event for the retained
        // source crop. Do not keep waiting for a network-backed full image.
        if info?[PHImageResultIsDegradedKey] as? Bool != true { self.macLocalPosterResolved = true }
        #endif
      }
    })
    var edge = min(4096, max(1600, pixels))
    #if os(macOS)
    if promptForCloud, let target = macDetailTarget {
      let fitted = target.fitted(for: asset)
      edge = min(4096, max(edge, fitted.width, fitted.height))
    }
    macPosterPixelsRequested = edge
    #endif
    #if os(iOS)
    if promptForCloud, let target = displayTarget {
      let fitted = target.fittedPixels(for: asset)
      edge = min(4096, max(edge, fitted.width, fitted.height))
    }
    posterPixelsRequested = edge
    readDetailPoster()
    #endif
    let size = CGSize(width: edge, height: edge)
    requests.append(manager.requestImage(for: asset, targetSize: size,
      contentMode: .aspectFit, options: options) { [weak self] value, info in
      Task { @MainActor in
        guard let self, self.generation == expected else { return }
        if info?[PHImageResultIsInCloudKey] as? Bool == true { self.cloudPoster = true }
        let final = info?[PHImageResultIsDegradedKey] as? Bool != true
          && self.asset.mediaType != .video && !self.asset.mediaSubtypes.contains(.photoLive)
        if let value {
          self.preparePoster(value, expected: expected, quality: info?[PHImageResultIsDegradedKey] as? Bool == true ? 1 : 2) { [weak self] available in
            if final { self?.finish(available, info: info) }
          }
        } else if final { self.finish(false, info: info) }
      }
    })
    if asset.mediaType == .video {
      let options = PHVideoRequestOptions(); options.isNetworkAccessAllowed = network
      options.progressHandler = { [weak self] value, _, _, _ in Task { @MainActor in
        guard self?.generation == expected else { return }; self?.progress = value
      } }
      requests.append(manager.requestPlayerItem(forVideo: asset, options: options) { [weak self] item, info in
        Task { @MainActor in
          guard let self, self.generation == expected else { return }
          self.player = item.map(AVPlayer.init(playerItem:)); self.finish(item != nil, info: info)
        }
      })
    } else if asset.mediaSubtypes.contains(.photoLive) {
      requestLivePhoto(size: size, expected: expected, networkAllowed: false, mayDownload: network)
    }
  }
  private func requestLivePhoto(size: CGSize, expected: UUID, networkAllowed: Bool, mayDownload: Bool) {
    guard let manager else { return }
    // PhotoKit reports progress for assembling entirely local Live Photos too.
    // Only a confirmed cloud fallback owns download feedback; the still poster
    // remains visible while local motion is prepared.
    let options = PHLivePhotoRequestOptions()
    options.isNetworkAccessAllowed = networkAllowed
    options.deliveryMode = .highQualityFormat
    if networkAllowed {
      options.progressHandler = { [weak self] value, _, _, _ in Task { @MainActor in
        guard self?.generation == expected else { return }; self?.progress = value
      } }
    }
    requests.append(manager.requestLivePhoto(for: asset, targetSize: size,
      contentMode: .aspectFit, options: options) { [weak self] value, info in
      Task { @MainActor in
        guard let self, self.generation == expected else { return }
        let error = info?[PHImageErrorKey] as? NSError
        let needsNetwork = info?[PHImageResultIsInCloudKey] as? Bool == true
          || (error?.domain == PHPhotosErrorDomain && error?.code == PHPhotosError.Code.networkAccessRequired.rawValue)
        if value == nil, needsNetwork {
          if !networkAllowed, mayDownload {
            self.requestLivePhoto(size: size, expected: expected, networkAllowed: true, mayDownload: false)
          } else { self.finish(false, info: info) }
          return
        }
        guard info?[PHImageResultIsDegradedKey] as? Bool != true else { return }
        self.livePhoto = value; self.finish(value != nil, info: info)
      }
    })
  }
  private func finish(_ available: Bool, info: [AnyHashable: Any]?) {
    loading = false
    let error = (info?[PHImageErrorKey] ?? info?[PHLivePhotoInfoErrorKey]) as? NSError
    let networkRequired = error?.domain == PHPhotosErrorDomain && error?.code == PHPhotosError.Code.networkAccessRequired.rawValue
    cloudNeeded = !available && (info?[PHImageResultIsInCloudKey] as? Bool == true || cloudPoster || networkRequired)
    failure = !available
    if networkRequested { cloudNeeded = false }
  }
  func activate() {
    if !networkRequested { load() }
    promptForCloud = true
    #if os(iOS)
    // Prefetched neighbours keep their pixels in the session. Only a viewed
    // page enters the cross-session cache so local preparation cannot evict it.
    if let image, posterQuality >= 2, let detailCacheGeneration {
      renditions?.retainDetailPoster(image, for: asset, target: displayTarget, generation: detailCacheGeneration)
    }
    #endif
  }
  func deactivate() { promptForCloud = false; player?.pause() }
  func moveBurst(_ direction: Int) {
    guard let asset = burstNeighbour(direction) else { return }; load(asset)
  }
  func burstNeighbour(_ direction: Int) -> PHAsset? {
    let index = burstIndex + direction
    guard let burstFetch, (0..<burstFetch.count).contains(index) else { return nil }
    return burstFetch.object(at: index)
  }
  func cancel() {
    #if os(macOS)
    macDetailRead?.cancel(); macDetailRead = nil
    macPosterPixelsRequested = 0
    #endif
    #if os(iOS)
    posterPixelsRequested = 0
    detailRead?.cancel(); detailRead = nil
    #endif
    generation = UUID()
    metadataGeneration = UUID()
    requests.forEach { manager?.cancelImageRequest($0) }; requests = []
    if let metadataRequest { PHAssetResourceManager.default().cancelDataRequest(metadataRequest) }; metadataRequest = nil
    player?.pause(); loading = false; metadataLoading = false
  }
  func cancelMetadata() {
    metadataGeneration = UUID()
    metadataRequested = false
    if let metadataRequest { PHAssetResourceManager.default().cancelDataRequest(metadataRequest) }
    metadataRequest = nil; metadataLoading = false
  }
  func loadMetadata() {
    if let sample = asset as? any PreviewSample {
      metadataRequested = true; metadata = sample.previewMetadata
      return
    }
    guard BackupEnvironment.usesPhotoLibrary else { return }
    metadataRequested = true
    metadataGeneration = UUID()
    let expectedMetadata = metadataGeneration
    let expected = generation
    metadata = []; metadataUnavailable = false
    // Basic metadata needs no download. EXIF is read on demand, never for grids.
    if asset.mediaType == .video {
      if let url = (player?.currentItem?.asset as? AVURLAsset)?.url,
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        metadata = [("preview_file_size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))]
      }
      return
    }
    if let metadataRequest { PHAssetResourceManager.default().cancelDataRequest(metadataRequest) }
    guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) else { return }
    let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = PreviewNetworkPolicy.shared.allowed
    metadataLoading = true
    let sizeKey = asset.mediaSubtypes.contains(.photoLive) ? "preview_still_file_size" : "preview_file_size"
    let bytes = PreviewMetadataBytes()
    metadataRequest = PHAssetResourceManager.default().requestData(for: resource, options: options,
      dataReceivedHandler: { bytes.append($0) }, completionHandler: { [weak self] error in
      if let error {
        Task { @MainActor in
          guard let self, self.generation == expected, self.metadataGeneration == expectedMetadata else { return }
          self.metadataLoading = false; self.metadataUnavailable = true; self.metadataRequest = nil
        }
        return
      }
      let (data, count) = bytes.snapshot()
      var fields = [(String, String)]()
      fields.append(("preview_format", UTType(resource.uniformTypeIdentifier)?.localizedDescription ?? resource.uniformTypeIdentifier))
      fields.append((sizeKey, ByteCountFormatter.string(fromByteCount: count, countStyle: .file)))
      let source = CGImageSourceCreateIncremental(nil)
      CGImageSourceUpdateData(source, data as CFData, count == Int64(data.count))
      if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        if let model = tiff[kCGImagePropertyTIFFModel as String] as? String { fields.append(("preview_camera", model)) }
        if let lens = exif[kCGImagePropertyExifLensModel as String] as? String { fields.append(("preview_lens", lens)) }
        if let f = exif[kCGImagePropertyExifFNumber as String] as? NSNumber { fields.append(("preview_aperture", "ƒ/\(f)")) }
        if let exposure = exif[kCGImagePropertyExifExposureTime as String] as? NSNumber {
          let seconds = exposure.doubleValue
          if seconds.isFinite && seconds >= 0.000000001 && seconds <= 86400 {
            fields.append(("preview_exposure", seconds < 1 ? "1/\(Int((1 / seconds).rounded())) s" : "\(seconds) s"))
          }
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first { fields.append(("preview_iso", iso.stringValue)) }
      }
      Task { @MainActor in guard self?.generation == expected, self?.metadataGeneration == expectedMetadata else { return }; self?.metadata = fields; self?.metadataLoading = false; self?.metadataRequest = nil }
    })
  }
}

/// Bounded media neighbours share their poster and load state with the pager.
/// Opening a neighbouring page for animation does not ask for cloud consent.
@MainActor final class MediaPreviewSession: ObservableObject {
  let library: PhotoLibraryModel
  // A review has a stable browsing batch. Deselecting an item must not move
  // the current page or prevent the user from selecting it again.
  private let reviewAssets: [PHAsset]?
  private let reviewIndices: [String: Int]
  var count: Int { reviewAssets?.count ?? library.loaded }
  func asset(at index: Int) -> PHAsset? {
    if let reviewAssets { return reviewAssets.indices.contains(index) ? reviewAssets[index] : nil }
    #if os(iOS)
    // The grid stores newest first; horizontal browsing runs oldest to newest.
    return library.asset(at: count - 1 - index)
    #else
    return library.asset(at: index)
    #endif
  }
  func index(of asset: PHAsset) -> Int? {
    if reviewAssets != nil { return reviewIndices[asset.localIdentifier] }
    #if os(iOS)
    return library.previewIndex(of: asset).map { count - 1 - $0 }
    #else
    return library.previewIndex(of: asset)
    #endif
  }
  @Published private(set) var current: MediaPreviewModel
  @Published private(set) var collectionRevision = 0
  @Published var zoomed = false
  @Published var paging = false
  @Published var fitRevision = 0
  func fitMedia() { zoomed = false; fitRevision &+= 1 }
  private var models: [String: MediaPreviewModel] = [:]
  #if os(macOS)
  private var macDisplayTarget: MacDetailPosterTarget?
  func setMacDisplayTarget(_ target: MacDetailPosterTarget) {
    guard macDisplayTarget != target else { return }
    macDisplayTarget = target
    models.values.forEach { $0.setMacDisplayTarget(target) }
  }
  #endif
  #if os(iOS)
  private var displayTarget: DetailPosterTarget?
  func setDisplayViewport(_ bounds: CGSize, screen: UIScreen) {
    guard bounds.width > 0, bounds.height > 0 else { return }
    let target = DetailPosterTarget(pixels: CGSize(width: ceil(bounds.width * screen.scale),
      height: ceil(bounds.height * screen.scale)),
      screen: "\(ObjectIdentifier(screen))",
      displayProfile: "native-hdr-v1|\(screen.traitCollection.displayGamut.rawValue)|\(screen.scale)")
    guard displayTarget != target else { return }
    displayTarget = target
    models.values.forEach { $0.setDisplayTarget(target) }
  }
  #endif
  init(asset: PHAsset, library: PhotoLibraryModel, poster: LibraryImage? = nil, reviewAssets: [PHAsset]? = nil) {
    self.library = library
    #if os(iOS)
    let reviewAssets = reviewAssets.map { collection in
      collection.sorted {
        if $0.creationDate != $1.creationDate { return ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        return $0.localIdentifier < $1.localIdentifier
      }
    }
    #endif
    self.reviewAssets = reviewAssets
    reviewIndices = Dictionary((reviewAssets ?? []).enumerated().map { ($0.element.localIdentifier,$0.offset) },uniquingKeysWith: { first,_ in first })
    current = MediaPreviewModel(asset: asset, poster: poster ?? library.thumbnails.poster(for: asset), renditions: library.thumbnails)
    models[asset.localIdentifier] = current
  }
  func model(for asset: PHAsset) -> MediaPreviewModel {
    if let cached = models[asset.localIdentifier] { return cached }
    let model = MediaPreviewModel(asset: asset, poster: library.thumbnails.poster(for: asset),
      renditions: library.thumbnails, isCurrent: false)
    #if os(macOS)
    if let macDisplayTarget { model.setMacDisplayTarget(macDisplayTarget) }
    #endif
    #if os(iOS)
    if let displayTarget { model.setDisplayTarget(displayTarget) }
    #endif
    models[asset.localIdentifier] = model
    model.load(promptForCloud: false)
    return model
  }
  func adjacent(to asset: PHAsset, direction: Int) -> PHAsset? {
    guard let index = index(of: asset) else { return nil }
    return self.asset(at: index + direction)
  }
  func activate(_ asset: PHAsset) {
    current.deactivate(); current = model(for: asset); fitMedia(); current.activate()
    Task { [weak self] in
      guard let self else { return }
      let previousCount = count
      if reviewAssets == nil { _ = await library.previewNeighbor(of: asset, direction: 1) }
      if count != previousCount { collectionRevision &+= 1 }
      guard current.asset.localIdentifier == asset.localIdentifier else { return }
      #if os(iOS)
      let neighbours = ([-2, -1, 0, 1, 2]).compactMap { offset in
        index(of: asset).flatMap { self.asset(at: $0 + offset) }
      }
      // Prepare two local neighbours in each direction without widening the
      // visible page's network request or creating another transfer queue.
      for neighbour in neighbours where neighbour.localIdentifier != asset.localIdentifier { _ = model(for: neighbour) }
      let keep = Set(neighbours.map(\.localIdentifier))
      #else
      let keep = Set([asset, adjacent(to: asset, direction: -1), adjacent(to: asset, direction: 1)].compactMap { $0?.localIdentifier })
      #endif
      for id in Array(models.keys) where !keep.contains(id) { models.removeValue(forKey: id)?.cancel() }
    }
  }
  func start() { current.load(); activate(current.asset) }
  func stop() { models.values.forEach { $0.cancel() }; models.removeAll() }
  func reloadForPolicy() {
    for model in models.values {
      let info = model.metadataRequested; model.load(promptForCloud: model === current)
      if info { model.loadMetadata() }
    }
  }
}
/// Keep only a bounded metadata prefix while counting streamed bytes. Opening
/// information for a large camera original never allocates its entire payload.
final class PreviewMetadataBytes: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()
  private var count: Int64 = 0
  func append(_ chunk: Data) {
    lock.lock(); defer { lock.unlock() }
    count += Int64(chunk.count)
    let remaining = max(0, 1_048_576 - data.count)
    if remaining > 0 { data.append(chunk.prefix(remaining)) }
  }
  func snapshot() -> (Data, Int64) {
    lock.lock(); defer { lock.unlock() }; return (data, count)
  }
}
struct BurstPreviewControls: View {
  @ObservedObject var preview: MediaPreviewModel
  var select: ((PHAsset) -> Void)? = nil
  var body: some View {
    if preview.burstCount > 1 {
      HStack {
        Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
          .disabled(preview.burstIndex == 0).accessibilityLabel(Text("preview_burst_previous"))
        Text(String(format: NSLocalizedString("preview_burst_index", comment: ""), preview.burstIndex + 1, preview.burstCount)).font(.callout).monospacedDigit()
        Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
          .disabled(preview.burstIndex + 1 == preview.burstCount).accessibilityLabel(Text("preview_burst_next"))
      }.frame(maxWidth: .infinity)
    }
  }
  private func move(_ direction: Int) {
    if let select, let asset = preview.burstNeighbour(direction) { select(asset) }
    else { preview.moveBurst(direction) }
  }
}
struct PhotoMetadataPanel: View {
  @ObservedObject var preview: MediaPreviewModel
  /// Changes whenever the backup facts behind `backupInfo` change, so the
  /// panel redraws; a new closure alone does not count as a change.
  var revision = 0
  var backupInfo: (([(String, String)]) -> AnyView)? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.small) {
      if let backupInfo { backupInfo(fields) }
      else {
        PhotoBackupInfo(sourceID: preview.asset.localIdentifier, takenAt: preview.asset.creationDate,
          filename: preview.filename, fields: fields)
      }
      if preview.metadataLoading { ProgressView().controlSize(.small) }
      if preview.metadataUnavailable { Text("preview_info_unavailable").font(.footnote).foregroundStyle(.secondary) }
      if let location = preview.asset.location {
        Map(initialPosition: .region(MKCoordinateRegion(center: location.coordinate,
          span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
          Marker("preview_location", coordinate: location.coordinate).annotationTitles(.hidden)
        }.mapStyle(.standard).frame(height: 160)
          .clipShape(RoundedRectangle(cornerRadius: DuckRadius.card))
          .allowsHitTesting(false).accessibilityLabel(Text("preview_location")).id(preview.asset.localIdentifier)
      }
    }
    .task(id: preview.asset.localIdentifier) { preview.loadMetadata() }
    .onDisappear { preview.cancelMetadata() }
  }
  private var fields: [(String, String)] {
    var result = [("preview_resolution", "\(preview.asset.pixelWidth) × \(preview.asset.pixelHeight)")]
    if preview.asset.mediaType == .video { result.append(("preview_video_duration", videoDurationLabel(preview.asset.duration))) }
    return result + preview.metadata
  }
}

/// A failed explicit media download retains the poster and the existing Retry action.
struct MediaPreviewFailure: View {
  var retry: () -> Void
  var body: some View {
    VStack(spacing: DuckSpacing.small) {
      Image(systemName: "exclamationmark.circle").font(.largeTitle)
      Text("library_preview_icloud_failed").font(.callout).multilineTextAlignment(.center)
      Button("retry_task", action: retry).duckSecondaryAction()
    }.padding(DuckSpacing.medium + DuckSpacing.xxSmall)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DuckRadius.feature))
      .accessibilityIdentifier("library.preview.failure")
  }
}

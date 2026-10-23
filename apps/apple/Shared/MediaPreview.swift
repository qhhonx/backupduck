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
  var previewFilename: String { get }
  var previewMetadata: [(String, String)] { get }
}

@MainActor final class MediaPreviewModel: ObservableObject {
  @Published private(set) var asset: PHAsset
  @Published private(set) var image: LibraryImage?
  @Published private(set) var livePhoto: PHLivePhoto?
  @Published private(set) var player: AVPlayer?
  @Published private(set) var loading = false
  @Published private(set) var cloudNeeded = false
  @Published private(set) var failure = false
  @Published private(set) var progress: Double = 0
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
  private var cloudPoster = false
  private var promptForCloud = true
  private let manager: PHImageManager?
  init(asset: PHAsset, poster: LibraryImage? = nil, manager: PHImageManager? = nil) {
    self.asset = asset; image = poster; self.manager = BackupEnvironment.usesPhotoLibrary ? (manager ?? .default()) : nil
  }
  private func adoptPoster(_ incoming: LibraryImage) {
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
      if fullAspect(incoming), !fullAspect(current) {
        image = incoming; return
      }
      guard edge(incoming) >= edge(current) else { return }
    }
    image = incoming
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
    self.promptForCloud = promptForCloud
    if let next, next.localIdentifier != asset.localIdentifier { asset = next; image = nil }
    if let sample = asset as? any PreviewSample {
      image = sample.previewImage; loading = false; failure = image == nil
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
    cloudPoster = false; cloudNeeded = false; failure = false; loading = true; progress = 0
    let expected = generation
    let network = PreviewNetworkPolicy.shared.allowed
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
      contentMode: .aspectFit, options: local) { [weak self] value, _ in
      Task { @MainActor in
        guard let self, self.generation == expected, let value else { return }
        self.adoptPoster(value)
      }
    })
    let size = CGSize(width: min(4096, max(1600, pixels)), height: min(4096, max(1600, pixels)))
    requests.append(manager.requestImage(for: asset, targetSize: size,
      contentMode: .aspectFit, options: options) { [weak self] value, info in
      Task { @MainActor in
        guard let self, self.generation == expected else { return }
        if let value { self.adoptPoster(value) }
        if info?[PHImageResultIsInCloudKey] as? Bool == true { self.cloudPoster = true }
        guard info?[PHImageResultIsDegradedKey] as? Bool != true else { return }
        if self.asset.mediaType != .video && !self.asset.mediaSubtypes.contains(.photoLive) {
          self.finish(value != nil, info: info)
        }
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
      let options = PHLivePhotoRequestOptions(); options.isNetworkAccessAllowed = network
      options.deliveryMode = .highQualityFormat
      options.progressHandler = { [weak self] value, _, _, _ in Task { @MainActor in
        guard self?.generation == expected else { return }; self?.progress = value
      } }
      requests.append(manager.requestLivePhoto(for: asset, targetSize: size,
        contentMode: .aspectFit, options: options) { [weak self] value, info in
        Task { @MainActor in
          guard let self, self.generation == expected, info?[PHLivePhotoInfoIsDegradedKey] as? Bool != true else { return }
          self.livePhoto = value; self.finish(value != nil, info: info)
        }
      })
    }
  }
  private func finish(_ available: Bool, info: [AnyHashable: Any]?) {
    loading = false
    let error = (info?[PHImageErrorKey] ?? info?[PHLivePhotoInfoErrorKey]) as? NSError
    let networkRequired = error?.domain == PHPhotosErrorDomain && error?.code == PHPhotosError.Code.networkAccessRequired.rawValue
    cloudNeeded = !available && (info?[PHImageResultIsInCloudKey] as? Bool == true || cloudPoster || networkRequired)
    failure = !available && !cloudNeeded
  }
  func activate() {
    promptForCloud = true
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
    return library.asset(at: index)
  }
  func index(of asset: PHAsset) -> Int? {
    reviewAssets == nil ? library.previewIndex(of: asset) : reviewIndices[asset.localIdentifier]
  }
  @Published private(set) var current: MediaPreviewModel
  @Published var zoomed = false
  @Published var paging = false
  @Published var fitRevision = 0
  func fitMedia() { zoomed = false; fitRevision &+= 1 }
  private var models: [String: MediaPreviewModel] = [:]
  init(asset: PHAsset, library: PhotoLibraryModel, poster: LibraryImage? = nil, reviewAssets: [PHAsset]? = nil) {
    self.library = library
    self.reviewAssets = reviewAssets
    reviewIndices = Dictionary((reviewAssets ?? []).enumerated().map { ($0.element.localIdentifier,$0.offset) },uniquingKeysWith: { first,_ in first })
    current = MediaPreviewModel(asset: asset, poster: poster ?? library.thumbnails.poster(for: asset))
    models[asset.localIdentifier] = current
  }
  func model(for asset: PHAsset) -> MediaPreviewModel {
    if let cached = models[asset.localIdentifier] { return cached }
    let model = MediaPreviewModel(asset: asset, poster: library.thumbnails.poster(for: asset))
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
      if reviewAssets == nil { _ = await library.previewNeighbor(of: asset, direction: 1) }
      guard current.asset.localIdentifier == asset.localIdentifier else { return }
      let keep = Set([asset, adjacent(to: asset, direction: -1), adjacent(to: asset, direction: 1)].compactMap { $0?.localIdentifier })
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

import AVKit
import Combine
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// Network consent applies only to browsing. It never registers backup work.
@MainActor final class PreviewNetworkPolicy: ObservableObject {
  static let shared = PreviewNetworkPolicy()
  @Published private(set) var choice: String
  @Published var asking = false
  var allowed: Bool { choice == "allow" }
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    choice = defaults.string(forKey: "previewCloudConsent") ?? "ask"
  }
  private let defaults: UserDefaults
  func requestConsent() { if choice == "ask" { asking = true } }
  func decide(_ allow: Bool) {
    choice = allow ? "allow" : "deny"
    defaults.set(choice, forKey: "previewCloudConsent")
    asking = false
  }
}
struct PreviewCloudSetting: View {
  @ObservedObject private var policy = PreviewNetworkPolicy.shared
  var body: some View {
    Toggle("preview_cloud_setting", isOn: Binding(get: { policy.allowed }, set: { policy.decide($0) }))
      .accessibilityIdentifier("settings.preview_cloud")
  }
}
private struct PreviewConsent: ViewModifier {
  @ObservedObject private var policy = PreviewNetworkPolicy.shared
  func body(content: Content) -> some View {
    content.alert("preview_cloud_title", isPresented: $policy.asking) {
      Button("preview_cloud_allow") { policy.decide(true) }
      Button("preview_cloud_not_now", role: .cancel) { policy.decide(false) }
    } message: { Text("preview_cloud_note") }
  }
}
extension View {
  func previewCloudConsent() -> some View { modifier(PreviewConsent()) }
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
  private var generation = UUID()
  private var cloudPoster = false
  init(asset: PHAsset) { self.asset = asset }
  var kind: String {
    asset.burstIdentifier != nil ? "burst" : asset.mediaType == .video ? "video"
      : asset.mediaSubtypes.contains(.photoLive) ? "motion" : "photo"
  }
  var filename: String { PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "" }
  func load(_ next: PHAsset? = nil, pixels: CGFloat = 2400) {
    cancel()
    if let next { asset = next }
    if let burst = asset.burstIdentifier {
      let options = photoLibraryFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
      burstFetch = PHAsset.fetchAssets(withBurstIdentifier: burst, options: options)
      burstCount = burstFetch?.count ?? 0
      let index = burstFetch?.index(of: asset) ?? NSNotFound
      burstIndex = index == NSNotFound ? 0 : index
    } else { burstFetch = nil; burstCount = 0; burstIndex = 0 }
    image = nil; livePhoto = nil; player = nil; metadata = []
    cloudPoster = false; cloudNeeded = false; failure = false; loading = true; progress = 0
    let expected = generation
    let network = PreviewNetworkPolicy.shared.allowed
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = network
    options.deliveryMode = .opportunistic; options.resizeMode = .exact
    options.progressHandler = { [weak self] value, _, _, _ in
      Task { @MainActor in guard self?.generation == expected else { return }; self?.progress = value }
    }
    let size = CGSize(width: min(4096, max(1600, pixels)), height: min(4096, max(1600, pixels)))
    requests.append(PHImageManager.default().requestImage(for: asset, targetSize: size,
      contentMode: .aspectFit, options: options) { [weak self] value, info in
      Task { @MainActor in
        guard let self, self.generation == expected else { return }
        if let value { self.image = value }
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
      requests.append(PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, info in
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
      requests.append(PHImageManager.default().requestLivePhoto(for: asset, targetSize: size,
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
    if cloudNeeded { PreviewNetworkPolicy.shared.requestConsent() }
  }
  func moveBurst(_ direction: Int) {
    let index = burstIndex + direction
    guard let burstFetch, (0..<burstFetch.count).contains(index) else { return }
    load(burstFetch.object(at: index))
  }
  func cancel() {
    generation = UUID()
    requests.forEach { PHImageManager.default().cancelImageRequest($0) }; requests = []
    if let metadataRequest { PHAssetResourceManager.default().cancelDataRequest(metadataRequest) }; metadataRequest = nil
    player?.pause(); loading = false; metadataLoading = false
  }
  func loadMetadata() {
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
          guard let self, self.generation == expected else { return }
          self.metadataLoading = false; self.metadataUnavailable = true; self.metadataRequest = nil
          if (error as NSError).domain == PHPhotosErrorDomain && (error as NSError).code == PHPhotosError.Code.networkAccessRequired.rawValue { PreviewNetworkPolicy.shared.requestConsent() }
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
      Task { @MainActor in guard self?.generation == expected else { return }; self?.metadata = fields; self?.metadataLoading = false; self?.metadataRequest = nil }
    })
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
  var body: some View {
    if preview.burstCount > 1 {
      HStack {
        Button { preview.moveBurst(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
          .disabled(preview.burstIndex == 0).accessibilityLabel(Text("preview_burst_previous"))
        Text(String(format: NSLocalizedString("preview_burst_index", comment: ""), preview.burstIndex + 1, preview.burstCount)).font(.callout).monospacedDigit()
        Button { preview.moveBurst(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
          .disabled(preview.burstIndex + 1 == preview.burstCount).accessibilityLabel(Text("preview_burst_next"))
      }.frame(maxWidth: .infinity)
    }
  }
}
struct PhotoMetadataPanel: View {
  @ObservedObject private var policy = PreviewNetworkPolicy.shared
  @ObservedObject var preview: MediaPreviewModel
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !preview.filename.isEmpty { Text(preview.filename).font(.headline).textSelection(.enabled) }
      LabeledContent("design_file_type", value: NSLocalizedString("library_filter_" + preview.kind, comment: ""))
      LabeledContent("design_capture_time", value: preview.asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? NSLocalizedString("design_capture_unknown", comment: ""))
      LabeledContent("apple_photo_dimensions", value: "\(preview.asset.pixelWidth) × \(preview.asset.pixelHeight)")
      if preview.asset.mediaType == .video { LabeledContent("apple_photo_duration", value: videoDurationLabel(preview.asset.duration)) }
      if preview.metadataLoading { ProgressView("preview_loading_info") }
      if preview.metadataUnavailable {
        Text("preview_info_unavailable").font(.footnote).foregroundStyle(DuckColors.textSecondary)
        Button(policy.allowed ? "retry_task" : "preview_cloud_allow") {
          if !policy.allowed { policy.decide(true) }; preview.loadMetadata()
        }
      }
      ForEach(Array(preview.metadata.enumerated()), id: \.offset) { _, field in LabeledContent(LocalizedStringKey(field.0), value: field.1) }
      if let location = preview.asset.location {
        LabeledContent("preview_location", value: String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude))
      }
    }.textSelection(.enabled).task(id: preview.asset.localIdentifier) { preview.loadMetadata() }
  }
}

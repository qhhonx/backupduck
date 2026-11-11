#if os(iOS)
import CryptoKit
import Compression
import UIKit

/// The viewer's fitted image is a thumbnail tier, not an original or zoom resource.
struct DetailThumbnailIdentity: Codable, Equatable, Sendable {
  let assetID: String
  let revision: String
  let width: Int
  let height: Int
  let screen: String
  var key: String {
    // JSON preserves field boundaries even when an identifier contains separators.
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return "detail-bitmap-v2|" + String(decoding: try! encoder.encode(self), as: UTF8.self)
  }
}

struct DetailThumbnailQuality: Codable, Equatable, Sendable {
  let hdr: Bool, wideColor: Bool
  let componentBits: Int
  let edge: CGFloat
  init(_ image: UIImage) {
    let space = image.cgImage?.colorSpace
    hdr = image.isHighDynamicRange || space?.isHDR() == true
      || (space.map { CGColorSpaceUsesExtendedRange($0) } ?? false)
    wideColor = space?.isWideGamutRGB ?? false
    componentBits = image.cgImage?.bitsPerComponent ?? 0
    edge = max(image.size.width, image.size.height) * image.scale
  }
  func improvesColor(_ previous: Self) -> Bool {
    if hdr != previous.hdr { return hdr }
    if wideColor != previous.wideColor { return wideColor }
    return componentBits > previous.componentBits
  }
  func improves(_ previous: Self) -> Bool {
    if hdr != previous.hdr { return hdr }
    if wideColor != previous.wideColor { return wideColor }
    if componentBits != previous.componentBits { return componentBits > previous.componentBits }
    return edge > previous.edge
  }
}

/// Lossless prepared pixels avoid a JPEG/HEIF conversion of wide-color or HDR
/// components. ImageIO's preserve-gain-map API needs an image source with its
/// auxiliary data; PhotoKit's UIImage callback does not provide that source.
/// A gain-map-only UIImage is therefore not persisted from its SDR base bitmap.
/// All records live in ThumbnailDiskCache and share its accounting and clearing.
enum DetailThumbnailCodec {
  static let maximumBytes = 64 * 1024 * 1024
  struct Record: Codable {
    let version: Int
    let key: String
    let width: Int, height: Int, rowBytes: Int, componentBits: Int, pixelBits: Int
    let bitmapInfo: UInt32
    let intent: Int32
    let colorName: String?
    let colorProfile: Data?
    let orientation: Int
    let scale: CGFloat
    let headroom: Float
    let quality: DetailThumbnailQuality
    let checksum: Data
    let pixels: Data
  }
  static func encode(_ image: UIImage, key: String) -> Data? {
    guard image.images == nil, let cg = image.cgImage, !cg.isMask, cg.decode == nil,
      let space = cg.colorSpace, space.model == .rgb,
      [8, 16, 32].contains(cg.bitsPerComponent), cg.width > 0, cg.height > 0,
      cg.bytesPerRow <= maximumBytes / cg.height,
      !(image.isHighDynamicRange && !space.isHDR() && !CGColorSpaceUsesExtendedRange(space)),
      let raw = cg.dataProvider?.data else { return nil }
    let count = cg.bytesPerRow * cg.height
    guard CFDataGetLength(raw) >= count else { return nil }
    let bytes = Data((raw as Data).prefix(count))
    var compressed = Data(count: count + 4096)
    let encodedCount = compressed.withUnsafeMutableBytes { output in
      bytes.withUnsafeBytes { input in
        compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
          input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZFSE)
      }
    }
    guard encodedCount > 0 else { return nil }
    compressed.count = encodedCount
    let record = Record(version: 1, key: key, width: cg.width, height: cg.height,
      rowBytes: cg.bytesPerRow, componentBits: cg.bitsPerComponent, pixelBits: cg.bitsPerPixel,
      bitmapInfo: cg.bitmapInfo.rawValue, intent: cg.renderingIntent.rawValue,
      colorName: space.name as String?, colorProfile: space.copyICCData() as Data?,
      orientation: image.imageOrientation.rawValue, scale: image.scale, headroom: cg.contentHeadroom,
      quality: DetailThumbnailQuality(image), checksum: Data(SHA256.hash(data: bytes)), pixels: compressed)
    let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
    guard let data = try? encoder.encode(record), data.count <= maximumBytes,
      let restored = decode(data, key: key), let restoredCG = restored.cgImage,
      CFEqual(space, restoredCG.colorSpace), restoredCG.bitmapInfo == cg.bitmapInfo else { return nil }
    return data
  }
  static func record(_ data: Data, key: String) -> Record? {
    guard data.count <= maximumBytes,
      let record = try? PropertyListDecoder().decode(Record.self, from: data),
      record.version == 1, record.key == key,
      record.width > 0, record.height > 0, record.width <= 16384, record.height <= 16384,
      [8, 16, 32].contains(record.componentBits), record.pixelBits > 0, record.pixelBits <= 128,
      record.rowBytes >= (record.width * record.pixelBits + 7) / 8,
      record.rowBytes <= maximumBytes / record.height,
      (0...7).contains(record.orientation),
      record.scale.isFinite, record.scale > 0, record.headroom.isFinite, record.headroom >= 0,
      !record.pixels.isEmpty, (0...4).contains(record.intent),
      record.checksum.count == SHA256.byteCount else { return nil }
    return record
  }
  static func decode(_ data: Data, key: String) -> UIImage? {
    guard let record = record(data, key: key),
      let orientation = UIImage.Orientation(rawValue: record.orientation),
      let intent = CGColorRenderingIntent(rawValue: record.intent) else { return nil }
    let space = record.colorName.flatMap { CGColorSpace(name: $0 as CFString) }
      ?? record.colorProfile.flatMap { CGColorSpace(iccData: $0 as CFData) }
    guard let space, space.model == .rgb else { return nil }
    if let profile = record.colorProfile, space.copyICCData() as Data? != profile { return nil }
    // Bound decompression before allocating output, including for corrupt files.
    let count = record.rowBytes * record.height
    var raw = Data(count: count + 1)
    let decodedCount = raw.withUnsafeMutableBytes { output in
      record.pixels.withUnsafeBytes { input in
        compression_decode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
          input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZFSE)
      }
    }
    guard decodedCount == count else { return nil }
    raw.count = count
    guard Data(SHA256.hash(data: raw)) == record.checksum,
      let provider = CGDataProvider(data: raw as CFData),
      var cg = CGImage(width: record.width, height: record.height,
        bitsPerComponent: record.componentBits, bitsPerPixel: record.pixelBits,
        bytesPerRow: record.rowBytes, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: record.bitmapInfo), provider: provider,
        decode: nil, shouldInterpolate: true, intent: intent) else { return nil }
    if record.headroom > 0 {
      guard let tagged = CGImageCreateCopyWithContentHeadroom(record.headroom, cg) else { return nil }
      cg = tagged
    }
    let image = UIImage(cgImage: cg, scale: record.scale, orientation: orientation)
    guard DetailThumbnailQuality(image) == record.quality,
      cg.contentHeadroom == record.headroom else { return nil }
    return image
  }
}
#endif

#if os(macOS)
import AppKit
import Combine
import Compression
import CryptoKit
import Photos

/// Identity of a display-sized, uncropped rendition. The display profile is part
/// of the identity because images can be requested on different screens.
struct MacDetailPosterTarget: Equatable {
  let pixels: CGSize
  let profile: String
  func fitted(for asset: PHAsset) -> CGSize {
    let width = CGFloat(max(1, asset.pixelWidth)), height = CGFloat(max(1, asset.pixelHeight))
    let scale = min(1, pixels.width / width, pixels.height / height, 4096 / max(width, height))
    return CGSize(width: ceil(width * scale), height: ceil(height * scale))
  }
}

/// Lossless bitmap record: preserve the source profile, component format and
/// HDR headroom rather than converting the full-aspect image into a JPEG.
enum MacDetailBitmap {
  static let limit = 64 * 1024 * 1024
  static func improvesColor(_ candidate: CGImage, over previous: CGImage) -> Bool {
    let first = candidate.colorSpace, second = previous.colorSpace
    let candidateHDR = first?.isHDR() == true || (first.map { CGColorSpaceUsesExtendedRange($0) } ?? false)
    let previousHDR = second?.isHDR() == true || (second.map { CGColorSpaceUsesExtendedRange($0) } ?? false)
    if candidateHDR != previousHDR { return candidateHDR }
    let candidateWide = first?.isWideGamutRGB == true, previousWide = second?.isWideGamutRGB == true
    if candidateWide != previousWide { return candidateWide }
    return candidate.bitsPerComponent > previous.bitsPerComponent
  }
  static func keepsCurrentColor(_ current: CGImage, incoming: CGImage, fitted: CGSize?) -> Bool {
    func fits(_ image: CGImage) -> Bool {
      guard let fitted else { return false }
      return CGFloat(image.width) >= fitted.width - 1 && CGFloat(image.height) >= fitted.height - 1
    }
    return !(fits(incoming) && !fits(current)) && improvesColor(current, over: incoming)
  }
  struct Record: Codable {
    let key: String
    let width: Int, height: Int, rowBytes: Int, componentBits: Int, pixelBits: Int
    let bitmapInfo: UInt32
    let intent: Int32
    let colorName: String?
    let colorProfile: Data?
    let headroom: Float
    let checksum: Data
    let pixels: Data
  }
  static func encode(_ image: CGImage, key: String) -> Data? {
    guard !image.isMask, image.decode == nil, let space = image.colorSpace, space.model == .rgb,
      [8, 16, 32].contains(image.bitsPerComponent), image.width > 0, image.height > 0,
      image.bytesPerRow <= limit / image.height, let raw = image.dataProvider?.data else { return nil }
    let count = image.bytesPerRow * image.height
    guard CFDataGetLength(raw) >= count else { return nil }
    let bytes = Data((raw as Data).prefix(count))
    var compressed = Data(count: count + 4096)
    let size = compressed.withUnsafeMutableBytes { output in
      bytes.withUnsafeBytes { input in
        compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
          input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZFSE)
      }
    }
    guard size > 0 else { return nil }
    compressed.count = size
    let headroom: Float
    if #available(macOS 15, *) { headroom = image.contentHeadroom } else { headroom = 0 }
    let record = Record(key: key, width: image.width, height: image.height, rowBytes: image.bytesPerRow,
      componentBits: image.bitsPerComponent, pixelBits: image.bitsPerPixel, bitmapInfo: image.bitmapInfo.rawValue,
      intent: image.renderingIntent.rawValue, colorName: space.name as String?,
      colorProfile: space.copyICCData() as Data?, headroom: headroom,
      checksum: Data(SHA256.hash(data: bytes)), pixels: compressed)
    let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
    guard let data = try? encoder.encode(record), data.count <= limit,
      let restored = decode(data, key: key), let restoredSpace = restored.colorSpace,
      CFEqual(space, restoredSpace), restored.bitmapInfo == image.bitmapInfo else { return nil }
    return data
  }
  static func decode(_ data: Data, key: String) -> CGImage? {
    guard data.count <= limit, let record = try? PropertyListDecoder().decode(Record.self, from: data),
      record.key == key, record.width > 0, record.height > 0, record.width <= 16384, record.height <= 16384,
      [8, 16, 32].contains(record.componentBits), record.pixelBits > 0, record.pixelBits <= 128,
      record.rowBytes >= (record.width * record.pixelBits + 7) / 8,
      record.rowBytes <= limit / record.height, record.headroom.isFinite, record.headroom >= 0,
      record.checksum.count == SHA256.byteCount, !record.pixels.isEmpty,
      let intent = CGColorRenderingIntent(rawValue: record.intent) else { return nil }
    let space = record.colorName.flatMap { CGColorSpace(name: $0 as CFString) }
      ?? record.colorProfile.flatMap { CGColorSpace(iccData: $0 as CFData) }
    guard let space, space.model == .rgb else { return nil }
    if let profile = record.colorProfile, space.copyICCData() as Data? != profile { return nil }
    let count = record.rowBytes * record.height
    var raw = Data(count: count + 1)
    let decoded = raw.withUnsafeMutableBytes { output in
      record.pixels.withUnsafeBytes { input in
        compression_decode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
          input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZFSE)
      }
    }
    guard decoded == count else { return nil }
    raw.count = count
    guard Data(SHA256.hash(data: raw)) == record.checksum,
      let provider = CGDataProvider(data: raw as CFData),
      var image = CGImage(width: record.width, height: record.height, bitsPerComponent: record.componentBits,
        bitsPerPixel: record.pixelBits, bytesPerRow: record.rowBytes, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: record.bitmapInfo), provider: provider,
        decode: nil, shouldInterpolate: true, intent: intent) else { return nil }
    if record.headroom > 0 {
      // Sonoma can retain extended-range pixels but cannot restore an explicit headroom tag.
      guard #available(macOS 15, *) else { return nil }
      if image.contentHeadroom != record.headroom {
        guard let tagged = CGImageCreateCopyWithContentHeadroom(record.headroom, image) else { return nil }
        image = tagged
      }
    }
    return image
  }
}
#endif

#if os(macOS)
/// The detail tier shares the native thumbnail storage's epoch and budget.
/// The fast memory tier is bounded independently and discarded under pressure.
@MainActor final class MacDetailPosterCache {
  static let shared = MacDetailPosterCache()
  nonisolated static let retention: TimeInterval = 30 * 24 * 60 * 60
  private let memory = NSCache<NSString, NSImage>()
  private var memoryAccess: [String: Date] = [:]
  private var memoryAssets: [String: String] = [:]
  private var generation = 0
  private final class PublicationGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func advance() { lock.lock(); value &+= 1; lock.unlock() }
    func isCurrent(_ expected: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return value == expected }
    func withCurrent<T>(_ expected: Int, _ operation: () -> T, stale: (T) -> Void = { _ in }) -> T? {
      guard isCurrent(expected) else { return nil }
      let result = operation()
      guard isCurrent(expected) else { stale(result); return nil }
      return result
    }
  }
  private let publicationGeneration = PublicationGeneration()
  private var activeReads = 0
  private var encoding = false
  private var publicationVersion = 0
  private var tasks: [String: Task<Void, Never>] = [:]
  private var observation: AnyCancellable?
  private var foregroundObservation: AnyCancellable?
  private var memoryPressure: DispatchSourceMemoryPressure?
  private var authorization: PHAuthorizationStatus?
  private let storage: ThumbnailCacheStorage
  private let budget: () -> Int
  private let tableUsage: () -> Int
  private let authorizationStatus: () -> PHAuthorizationStatus
  private let currentRevision: ((PHAsset) -> String?)?
  private let beforeCommit: () async -> Void
  private let didFinish: () -> Void
  private let afterRename: @Sendable () -> Void
  private let publicationValid: @Sendable (String, String) -> Bool
  init(storage: ThumbnailCacheStorage = MacThumbnailTables.storage,
    budget: @escaping () -> Int = { MacThumbnailTables.budgetMB * 1024 * 1024 },
    tableUsage: (() -> Int)? = nil,
    authorization: @escaping () -> PHAuthorizationStatus = { PHPhotoLibrary.authorizationStatus(for: .readWrite) },
    revision: ((PHAsset) -> String?)? = nil,
    beforeCommit: @escaping () async -> Void = {}, didFinish: @escaping () -> Void = {},
    afterRename: @escaping @Sendable () -> Void = {},
    publicationValid: @escaping @Sendable (String, String) -> Bool = { id, revision in
      guard PhotoLibraryModel.allowed(PHPhotoLibrary.authorizationStatus(for: .readWrite)),
        let current = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return false }
      return PhotoLibraryModel.revision(current) == revision
    }) {
    self.storage = storage; self.budget = budget
    if let tableUsage { self.tableUsage = tableUsage }
    else {
      // The tables capture the screen profile at initialization, on the main thread.
      let tables = [MacThumbnailTables.overview, MacThumbnailTables.detail]
      self.tableUsage = {
        let used = tables.map(\.usage)
        return storage.tableUsage(active: tables) + zip(tables, used).reduce(0) { total, pair in
          let (table, earlierUsage) = pair
          let header = (table.capacity * 16 + 16383) / 16384 * 16384
          return total + max(0, header + table.limit * table.entryBytes - earlierUsage)
        }
      }
    }
    authorizationStatus = authorization; currentRevision = revision
    self.beforeCommit = beforeCommit; self.didFinish = didFinish; self.afterRename = afterRename
    self.publicationValid = publicationValid
    memory.totalCostLimit = min(128 * 1024 * 1024, max(32 * 1024 * 1024, Int(ProcessInfo.processInfo.physicalMemory / 32)))
    memory.countLimit = 64
    observation = NotificationCenter.default.publisher(for: Notification.Name("LibraryThumbnailsCleared"))
      .sink { [weak self] _ in self?.invalidate() }
    foregroundObservation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in self?.synchronizeAuthorization() }
    let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
    source.setEventHandler { [weak self] in self?.invalidate() }
    source.resume(); memoryPressure = source
  }
  var accessGeneration: Int { synchronizeAuthorization(); return generation }
  private func synchronizeAuthorization() {
    let next = authorizationStatus()
    if let authorization, authorization != next { invalidate() }
    authorization = next
  }
  private func valid(_ asset: PHAsset, revision: String) async -> Bool {
    synchronizeAuthorization()
    guard PhotoLibraryModel.allowed(authorizationStatus()) else { return false }
    if let currentRevision { return currentRevision(asset) == revision }
    let check = publicationValid, id = asset.localIdentifier
    return await Task.detached(priority: .userInitiated) { check(id, revision) }.value
  }
  private func key(asset: PHAsset, target: MacDetailPosterTarget) -> String {
    let fitted = target.fitted(for: asset)
    let fields = [asset.localIdentifier, PhotoLibraryModel.revision(asset), String(Int(fitted.width)),
      String(Int(fitted.height)), target.profile]
    let data = try! JSONEncoder().encode(fields)
    return "mac-detail-v2|" + String(decoding: data, as: UTF8.self)
  }
  private nonisolated static func filename(_ key: String) -> String {
    SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".detail"
  }
  private nonisolated static func isDetailFile(_ file: URL) -> Bool {
    guard file.lastPathComponent.range(of: "^[0-9a-f]{64}\\.detail$", options: .regularExpression) != nil,
      let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
    return values.isRegularFile == true && values.isSymbolicLink != true
  }
  nonisolated static func diskUsage(directory: URL) -> Int {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    return files.filter(isDetailFile).reduce(0) {
      $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }
  private func remember(_ image: NSImage, bitmap: CGImage, key: String, assetKey: String) {
    if memoryAccess[key] == nil, memoryAccess.count >= 64,
      let oldest = memoryAccess.min(by: { $0.value < $1.value })?.key {
      memoryAccess.removeValue(forKey: oldest); memoryAssets.removeValue(forKey: oldest); memory.removeObject(forKey: oldest as NSString)
    }
    memory.setObject(image, forKey: key as NSString, cost: bitmap.bytesPerRow * bitmap.height)
    memoryAccess[key] = Date(); memoryAssets[key] = assetKey
  }
  /// Synchronous warm seed for the opening flight; no decoding or disk access.
  func memoryPoster(asset: PHAsset) -> NSImage? {
    synchronizeAuthorization()
    guard PhotoLibraryModel.allowed(authorizationStatus()), !(asset is any PreviewSample) else { return nil }
    let revision = PhotoLibraryModel.revision(asset)
    let assetKey = asset.localIdentifier + "|" + revision
    let candidates = memoryAccess.keys.filter { memoryAssets[$0] == assetKey }
    guard !candidates.isEmpty else { return nil }
    let current: String?
    if let currentRevision { current = currentRevision(asset) }
    else {
      current = PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: nil)
        .firstObject.map(PhotoLibraryModel.revision)
    }
    guard current == revision else { return nil }
    for key in candidates.sorted(by: { memoryAccess[$0]! > memoryAccess[$1]! }) {
      guard let touched = memoryAccess[key], Date().timeIntervalSince(touched) <= Self.retention,
        let image = memory.object(forKey: key as NSString) else { continue }
      memoryAccess[key] = Date()
      return image
    }
    return nil
  }
  private func touch(_ url: URL, assetID: String, revision: String, epoch: Int, generation: Int) {
    let storage = storage, gate = publicationGeneration, valid = publicationValid
    Task.detached(priority: .utility) {
      guard valid(assetID, revision), Self.isDetailFile(url) else { return }
      _ = storage.withCurrent(epoch) {
        _ = gate.withCurrent(generation) {
          try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        }
      }
    }
  }
  func load(asset: PHAsset, target: MacDetailPosterTarget) async -> NSImage? {
    guard !(asset is any PreviewSample) else { return nil }
    let revision = PhotoLibraryModel.revision(asset), key = key(asset: asset, target: target)
    let expected = generation
    guard await valid(asset, revision: revision), expected == generation, let epoch = storage.epoch else { return nil }
    let url = storage.directory.appendingPathComponent(Self.filename(key))
    if let image = memory.object(forKey: key as NSString), let touched = memoryAccess[key],
      Date().timeIntervalSince(touched) <= Self.retention {
      memoryAccess[key] = Date()
      touch(url, assetID: asset.localIdentifier, revision: revision, epoch: epoch, generation: expected)
      return image
    }
    memory.removeObject(forKey: key as NSString); memoryAccess.removeValue(forKey: key); memoryAssets.removeValue(forKey: key)
    guard activeReads < 2 else { return nil }
    activeReads += 1
    defer { activeReads -= 1 }
    let publication = publicationVersion
    let bitmap = await Task.detached(priority: .userInitiated) { () -> CGImage? in
      guard Self.isDetailFile(url), let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
        let size = values.fileSize, size <= MacDetailBitmap.limit,
        let accessed = values.contentModificationDate, Date().timeIntervalSince(accessed) <= Self.retention,
        let data = try? Data(contentsOf: url) else { return nil }
      return MacDetailBitmap.decode(data, key: key)
    }.value
    guard !Task.isCancelled, expected == generation, publication == publicationVersion, storage.isCurrent(epoch),
      await valid(asset, revision: revision), expected == generation, storage.isCurrent(epoch), let bitmap else { return nil }
    guard publication == publicationVersion else { return nil }
    let required = target.fitted(for: asset)
    guard CGFloat(bitmap.width) >= required.width - 1, CGFloat(bitmap.height) >= required.height - 1 else { return nil }
    let image = NSImage(cgImage: bitmap, size: NSSize(width: CGFloat(bitmap.width), height: CGFloat(bitmap.height)))
    remember(image, bitmap: bitmap, key: key, assetKey: asset.localIdentifier + "|" + revision)
    touch(url, assetID: asset.localIdentifier, revision: revision, epoch: epoch, generation: expected)
    return image
  }
  func retain(_ image: NSImage, asset: PHAsset, target: MacDetailPosterTarget, generation expected: Int) {
    guard !(asset is any PreviewSample), generation == expected,
      let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let epoch = storage.epoch else { return }
    let revision = PhotoLibraryModel.revision(asset)
    guard PhotoLibraryModel.allowed(authorizationStatus()), generation == expected else { return }
    let fitted = target.fitted(for: asset), aspect = CGFloat(max(1, asset.pixelWidth)) / CGFloat(max(1, asset.pixelHeight))
    guard abs(log((CGFloat(bitmap.width) / CGFloat(bitmap.height)) / aspect)) < 0.02,
      CGFloat(bitmap.width) >= fitted.width - 1, CGFloat(bitmap.height) >= fitted.height - 1 else { return }
    let key = key(asset: asset, target: target), directory = storage.directory
    // Keep viewed pixels immediately, even if another disk encoding is busy.
    if let previous = memory.object(forKey: key as NSString)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      MacDetailBitmap.improvesColor(previous, over: bitmap) { return }
    remember(image, bitmap: bitmap, key: key, assetKey: asset.localIdentifier + "|" + revision)
    guard tasks[key] == nil, tasks.isEmpty, !encoding,
      bitmap.bytesPerRow <= MacDetailBitmap.limit / bitmap.height else { return }
    encoding = true
    tasks[key] = Task { [weak self] in
      defer {
        self?.encoding = false
        self?.didFinish()
        if self?.generation == expected { self?.tasks.removeValue(forKey: key) }
      }
      guard let self, await self.valid(asset, revision: revision), self.generation == expected,
        !Task.isCancelled else { return }
      let url = directory.appendingPathComponent(Self.filename(key))
      let prepared = await Task.detached(priority: .utility) { () -> (CGImage, Data)? in
        if Self.isDetailFile(url),
          let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
          let size = values.fileSize, size <= MacDetailBitmap.limit,
          let accessed = values.contentModificationDate, Date().timeIntervalSince(accessed) <= Self.retention,
          let existing = try? Data(contentsOf: url), let previous = MacDetailBitmap.decode(existing, key: key),
          MacDetailBitmap.improvesColor(previous, over: bitmap) { return nil }
        guard let resized = Self.fit(bitmap, pixels: fitted), let data = MacDetailBitmap.encode(resized, key: key) else { return nil }
        return (resized, data)
      }.value
      guard !Task.isCancelled, self.generation == expected,
        self.storage.isCurrent(epoch), await self.valid(asset, revision: revision),
        self.generation == expected, self.storage.isCurrent(epoch), let (resized, data) = prepared else { return }
      let result = NSImage(cgImage: resized, size: NSSize(width: CGFloat(resized.width), height: CGFloat(resized.height)))
      self.publicationVersion &+= 1
      self.remember(result, bitmap: resized, key: key, assetKey: asset.localIdentifier + "|" + revision)
      let temp = directory.appendingPathComponent(UUID().uuidString + ".detailtmp")
      let written = await Task.detached(priority: .utility) { () -> Bool in
        do {
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          if let available = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
            available < Int64(data.count) + 128 * 1024 * 1024 { return false }
          try data.write(to: temp); return true
        }
        catch { return false }
      }.value
      defer { Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: temp) } }
      await self.beforeCommit()
      guard written, !Task.isCancelled, self.generation == expected, await self.valid(asset, revision: revision),
        self.generation == expected else { return }
      let budget = self.budget(), usage = self.tableUsage
      let reserved = await Task.detached(priority: .utility) { usage() }.value
      let limit = max(0, budget - reserved)
      guard data.count <= limit else { return }
      guard !Task.isCancelled, self.generation == expected, await self.valid(asset, revision: revision),
        self.generation == expected else { return }
      let storage = self.storage, gate = self.publicationGeneration, valid = self.publicationValid
      let afterRename = self.afterRename
      let assetID = asset.localIdentifier
      await Task.detached(priority: .utility) {
        guard valid(assetID, revision), gate.isCurrent(expected) else { return }
        _ = storage.withCurrent(epoch) {
          // Every detail producer uses this publication lock. Rescan inside
          // it so another source cannot consume the same remaining budget.
          let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
          var details = files.filter { Self.isDetailFile($0) && $0 != url }.compactMap { file -> (URL, Int, Date)? in
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
          }.sorted { $0.2 < $1.2 }
          let temporaryBytes = files.filter { $0 != temp && $0.lastPathComponent.range(
            of: "^[A-Za-z0-9-]+\\.detailtmp$", options: .regularExpression) != nil }.reduce(0) { total, file in
              guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                values.isRegularFile == true, values.isSymbolicLink != true else { return total }
              return total + (values.fileSize ?? 0)
            }
          var bytes = details.reduce(data.count + temporaryBytes) { $0 + $1.1 }
          while !details.isEmpty, bytes > limit || Date().timeIntervalSince(details[0].2) > Self.retention {
            let oldest = details.removeFirst()
            guard gate.isCurrent(expected), storage.isCurrent(epoch),
              (try? FileManager.default.removeItem(at: oldest.0)) != nil else { return }
            bytes -= oldest.1
          }
          guard bytes <= limit, valid(assetID, revision), storage.isCurrent(epoch) else { return }
          _ = gate.withCurrent(expected, {
            let status = rename(temp.path, url.path); afterRename(); return status
          }, stale: { status in
            if status == 0 { try? FileManager.default.removeItem(at: url) }
          })
        }
      }.value
    }
  }
  private nonisolated static func fit(_ source: CGImage, pixels: CGSize) -> CGImage? {
    let width = Int(pixels.width), height = Int(pixels.height)
    guard width > 0, height > 0, width <= MacDetailBitmap.limit / max(1, height * max(1, source.bitsPerPixel / 8)),
      let space = source.colorSpace else { return nil }
    if source.width == width, source.height == height { return source }
    var info = source.bitmapInfo.rawValue
    if source.alphaInfo == .last || source.alphaInfo == .first {
      let alpha: CGImageAlphaInfo = source.alphaInfo == .last ? .premultipliedLast : .premultipliedFirst
      info = (info & ~CGBitmapInfo.alphaInfoMask.rawValue) | alpha.rawValue
    }
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: source.bitsPerComponent,
      bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    guard var result = context.makeImage() else { return nil }
    if #available(macOS 15, *), source.contentHeadroom > 0 {
      guard let tagged = CGImageCreateCopyWithContentHeadroom(source.contentHeadroom, result) else { return nil }
      result = tagged
    }
    return result
  }
  func invalidate() {
    generation &+= 1
    publicationGeneration.advance()
    tasks.values.forEach { $0.cancel() }; tasks.removeAll(); memory.removeAllObjects(); memoryAccess.removeAll(); memoryAssets.removeAll()
  }
  func removeAll(epoch: Int) async {
    guard storage.generation == epoch, storage.epoch == nil else { return }
    invalidate()
    let storage = storage
    _ = await Task.detached(priority: .utility) { storage.clearDetails() }.value
  }
}
#endif

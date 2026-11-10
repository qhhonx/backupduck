import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI

/// File-backed grid renditions use durable size tiers. Memory is only a hot tier;
/// disk lookup never waits for the slower original-file/Quick Look queue.
@MainActor final class FileThumbnailPipeline {
  static let shared = FileThumbnailPipeline()
  private nonisolated static let tiers = [128, 256, 512, 1024, 2048]
  private static let embeddedTier = 64
  @MainActor private final class Flight {
    let identity: String, base: String, edge: Int, epoch: Int?
    let bookmark: Data, relative: String, assetID: String?, revision: String
    var root: URL?
    var needsEmbeddedPreview: Bool
    var persistsRendition: Bool
    var callbacks: [UUID: (NSImage?) -> Void] = [:]
    var visible = Set<UUID>()
    var started = false
    var quickLook: QLThumbnailGenerator.Request?
    var quickLookResult: CheckedContinuation<CGImage?, Never>?
    var video: AVAssetImageGenerator?
    init(identity: String, base: String, edge: Int, epoch: Int?, bookmark: Data,
      relative: String, assetID: String?, revision: String, persistsRendition: Bool) {
      self.identity = identity; self.base = base; self.edge = edge; self.epoch = epoch
      self.bookmark = bookmark; self.relative = relative; self.assetID = assetID; self.revision = revision
      self.persistsRendition = persistsRendition
      let ext = (relative as NSString).pathExtension.lowercased()
      let bytes = revision.split(separator: ":").first.flatMap { Int64($0) } ?? 0
      needsEmbeddedPreview = ["jpg", "jpeg"].contains(ext) && bytes >= 2 * 1024 * 1024
    }
    var diskKey: String { base + "|" + String(edge) }
  }
  struct Statistics {
    var memoryHits = 0, diskHits = 0, originalLoads = 0, coalescedRequests = 0
  }
  private(set) var statistics = Statistics()
  private var flights: [String: Flight] = [:]
  private var subscribers: [UUID: Flight] = [:]
  private var reads: [Flight] = [], originals: [Flight] = []
  private var reading = 0, decoding = 0, publishing = 0
  private let cache = NSCache<NSString, NSImage>()
  private let storage: ThumbnailCacheStorage
  private let budget: () -> Int
  private let originalLoader: ((URL, Int) async -> CGImage?)?
  var isIdle: Bool { reading == 0 && decoding == 0 && publishing == 0 && reads.isEmpty && originals.isEmpty }
  init(storage: ThumbnailCacheStorage = MacThumbnailTables.storage,
    budget: @escaping () -> Int = { MacThumbnailTables.budgetMB * 1024 * 1024 },
    originalLoader: ((URL, Int) async -> CGImage?)? = nil) {
    self.storage = storage; self.budget = budget; self.originalLoader = originalLoader
    cache.totalCostLimit = 96 * 1024 * 1024; cache.countLimit = 512
  }
  func request(id: UUID, source: FolderSource, relative: String, assetID: String? = nil,
    revision: String, size: CGFloat, preheat: Bool = false, persistsRendition: Bool = true,
    completion: @escaping (NSImage?) -> Void) {
    cancel(id)
    guard size.isFinite, size > 0, !relative.isEmpty, !relative.hasPrefix("/"),
      !relative.split(separator: "/").contains("..") else { completion(nil); return }
    let edge = Self.tiers.first { CGFloat($0) >= size * 2 } ?? Self.tiers.last!
    let base = Self.cacheBase(source: source.id, asset: assetID ?? relative, revision: revision)
    let epoch = storage.epoch
    let identity = base + "|\(edge)|\(epoch ?? -1)"
    var placeholder: NSImage?
    if let epoch {
      for tier in Self.candidates(edge) + [Self.embeddedTier] {
        let key = "\(base)|\(tier)|\(epoch)" as NSString
        guard let image = cache.object(forKey: key) else { continue }
        statistics.memoryHits += 1
        if tier >= edge { completion(image); return }
        placeholder = image
        break
      }
    }
    if let flight = flights[identity] {
      flight.callbacks[id] = completion; subscribers[id] = flight
      flight.persistsRendition = flight.persistsRendition || persistsRendition
      if !preheat { flight.visible.insert(id) }
      statistics.coalescedRequests += 1
      if !preheat, let placeholder { completion(placeholder) }
      return
    }
    guard flights.count < 256 else { completion(nil); return }
    let flight = Flight(identity: identity, base: base, edge: edge, epoch: epoch,
      bookmark: source.bookmark, relative: relative, assetID: assetID, revision: revision,
      persistsRendition: persistsRendition)
    flight.callbacks[id] = completion; subscribers[id] = flight
    if !preheat { flight.visible.insert(id) }
    if placeholder != nil { flight.needsEmbeddedPreview = false }
    flights[identity] = flight; reads.append(flight)
    if !preheat, let placeholder { completion(placeholder) }
    pumpReads()
  }
  func cancel(_ id: UUID, notifying: Bool = false) {
    guard let flight = subscribers.removeValue(forKey: id) else { return }
    let identity = flight.identity
    let completion = flight.callbacks.removeValue(forKey: id)
    defer { if notifying { completion?(nil) } }
    flight.visible.remove(id)
    guard flight.callbacks.isEmpty else { return }
    flight.video?.cancelAllCGImageGeneration()
    if let request = flight.quickLook {
      QLThumbnailGenerator.shared.cancel(request)
      flight.quickLook = nil
      let continuation = flight.quickLookResult; flight.quickLookResult = nil
      continuation?.resume(returning: nil)
    }
    if !flight.started {
      reads.removeAll { $0 === flight }; originals.removeAll { $0 === flight }
    }
    flights.removeValue(forKey: identity)
  }
  private func pumpReads() {
    while reading < 8, let index = reads.firstIndex(where: { !$0.visible.isEmpty }) ?? (reading < 2 ? reads.indices.first : nil) {
      let flight = reads.remove(at: index); reading += 1; flight.started = true
      let storage = storage, base = flight.base, edge = flight.edge, epoch = flight.epoch
      Task {
        let hit = await Task.detached(priority: flight.visible.isEmpty ? .utility : .userInitiated) { () -> (CGImage, Int, URL?)? in
          guard let epoch, storage.isCurrent(epoch), Self.safeDirectory(storage.directory) else { return nil }
          // Equal/larger tiers are final. A smaller tier is only a placeholder.
          for tier in Self.candidates(edge) {
            let key = base + "|\(tier)", path = Self.cacheURL(key, directory: storage.directory)
            guard let values = try? path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes <= MacDetailBitmap.limit,
              let data = try? Data(contentsOf: path), let image = MacDetailBitmap.decode(data, key: key),
              storage.isCurrent(epoch) else { continue }
            let accessed = values.contentModificationDate ?? .distantPast
            return (image, tier, Date().timeIntervalSince(accessed) > 3_600 ? path : nil)
          }
          return nil
        }.value
        reading -= 1
        if let hit, let epoch, storage.isCurrent(epoch) {
          statistics.diskHits += 1
          if let path = hit.2 {
            Task.detached(priority: .utility) {
              _ = storage.withCurrent(epoch) {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
              }
            }
          }
          let result = remember(hit.0, flight: flight, tier: hit.1)
          if hit.1 >= edge { finish(flight, image: result); pumpReads(); return }
          flight.needsEmbeddedPreview = false
          deliver(flight, image: result)
        }
        if flight.callbacks.isEmpty { finish(flight, image: nil) }
        else { flight.started = false; originals.append(flight) }
        pumpReads(); pumpOriginals()
      }
    }
  }
  private func pumpOriginals() {
    while decoding < 4, decoding + publishing < 8,
      let index = originals.firstIndex(where: { !$0.visible.isEmpty && $0.needsEmbeddedPreview })
        ?? originals.firstIndex(where: { !$0.visible.isEmpty })
        ?? (decoding == 0 ? originals.indices.first : nil) {
      let flight = originals.remove(at: index); decoding += 1; flight.started = true
      let storage = storage, limit = Int(Double(budget()) * MacThumbnailTables.fileRenditionShare)
      Task(priority: flight.visible.isEmpty ? .utility : .userInitiated) {
        if flight.needsEmbeddedPreview {
          flight.needsEmbeddedPreview = false
          let preview = await loadOriginal(flight, embeddedOnly: true)
          decoding -= 1
          if !flight.callbacks.isEmpty {
            if let preview { deliver(flight, image: remember(preview, flight: flight, tier: Self.embeddedTier)) }
            if !flight.callbacks.isEmpty { flight.started = false; originals.append(flight) }
          }
          pumpOriginals()
          return
        }
        statistics.originalLoads += 1
        let bitmap = await loadOriginal(flight, embeddedOnly: false)
        decoding -= 1
        guard !flight.callbacks.isEmpty else { pumpOriginals(); return }
        // Display is independent of encoding, eviction and writing. Publication
        // has its own bounded slots so it cannot grow unbounded decoded memory.
        publishing += 1
        finish(flight, image: bitmap.map { remember($0, flight: flight, tier: flight.edge) }); pumpOriginals()
        if flight.persistsRendition, let bitmap, let epoch = flight.epoch {
          let key = flight.diskKey
          await Task.detached(priority: .utility) {
            guard storage.isCurrent(epoch), let data = MacDetailBitmap.encode(bitmap, key: key) else { return }
            _ = storage.withCurrent(epoch) {
              Self.publish(data, path: Self.cacheURL(key, directory: storage.directory), storage: storage, limit: limit)
            }
          }.value
        }
        publishing -= 1; pumpOriginals()
      }
    }
  }
  /// A small browsing preview consumes no display-sized disk slot.
  func overviewImage(_ photo: FolderPhoto, source: FolderSource) async -> NSImage? {
    let id = UUID()
    return await withTaskCancellationHandler(operation: {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else { continuation.resume(returning: nil); return }
        request(id: id, source: source, relative: photo.relative, assetID: photo.source_id,
          revision: photo.revision, size: 64, preheat: true, persistsRendition: false) { image in
          self.cancel(id)
          continuation.resume(returning: image)
        }
      }
    }, onCancel: { Task { @MainActor in self.cancel(id, notifying: true) } })
  }
  private func loadOriginal(_ flight: Flight, embeddedOnly: Bool) async -> CGImage? {
    let bookmark = flight.bookmark, relative = flight.relative, edge = flight.edge
    let assetID = flight.assetID, revision = flight.revision
    guard !bookmark.isEmpty, !flight.callbacks.isEmpty else { return nil }
    // A cache hit never needs the source volume or its security-scoped bookmark.
    if flight.root == nil {
      flight.root = await Task.detached {
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting],
          relativeTo: nil, bookmarkDataIsStale: &stale)
      }.value
    }
    guard let root = flight.root, !flight.callbacks.isEmpty else { return nil }
    let scoped = root.startAccessingSecurityScopedResource()
    defer { if scoped { root.stopAccessingSecurityScopedResource() } }
    let file = root.standardizedFileURL.appendingPathComponent(relative)
    let valid = { @Sendable in Self.matchesInventory(file, assetID: assetID, revision: revision) }
    if embeddedOnly {
      return await Task.detached {
        guard valid(), let image = Self.embeddedPreview(file), valid() else { return nil }
        return image
      }.value
    }
    guard await Task.detached(operation: valid).value, !flight.callbacks.isEmpty else { return nil }
    if let originalLoader { return await originalLoader(file, edge) }
    var bitmap: CGImage?
    if ["mov", "mp4", "m4v"].contains(file.pathExtension.lowercased()) {
      let asset = AVURLAsset(url: file)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      flight.video = generator
      var maxEdge = CGFloat(edge)
      if let track = try? await asset.loadTracks(withMediaType: .video).first,
        let size = try? await track.load(.naturalSize) {
        maxEdge = Self.longEdge(CGFloat(edge), width: abs(size.width), height: abs(size.height))
      }
      generator.maximumSize = CGSize(width: maxEdge, height: maxEdge)
      if !flight.callbacks.isEmpty { bitmap = try? await generator.image(at: .zero).image }
      flight.video = nil
    } else {
      bitmap = await Task.detached { Self.still(file, edge: edge) }.value
    }
    if bitmap == nil, !flight.callbacks.isEmpty {
      bitmap = await withCheckedContinuation { continuation in
        let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: edge, height: edge), scale: 1, representationTypes: .thumbnail)
        flight.quickLook = request; flight.quickLookResult = continuation
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
          Task { @MainActor in
            let result = flight.quickLookResult
            flight.quickLookResult = nil; flight.quickLook = nil
            result?.resume(returning: representation?.cgImage)
          }
        }
      }
    }
    guard bitmap != nil, !flight.callbacks.isEmpty, await Task.detached(operation: valid).value else { return nil }
    return bitmap
  }
  private nonisolated static func embeddedPreview(_ file: URL) -> CGImage? {
    // The EXIF segment is at most 64 KiB. Feed a bounded header to ImageIO so
    // a preview can be shown before the card reads the compressed original.
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }
    guard let header = try? handle.read(upToCount: 128 * 1024) else { return nil }
    let source = CGImageSourceCreateIncremental(nil)
    CGImageSourceUpdateData(source, header as CFData, false)
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: false,
      kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: 256
    ] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, width > 0, height > 0 else { return nil }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let aspect = (5...8).contains(orientation) ? height / width : width / height
    let current = Double(image.width) / Double(image.height)
    guard abs(log(aspect / current)) <= 0.2 else { return nil }
    if abs(log(aspect / current)) < 0.02 { return image }
    // Some cameras pad the embedded preview to a different aspect ratio.
    let w = min(Double(image.width), (Double(image.height) * aspect).rounded())
    let h = min(Double(image.height), (Double(image.width) / aspect).rounded())
    return image.cropping(to: CGRect(x: floor((Double(image.width) - w) / 2),
      y: floor((Double(image.height) - h) / 2), width: w, height: h))
  }
  func memoryPoster(source: String, asset: String, revision: String) -> NSImage? {
    guard let epoch = storage.epoch else { return nil }
    let base = Self.cacheBase(source: source, asset: asset, revision: revision)
    for tier in Array(Self.tiers.reversed()) + [Self.embeddedTier] {
      if let image = cache.object(forKey: "\(base)|\(tier)|\(epoch)" as NSString) { return image }
    }
    return nil
  }
  static func cacheBase(source: String, asset: String, revision: String) -> String {
    "folder-grid-v4|" + String(decoding: try! JSONEncoder().encode([source, asset, revision]), as: UTF8.self)
  }
  private nonisolated static func matchesInventory(_ file: URL, assetID: String?, revision: String) -> Bool {
    var info = stat()
    guard file.resolvingSymlinksInPath().path == file.path,
      lstat(file.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return false }
    guard let assetID, assetID.hasPrefix("folder:") else { return true }
    let modified = info.st_mtimespec
    let nanos = modified.tv_sec >= 0 ? UInt64(modified.tv_sec) * 1_000_000_000 + UInt64(modified.tv_nsec) : 0
    let identity = SHA256.hash(data: Data(String(info.st_ino).utf8)).map { String(format: "%02x", $0) }.joined()
    return revision == "\(info.st_size):\(nanos)" && assetID.hasSuffix(":" + identity)
  }
  private nonisolated static func candidates(_ edge: Int) -> [Int] {
    tiers.filter { $0 >= edge } + tiers.filter { $0 < edge }.reversed()
  }
  private func deliver(_ flight: Flight, image: NSImage?) {
    for (id, callback) in flight.callbacks where subscribers[id] === flight { callback(image) }
  }
  private func remember(_ image: CGImage, flight: Flight, tier: Int) -> NSImage {
    let result = NSImage(cgImage: image, size: .zero)
    if let epoch = flight.epoch, storage.isCurrent(epoch) {
      let key = "\(flight.base)|\(tier)|\(epoch)" as NSString
      cache.setObject(result, forKey: key, cost: image.bytesPerRow * image.height)
    }
    return result
  }
  private func finish(_ flight: Flight, image: NSImage?) {
    guard flights[flight.identity] === flight else { return }
    flights.removeValue(forKey: flight.identity)
    let callbacks = flight.callbacks
    for (id, callback) in callbacks where subscribers[id] === flight {
      subscribers.removeValue(forKey: id)
      callback(image)
    }
  }
  private nonisolated static func still(_ file: URL, edge: Int) -> CGImage? {
    guard ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp"].contains(file.pathExtension.lowercased()),
      let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(edge)
    let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(edge)
    let target = longEdge(CGFloat(edge), width: CGFloat(width), height: CGFloat(height))
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(ceil(target)),
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceShouldAllowFloat: true,
      kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR
    ] as CFDictionary)
  }
  private nonisolated static func longEdge(_ edge: CGFloat, width: CGFloat, height: CGFloat) -> CGFloat {
    min(4096, max(edge, edge * max(width, height) / max(1, min(width, height))))
  }
  private nonisolated static func safeDirectory(_ directory: URL) -> Bool {
    var info = stat()
    return lstat(directory.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
  }
  private nonisolated static func publish(_ data: Data, path: URL, storage: ThumbnailCacheStorage, limit: Int) {
    guard data.count <= limit else { return }
    if !FileManager.default.fileExists(atPath: storage.directory.path) {
      try? FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
    }
    guard safeDirectory(storage.directory) else { return }
    if let free = try? storage.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
      free < Int64(data.count) + 128 * 1024 * 1024 { return }
    var used = storage.detailUsage
    if used + data.count > limit {
      let files = (try? FileManager.default.contentsOfDirectory(at: storage.directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])) ?? []
      let candidates = files.compactMap { file -> (URL, Int, Date)? in
        guard file != path, file.lastPathComponent.range(of: "^[0-9a-f]{64}\\.detail$", options: .regularExpression) != nil,
          let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
          values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
      }.sorted { $0.2 < $1.2 }
      for (file, size, _) in candidates where used + data.count > limit {
        if (try? FileManager.default.removeItem(at: file)) != nil { used -= size }
      }
    }
    guard used + data.count <= limit else { return }
    try? data.write(to: path, options: .atomic)
  }
  private nonisolated static func cacheURL(_ key: String, directory: URL) -> URL {
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(digest + ".detail")
  }
}

struct MacFileThumbnail: View {
  let source: FolderSource
  let relative: String
  var assetID: String? = nil
  let revision: String
  var video = false
  var size: CGFloat = 56
  var cornerRadius: CGFloat = 8
  var fillsFrame = false
  @AppStorage("macListThumbnails") private var enabled = true
  @State private var image: NSImage?
  @State private var token = UUID()
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius).fill(.quaternary)
      if enabled, let image {
        if fillsFrame { Image(nsImage: image).resizable().scaledToFill() }
        else { Image(nsImage: image).resizable().scaledToFit() }
      }
      else { Image(systemName: video ? "video" : "photo").foregroundStyle(.secondary) }
    }.frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .task(id: "\(enabled)|\(source.id)|\(assetID ?? relative)|\(revision)|\(size)") {
        FileThumbnailPipeline.shared.cancel(token)
        image = nil; token = UUID()
        guard enabled else { return }
        let expected = token
        FileThumbnailPipeline.shared.request(id: expected, source: source, relative: relative, assetID: assetID,
          revision: revision, size: size) { result in
            guard token == expected, let result else { return }; image = result
          }
      }.onDisappear { FileThumbnailPipeline.shared.cancel(token); token = UUID() }
  }
}

struct MacTransferThumbnail: View {
  let job: BackupJob
  var size: CGFloat = 56
  var cornerRadius: CGFloat = 8
  var fillsFrame = false
  @ObservedObject private var folders = FolderSources.active
  @AppStorage("macListThumbnails") private var enabled = true
  @State private var entry: FolderEntry?
  var body: some View {
    Group {
      if folders.isPreview, let photo = folders.previewRows?.first(where: { $0.source_id == job.asset.source_id }),
        let image = folders.syntheticImage(photo) {
        Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size).clipped()
      } else if let entry, let source = folders.sources.first(where: { $0.id == job.asset.metadata?["source_ref"] }) {
        MacFileThumbnail(source: source, relative: entry.relative, assetID: entry.source_id, revision: entry.revision,
          video: job.asset.kind == "video", size: size, cornerRadius: cornerRadius, fillsFrame: fillsFrame)
      } else {
        Image(systemName: job.asset.kind == "video" ? "video" : "photo")
          .foregroundStyle(.secondary).frame(width: size, height: size)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: cornerRadius))
      }
    }.task(id: "\(enabled)|\(job.id)|\(folders.indexRevision)|\(folders.sources.map { $0.id }.joined(separator: "|"))") {
      entry = nil
      guard enabled, let source = job.asset.metadata?["source_ref"],
        folders.sources.contains(where: { $0.id == source }),
        let value = try? await folders.previewEntry(source, job: job.id, sourceID: job.asset.source_id),
        !Task.isCancelled, value.source_id == job.asset.source_id,
        (value.revision == job.asset.revision || job.asset.revision.hasPrefix(value.revision + "|")) else { return }
      entry = value
    }
  }
}

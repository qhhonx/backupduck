import AppKit
import CryptoKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI

/// File-backed grid renditions use durable size tiers. Memory is only a hot tier;
/// disk lookup never waits for the slower original-file/Quick Look queue.
@MainActor final class FileThumbnailPipeline {
  static let shared = FileThumbnailPipeline()
  private static let tiers = [128, 256, 512, 1024, 2048]
  private final class Flight {
    let identity: String, base: String, edge: Int, epoch: Int?
    let root: URL, file: URL
    var callbacks: [UUID: (NSImage?) -> Void] = [:]
    var started = false
    var quickLook: QLThumbnailGenerator.Request?
    var quickLookResult: CheckedContinuation<CGImage?, Never>?
    init(identity: String, base: String, edge: Int, epoch: Int?, root: URL, file: URL) {
      self.identity = identity; self.base = base; self.edge = edge; self.epoch = epoch
      self.root = root; self.file = file
    }
    var diskKey: String { base + "|" + String(edge) }
  }
  struct Statistics {
    var diskHits = 0, originalLoads = 0, coalescedRequests = 0
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
    cache.totalCostLimit = 32 * 1024 * 1024; cache.countLimit = 128
  }
  func request(id: UUID, source: FolderSource, relative: String, revision: String, size: CGFloat,
    completion: @escaping (NSImage?) -> Void) {
    cancel(id)
    guard size.isFinite, size > 0, !relative.isEmpty, !relative.hasPrefix("/"),
      !relative.split(separator: "/").contains("..") else { completion(nil); return }
    var stale = false
    guard let root = try? URL(resolvingBookmarkData: source.bookmark,
      options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil,
      bookmarkDataIsStale: &stale) else { completion(nil); return }
    // Normalize the root once. Normalizing a missing child independently can
    // choose a different system path alias and incorrectly reject cached files.
    let baseURL = root.standardizedFileURL
    let file = baseURL.appendingPathComponent(relative)
    guard file.path.hasPrefix(baseURL.path + "/") else { completion(nil); return }
    let edge = Self.tiers.first { CGFloat($0) >= size * 2 } ?? Self.tiers.last!
    let base = "folder-grid-v3|" + String(decoding: try! JSONEncoder().encode([source.id, relative, revision]), as: UTF8.self)
    let epoch = storage.epoch
    let identity = base + "|\(edge)|\(epoch ?? -1)"
    if epoch != nil, let image = cache.object(forKey: identity as NSString) { completion(image); return }
    if let flight = flights[identity] {
      flight.callbacks[id] = completion; subscribers[id] = flight
      statistics.coalescedRequests += 1; return
    }
    guard flights.count < 256 else { completion(nil); return }
    let flight = Flight(identity: identity, base: base, edge: edge, epoch: epoch, root: root, file: file)
    flight.callbacks[id] = completion; subscribers[id] = flight
    flights[identity] = flight; reads.append(flight); pumpReads()
  }
  func cancel(_ id: UUID) {
    guard let flight = subscribers.removeValue(forKey: id) else { return }
    let identity = flight.identity
    flight.callbacks.removeValue(forKey: id)
    if flight.callbacks.isEmpty, let request = flight.quickLook {
      QLThumbnailGenerator.shared.cancel(request)
      flight.quickLook = nil
      let continuation = flight.quickLookResult; flight.quickLookResult = nil
      continuation?.resume(returning: nil)
    }
    if flight.callbacks.isEmpty && !flight.started {
      reads.removeAll { $0 === flight }; originals.removeAll { $0 === flight }
      flights.removeValue(forKey: identity)
    }
  }
  private func pumpReads() {
    while reading < 8, !reads.isEmpty {
      let flight = reads.removeFirst(); reading += 1; flight.started = true
      let storage = storage, base = flight.base, edge = flight.edge, epoch = flight.epoch
      Task {
        let hit = await Task.detached(priority: .userInitiated) { () -> (CGImage, Bool)? in
          guard let epoch, storage.isCurrent(epoch), Self.safeDirectory(storage.directory) else { return nil }
          // Equal/larger tiers are final. A smaller tier is only a placeholder.
          let candidates = Self.tiers.filter { $0 >= edge } + Self.tiers.filter { $0 < edge }.reversed()
          for tier in candidates {
            let key = base + "|\(tier)", path = Self.cacheURL(base + "|\(tier)", directory: storage.directory)
            guard let values = try? path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes <= MacDetailBitmap.limit,
              let data = try? Data(contentsOf: path), let image = MacDetailBitmap.decode(data, key: key),
              storage.isCurrent(epoch) else { continue }
            _ = storage.withCurrent(epoch) { try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path) }
            return (image, tier >= edge)
          }
          return nil
        }.value
        reading -= 1
        if let hit, let epoch, storage.isCurrent(epoch) {
          statistics.diskHits += 1
          if hit.1 { finish(flight, image: hit.0); pumpReads(); return }
          deliver(flight, image: NSImage(cgImage: hit.0, size: .zero))
        }
        if flight.callbacks.isEmpty { finish(flight, image: nil) }
        else { flight.started = false; originals.append(flight) }
        pumpReads(); pumpOriginals()
      }
    }
  }
  private func pumpOriginals() {
    while decoding < 3, publishing < 3, !originals.isEmpty {
      let flight = originals.removeFirst(); decoding += 1; flight.started = true
      statistics.originalLoads += 1
      let storage = storage, limit = budget() * 3 / 10
      Task {
        _ = flight.root.startAccessingSecurityScopedResource()
        let file = flight.file, edge = flight.edge
        let safe = await Task.detached(priority: .userInitiated) { file.resolvingSymlinksInPath().path == file.path }.value
        var bitmap: CGImage?
        if safe {
          if let originalLoader { bitmap = await originalLoader(file, edge) }
          else {
            bitmap = await Task.detached(priority: .userInitiated) { Self.still(file, edge: edge) }.value
            if bitmap == nil {
              let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: edge, height: edge), scale: 1, representationTypes: .thumbnail)
              if !flight.callbacks.isEmpty {
                bitmap = await withCheckedContinuation { continuation in
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
            }
          }
        }
        flight.root.stopAccessingSecurityScopedResource()
        decoding -= 1
        // Display is independent of encoding, eviction and writing. Publication
        // has its own bounded slots so it cannot grow unbounded decoded memory.
        publishing += 1
        finish(flight, image: bitmap); pumpOriginals()
        if let bitmap, let epoch = flight.epoch {
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
  private func deliver(_ flight: Flight, image: NSImage?) {
    for (id, callback) in flight.callbacks where subscribers[id] === flight { callback(image) }
  }
  private func finish(_ flight: Flight, image: CGImage?) {
    guard flights[flight.identity] === flight else { return }
    let result = image.map { NSImage(cgImage: $0, size: .zero) }
    if let image, let result, let epoch = flight.epoch, storage.isCurrent(epoch) {
      cache.setObject(result, forKey: flight.identity as NSString, cost: image.bytesPerRow * image.height)
    }
    flights.removeValue(forKey: flight.identity)
    let callbacks = flight.callbacks
    for (id, callback) in callbacks where subscribers[id] === flight {
      subscribers.removeValue(forKey: id)
      callback(result)
    }
  }
  private nonisolated static func still(_ file: URL, edge: Int) -> CGImage? {
    guard ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"].contains(file.pathExtension.lowercased()),
      let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(edge)
    let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(edge)
    let target = min(4096, max(Double(edge), Double(edge) * max(width, height) / max(1, min(width, height))))
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(ceil(target)),
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceShouldAllowFloat: true,
      kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR
    ] as CFDictionary)
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
      .task(id: "\(enabled)|\(source.id)|\(relative)|\(revision)|\(size)") {
        FileThumbnailPipeline.shared.cancel(token)
        image = nil; token = UUID()
        guard enabled else { return }
        let expected = token
        FileThumbnailPipeline.shared.request(id: expected, source: source, relative: relative,
          revision: revision, size: size) { result in
            guard token == expected else { return }; image = result
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
        MacFileThumbnail(source: source, relative: entry.relative, revision: entry.revision,
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

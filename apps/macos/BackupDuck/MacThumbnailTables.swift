import AppKit
import CryptoKit
import ImageIO
import Photos

/// Decoded thumbnails for the overview mosaics, shared with the iPhone's
/// `ThumbnailTable` (one memory-mapped file per size). A hit is a `CGImage`
/// backed by the mapping: no PhotoKit request, decode or copy, so a mosaic is
/// complete the instant it appears instead of filling in tile by tile.
/// The overview table covers the library at year-overview size; the detail table
/// keeps month-overview thumbnails. Rebuildable cache data in Caches.
enum MacThumbnailTables {
  /// `-no-thumbnail-table` turns the tables off for side-by-side measurement.
  static let enabled = !ProcessInfo.processInfo.arguments.contains("-no-thumbnail-table")
  static let overviewSide = 48, detailSide = 96
  static let storage = ThumbnailCacheStorage(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ThumbnailTables", isDirectory: true))
  static var directory: URL { storage.directory }
  /// The browsing-thumbnail limit in Settings, shared in name and default with
  /// the iPhone (1 GB). All rebuildable thumbnail files share this owner.
  static let budgetKey = "libraryThumbnailBudgetMB"
  static var budgetMB: Int {
    let stored = UserDefaults.standard.integer(forKey: budgetKey)
    return max(64, stored == 0 ? 1024 : stored)
  }
  static var tableUsage: Int { storage.tableUsage(active: [overview, detail]) }
  static var usage: Int { tableUsage + storage.detailUsage }
  static func setBudget(_ mb: Int) {
    storage.invalidate()
    UserDefaults.standard.set(mb, forKey: budgetKey)
    for (table, share) in [(overview, overviewShare), (detail, detailShare)] {
      let limit = Int(Double(mb * 1024 * 1024) * share) / table.entryBytes
      table.limit = limit
      // A lowered limit starts the table over; it refills newest first.
      if table.count > limit { table.clear(); prefilled = nil }
    }
  }
  static let overviewShare = 0.5, detailShare = 0.2
  static let overview = table("mac-overview", side: overviewSide, capacity: 131_072, share: overviewShare)
  static let detail = table("mac-detail", side: detailSide, capacity: 16_384, share: detailShare)
  /// The main display's own colour space. Core Animation colour-matched every
  /// sRGB tile to it on each commit, a third of the overview's scroll time; the
  /// tables store pixels already matched. A different display profile gets its
  /// own files, named by a short digest of the profile.
  static let space: CGColorSpace = NSScreen.main?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
  private static let spaceTag: String = {
    guard let data = space.copyICCData() as Data? else { return "srgb" }
    var hash: UInt64 = 1469598103934665603
    for byte in data { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
    return String(hash, radix: 36)
  }()
  private static func table(_ name: String, side: Int, capacity: Int, share: Double) -> ThumbnailTable {
    let table = ThumbnailTable(url: directory.appendingPathComponent("\(name)-\(spaceTag)-\(side).table"),
      side: side, capacity: capacity, space: space, storage: storage)
    table.limit = Int(Double(budgetMB * 1024 * 1024) * share) / table.entryBytes
    return table
  }
  static func key(_ asset: PHAsset) -> String { "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))" }
  /// The sharpest stored thumbnail for a displayed pixel width, and whether it
  /// is sharp enough to stand without a request. A small overview thumbnail
  /// still fills a month-overview tile at once; the sharper one follows.
  static func image(_ asset: PHAsset, pixels: CGFloat) -> (image: CGImage, sharp: Bool)? {
    image(key: key(asset), pixels: pixels)
  }
  static func image(key: String, pixels: CGFloat) -> (image: CGImage, sharp: Bool)? {
    guard enabled, pixels <= CGFloat(detailSide) * 1.25 else { return nil }
    if pixels > CGFloat(overviewSide) * 1.25 {
      if let sharp = detail.image(key) { return (sharp, true) }
      return overview.image(key).map { ($0, false) }
    }
    return (overview.image(key) ?? detail.image(key)).map { ($0, true) }
  }
  /// Any stored thumbnail, sharpest first: what a grid cell or a zoom tile
  /// shows at once while its own size loads, so no tile is ever blank for a
  /// photo the library has shown before.
  static func placeholder(_ asset: PHAsset) -> CGImage? {
    guard enabled else { return nil }
    let key = key(asset)
    return detail.image(key) ?? overview.image(key)
  }
  /// Stores a delivered thumbnail in each table it is sharp enough for. Grid
  /// cells deliver larger images; the table draws them down to its tile size.
  static func remember(_ asset: PHAsset, pixels: CGFloat = 0, image: CGImage) {
    guard enabled, let epoch = storage.epoch else { return }
    let key = key(asset), edge = min(image.width, image.height)
    overview.writes.async {
      if edge * 5 >= overviewSide * 4 { overview.store(key, image: image, generation: epoch) }
      if edge * 5 >= detailSide * 4 { detail.store(key, image: image, generation: epoch) }
    }
  }
  static func contains(_ asset: PHAsset) -> Bool { enabled && overview.contains(key(asset)) }
  /// Clears both tables and the in-memory thumbnails; the next library visit
  /// refills the overview from local renditions.
  @MainActor static func clear() async -> String? {
    guard let epoch = storage.beginClear() else { return nil }
    defer { storage.endClear(epoch) }
    prefillTask?.cancel()
    let failure = await Task.detached(priority: .userInitiated) {
      let tableFailure = storage.clearTables(active: [overview, detail])
      let detailFailure = storage.clearDetails()
      return tableFailure ?? detailFailure
    }.value
    prefilled = nil
    await MacFileDetailPosterCache.shared.clearMemory()
    NotificationCenter.default.post(name: Notification.Name("LibraryThumbnailsCleared"), object: nil)
    return failure
  }
  nonisolated(unsafe) private static var prefilled: ObjectIdentifier?
  nonisolated(unsafe) private static var prefillTask: Task<Void, Never>?
  /// Fills the overview table for the whole library from local renditions, newest
  /// first, in the background. Nothing is downloaded and nothing is requested
  /// for assets already stored.
  @MainActor static func prefill(_ fetch: PHFetchResult<PHAsset>?) {
    guard BackupEnvironment.usesPhotoLibrary, enabled, let fetch, prefilled != ObjectIdentifier(fetch), overview.available, let epoch = storage.epoch else { return }
    prefilled = ObjectIdentifier(fetch)
    prefillTask?.cancel()
    prefillTask = Task.detached(priority: .utility) {
      let manager = PHImageManager.default()
      let options = PHImageRequestOptions()
      options.deliveryMode = .fastFormat
      options.resizeMode = .fast
      options.isSynchronous = true
      options.isNetworkAccessAllowed = false
      let size = CGSize(width: overviewSide * 2, height: overviewSide * 2)
      let total = fetch.count, id = ObjectIdentifier(fetch)
      var facts = [Fact?](repeating: nil, count: total)
      var index = 0
      while index < total, !Task.isCancelled, storage.isCurrent(epoch) {
        let end = min(total, index + 256)
        let found = await withTaskGroup(of: [(Int, Fact)].self) { group in
          for lane in 0..<3 {
            group.addTask {
              var out: [(Int, Fact)] = []
              var i = index + lane
              while i < end, !Task.isCancelled, storage.isCurrent(epoch) {
                autoreleasepool {
                  let asset = fetch.object(at: i)
                  let key = key(asset)
                  out.append((i, Fact(key: key, date: asset.creationDate)))
                  if !overview.contains(key) {
                    manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                      guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                      overview.store(key, image: cg, generation: epoch)
                    }
                  }
                }
                i += 3
              }
              return out
            }
          }
          return await group.reduce(into: []) { $0 += $1 }
        }
        for (i, fact) in found { facts[i] = fact }
        index = end
        try? await Task.sleep(nanoseconds: 20_000_000)
      }
      guard !Task.isCancelled, storage.isCurrent(epoch) else { return }
      let done = facts
      await MainActor.run { if prefilled == id { known = (id, done) } }
    }
  }
  /// Table key and capture date by fetch index, gathered by the prefill pass that
  /// already reads every asset off the main thread. The overview mosaics scroll
  /// through thousands of photos a second; faulting each `PHAsset` there cost a
  /// tenth of the main thread.
  struct Fact: Sendable { let key: String; let date: Date? }
  @MainActor private static var known: (fetch: ObjectIdentifier, facts: [Fact?])?
  @MainActor static func fact(_ fetch: PHFetchResult<PHAsset>?, at index: Int) -> Fact? {
    guard let fetch, let known, known.fetch == ObjectIdentifier(fetch), known.facts.indices.contains(index)
    else { return nil }
    return known.facts[index]
  }
}

/// File-backed detail uses the same lossless records, storage epoch and budget
/// as PhotoKit detail. Serial actor isolation keeps decoding off the UI thread.
actor MacFileDetailPosterCache {
  static let shared = MacFileDetailPosterCache()
  private struct Retained {
    let image: CGImage
    var accessed: Date
    let bytes: Int
  }
  private var retained: [String: Retained] = [:]
  private var retainedBytes = 0
  private var retainedEpoch: Int?
  private let storage: ThumbnailCacheStorage
  private var pressure: DispatchSourceMemoryPressure?
  init(storage: ThumbnailCacheStorage = MacThumbnailTables.storage) { self.storage = storage }
  func clearMemory() { retained.removeAll(); retainedBytes = 0 }
  private func observePressure() {
    guard pressure == nil else { return }
    let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
    source.setEventHandler { [weak self] in Task { await self?.clearMemory() } }
    source.resume(); pressure = source
  }
  private static func stamp(_ file: URL) -> String? {
    var info = stat()
    guard lstat(file.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
    return "\(info.st_dev)|\(info.st_ino)|\(info.st_size)|\(info.st_mtimespec.tv_sec)|\(info.st_mtimespec.tv_nsec)|\(info.st_ctimespec.tv_sec)|\(info.st_ctimespec.tv_nsec)"
  }
  private static func safe(_ file: URL, root: URL) -> Bool {
    file.path.hasPrefix(root.standardizedFileURL.path + "/")
      && file.resolvingSymlinksInPath().path == file.path
      && FileManager.default.isReadableFile(atPath: file.path)
  }
  func load(photo: FolderPhoto, file: URL, root: URL, target: MacDetailPosterTarget,
    epoch: Int?, budget: Int, reserved: Int) -> CGImage? {
    observePressure()
    if retainedEpoch != epoch { clearMemory(); retainedEpoch = epoch }
    guard !Task.isCancelled else { return nil }
    _ = root.startAccessingSecurityScopedResource()
    defer { root.stopAccessingSecurityScopedResource() }
    guard Self.safe(file, root: root), let stamp = Self.stamp(file) else { return nil }
    let fields = [photo.folder_id, photo.source_id, photo.relative, photo.revision, stamp,
      String(Int(ceil(target.pixels.width))), String(Int(ceil(target.pixels.height))), target.profile]
    let key = "folder-detail-v1|" + String(decoding: try! JSONEncoder().encode(fields), as: UTF8.self)
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    let path = storage.directory.appendingPathComponent(digest + ".detail")
    let current = { !Task.isCancelled && Self.safe(file, root: root) && Self.stamp(file) == stamp }
    if let epoch, storage.isCurrent(epoch), var hit = retained[key],
      Date().timeIntervalSince(hit.accessed) <= MacDetailPosterCache.retention, current() {
      hit.accessed = Date(); retained[key] = hit
      _ = storage.withCurrent(epoch) { try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path) }
      return hit.image
    }
    var image: CGImage?
    var cacheDirectoryInfo = stat()
    let regularCacheDirectory = lstat(storage.directory.path, &cacheDirectoryInfo) == 0
      && (cacheDirectoryInfo.st_mode & S_IFMT) == S_IFDIR
    if let epoch, storage.isCurrent(epoch), regularCacheDirectory,
      let values = try? path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
      values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size <= MacDetailBitmap.limit,
      let accessed = values.contentModificationDate,
      Date().timeIntervalSince(accessed) <= MacDetailPosterCache.retention,
      let data = try? Data(contentsOf: path) {
      image = MacDetailBitmap.decode(data, key: key)
    }
    let diskHit = image != nil
    if image == nil {
      guard current(), let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
      let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
      let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
      let rotated = (5...8).contains(orientation)
      let w = rotated ? height : width, h = rotated ? width : height
      guard w > 0, h > 0 else { return nil }
      let scale = min(1, target.pixels.width / w, target.pixels.height / h, 4096 / max(w, h))
      let edge = max(1, Int(ceil(max(w, h) * scale)))
      image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: edge,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceShouldAllowFloat: true,
        kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR
      ] as CFDictionary)
    }
    guard let image, current() else { return nil }
    guard let epoch, storage.isCurrent(epoch) else { return image }
    let bytes = image.bytesPerRow * image.height
    if bytes <= MacDetailBitmap.limit {
      if let old = retained.removeValue(forKey: key) { retainedBytes -= old.bytes }
      while !retained.isEmpty, retainedBytes + bytes > MacDetailBitmap.limit || retained.count >= 32 {
        guard let oldest = retained.min(by: { $0.value.accessed < $1.value.accessed })?.key,
          let removed = retained.removeValue(forKey: oldest) else { break }
        retainedBytes -= removed.bytes
      }
      retained[key] = Retained(image: image, accessed: Date(), bytes: bytes); retainedBytes += bytes
    }
    if diskHit {
      _ = storage.withCurrent(epoch) { try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path) }
    } else if let data = MacDetailBitmap.encode(image, key: key), current() {
      _ = storage.withCurrent(epoch) {
        guard current() else { return }
        Self.publish(data, path: path, storage: storage, limit: max(0, budget - reserved))
      }
    }
    return current() ? image : nil
  }
  private static func publish(_ data: Data, path: URL, storage: ThumbnailCacheStorage, limit: Int) {
    guard data.count <= limit else { return }
    var directoryInfo = stat()
    if lstat(storage.directory.path, &directoryInfo) != 0 {
      guard errno == ENOENT else { return }
      try? FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
    }
    guard lstat(storage.directory.path, &directoryInfo) == 0, (directoryInfo.st_mode & S_IFMT) == S_IFDIR else { return }
    if let free = try? storage.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
      free < Int64(data.count) + 128 * 1024 * 1024 { return }
    let files = (try? FileManager.default.contentsOfDirectory(at: storage.directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])) ?? []
    var entries = files.compactMap { file -> (URL, Int, Date)? in
      guard file.lastPathComponent.range(of: "^[0-9a-f]{64}\\.detail$", options: .regularExpression) != nil,
        let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
        values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
      return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
    }.sorted { $0.2 < $1.2 }
    var used = storage.detailUsage
    let replaced = entries.first { $0.0 == path }?.1 ?? 0
    entries.removeAll { $0.0 == path }
    while !entries.isEmpty, used - replaced + data.count > limit
      || Date().timeIntervalSince(entries[0].2) > MacDetailPosterCache.retention {
      let oldest = entries.removeFirst()
      if (try? FileManager.default.removeItem(at: oldest.0)) != nil { used -= oldest.1 }
    }
    guard used - replaced + data.count <= limit else { return }
    try? data.write(to: path, options: .atomic)
  }
}

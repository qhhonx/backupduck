import AppKit
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
  static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ThumbnailTables", isDirectory: true)
  /// The browsing-thumbnail limit in Settings, shared in name and default with
  /// the iPhone (1 GB). The Mac keeps no rendition files; the tables are its cache.
  static let budgetKey = "libraryThumbnailBudgetMB"
  static var budgetMB: Int {
    let stored = UserDefaults.standard.integer(forKey: budgetKey)
    return max(64, stored == 0 ? 1024 : stored)
  }
  static var usage: Int { overview.usage + detail.usage }
  static func setBudget(_ mb: Int) {
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
      side: side, capacity: capacity, space: space)
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
    guard enabled else { return }
    let key = key(asset), edge = min(image.width, image.height)
    overview.writes.async {
      if edge * 5 >= overviewSide * 4 { overview.store(key, image: image) }
      if edge * 5 >= detailSide * 4 { detail.store(key, image: image) }
    }
  }
  static func contains(_ asset: PHAsset) -> Bool { enabled && overview.contains(key(asset)) }
  /// Clears both tables and the in-memory thumbnails; the next library visit
  /// refills the overview from local renditions.
  @MainActor static func clear() async {
    prefillTask?.cancel()
    await Task.detached(priority: .userInitiated) { overview.clear(); detail.clear() }.value
    prefilled = nil
    NotificationCenter.default.post(name: Notification.Name("LibraryThumbnailsCleared"), object: nil)
  }
  nonisolated(unsafe) private static var prefilled: ObjectIdentifier?
  nonisolated(unsafe) private static var prefillTask: Task<Void, Never>?
  /// Fills the overview table for the whole library from local renditions, newest
  /// first, in the background. Nothing is downloaded and nothing is requested
  /// for assets already stored.
  @MainActor static func prefill(_ fetch: PHFetchResult<PHAsset>?) {
    guard enabled, let fetch, prefilled != ObjectIdentifier(fetch), overview.available else { return }
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
      while index < total, !Task.isCancelled {
        let end = min(total, index + 256)
        let found = await withTaskGroup(of: [(Int, Fact)].self) { group in
          for lane in 0..<3 {
            group.addTask {
              var out: [(Int, Fact)] = []
              var i = index + lane
              while i < end, !Task.isCancelled {
                autoreleasepool {
                  let asset = fetch.object(at: i)
                  let key = key(asset)
                  out.append((i, Fact(key: key, date: asset.creationDate)))
                  if !overview.contains(key) {
                    manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                      guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                      overview.store(key, image: cg)
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
      guard !Task.isCancelled else { return }
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

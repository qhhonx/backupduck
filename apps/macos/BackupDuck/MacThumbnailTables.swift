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
  private static let budget = 1024 * 1024 * 1024
  static let overview = table("mac-overview", side: overviewSide, capacity: 131_072, share: 0.5)
  static let detail = table("mac-detail", side: detailSide, capacity: 16_384, share: 0.2)
  private static func table(_ name: String, side: Int, capacity: Int, share: Double) -> ThumbnailTable {
    let table = ThumbnailTable(url: directory.appendingPathComponent("\(name)-\(side).table"), side: side, capacity: capacity)
    table.limit = Int(Double(budget) * share) / table.entryBytes
    return table
  }
  static func key(_ asset: PHAsset) -> String { "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))" }
  /// The sharpest stored thumbnail for a displayed pixel width, and whether it
  /// is sharp enough to stand without a request. A small overview thumbnail
  /// still fills a month-overview tile at once; the sharper one follows.
  static func image(_ asset: PHAsset, pixels: CGFloat) -> (image: CGImage, sharp: Bool)? {
    guard enabled, pixels <= CGFloat(detailSide) * 1.25 else { return nil }
    let key = key(asset)
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
  static func clear() { overview.clear(); detail.clear() }
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
      let total = fetch.count
      var index = 0
      while index < total, !Task.isCancelled {
        let end = min(total, index + 256)
        await withTaskGroup(of: Void.self) { group in
          for lane in 0..<3 {
            group.addTask {
              var i = index + lane
              while i < end, !Task.isCancelled {
                autoreleasepool {
                  let asset = fetch.object(at: i)
                  let key = key(asset)
                  if !overview.contains(key) {
                    manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                      guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                      overview.store(key, image: cg)
                    }
                  }
                }
                i += 3
              }
            }
          }
        }
        index = end
        try? await Task.sleep(nanoseconds: 20_000_000)
      }
    }
  }
}

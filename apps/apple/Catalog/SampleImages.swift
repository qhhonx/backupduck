import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Catalog-only local sample media, with procedural landscapes as fallback.
/// Identifiers use the same fixed UTF-8 hash and manifest order on every platform.
enum SampleImages {
  private struct Manifest: Decodable {
    let photos: [Photo]
    struct Photo: Decodable { let file: String; let taken: String? }
  }
  private struct Photo {
    let url: URL
    let taken: Date?
  }
  private final class Pool: @unchecked Sendable {
    let photos: [Photo]
    init(_ photos: [Photo]) { self.photos = photos }
    func photo(for id: String) -> Photo { photos[Int(stableHash(id) % UInt64(photos.count))] }
  }
  // The providers are synchronous. Serialize cache misses to avoid duplicate decodes;
  // cache by pool file rather than scenario ID, and never decode an original at full size.
  private final class Bitmaps: @unchecked Sendable {
    let lock = NSLock()
    let thumbnails = NSCache<NSString, CGImage>()
    let details = NSCache<NSString, CGImage>()
    let synthetic = NSCache<NSString, CGImage>()
    init() {
      thumbnails.totalCostLimit = 16 * 1024 * 1024
      details.totalCostLimit = 32 * 1024 * 1024
      synthetic.totalCostLimit = 4 * 1024 * 1024
    }
  }
  private static let bitmaps = Bitmaps()
  private static let pool: Pool? = loadPool()

  static func stableHash(_ id: String) -> UInt64 {
    id.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
  }

  private static func loadPool() -> Pool? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let flag = arguments.firstIndex(of: "-mediaDir"), arguments.indices.contains(flag + 1),
      (arguments[flag + 1] as NSString).isAbsolutePath else { return nil }
    let root = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    do {
      let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
      let photos = try manifest.photos.map { row -> Photo in
        let url = root.appendingPathComponent(row.file).resolvingSymlinksInPath().standardizedFileURL
        guard !(row.file as NSString).isAbsolutePath, !row.file.isEmpty,
          url.path.hasPrefix(root.path + "/") else { throw CocoaError(.fileReadCorruptFile) }
        return Photo(url: url, taken: row.taken.flatMap(parseDate))
      }
      guard !photos.isEmpty else { return nil }
      print("Catalog media: \(photos.count) pool entries; synthetic fallback enabled")
      return Pool(photos)
    } catch {
      print("Catalog media manifest unavailable; using synthetic photos")
      return nil
    }
  }

  private static func parseDate(_ text: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: text) { return date }
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: text) { return date }
    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.calendar = Calendar(identifier: .gregorian)
    local.timeZone = .current
    local.isLenient = false
    for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
      local.dateFormat = format
      if let date = local.date(from: text) { return date }
    }
    return nil
  }

  static func takenDate(for id: String) -> Date? { pool?.photo(for: id).taken }

  /// Fill only missing capture metadata, after the scenario's relative-time shift.
  /// Receipt, publication and other event timestamps keep their scripted values.
  static func fillingDates(_ value: Any?) -> Any? {
    guard pool != nil else { return value }
    if let list = value as? [Any] { return list.map { fillingDates($0) ?? NSNull() } }
    guard let object = value as? [String: Any] else { return value }
    var result = object.mapValues { fillingDates($0) ?? NSNull() }
    if let id = object["source_id"] as? String, object["resources"] != nil,
      let date = takenDate(for: id) {
      var metadata = object["metadata"] as? [String: Any] ?? [:]
      let existing = metadata["created_at_ms"].flatMap { Double("\($0)") } ?? 0
      if existing <= 0 {
        metadata["created_at_ms"] = String(Int64(date.timeIntervalSince1970 * 1000))
        result["metadata"] = metadata
      }
    }
    return result
  }

  static func image(for id: String) -> Image? {
    cgImage(for: id).map { Image(decorative: $0, scale: 1) }
  }

  static func cgImage(for id: String, maxPixelSize: Int = 480) -> CGImage? {
    let edge = ((min(2048, max(1, maxPixelSize)) + 63) / 64) * 64
    return bitmaps.lock.withLock {
      if let photo = pool?.photo(for: id) {
        let key = "\(photo.url.path)|\(edge)" as NSString
        let cache = edge <= 512 ? bitmaps.thumbnails : bitmaps.details
        if let picture = cache.object(forKey: key) { return picture }
        if let source = CGImageSourceCreateWithURL(photo.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: edge
          ] as CFDictionary) {
          cache.setObject(picture, forKey: key, cost: picture.bytesPerRow * picture.height)
          return picture
        }
      }
      let key = id as NSString
      if let picture = bitmaps.synthetic.object(forKey: key) { return picture }
      guard let picture = draw(seed: stableHash(id)) else { return nil }
      bitmaps.synthetic.setObject(picture, forKey: key, cost: picture.bytesPerRow * picture.height)
      return picture
    }
  }

  // Sky top, sky bottom, sun, far land, near land.
  private static let scenes: [[UInt32]] = [
    [0x7FB3E6, 0xF3D9B1, 0xFFE9A8, 0x6E8F72, 0x3F5E45],
    [0x2E3A6B, 0xE98C6B, 0xFFD27F, 0x5B4A6B, 0x2C2540],
    [0xA7D3F2, 0xE8F4FB, 0xFFFFFF, 0x9DB7C9, 0x557A95],
    [0xF6C8A8, 0xFBE7D3, 0xFFF4D6, 0xC79A6E, 0x8A5A3B],
    [0x94C5B8, 0xE4F1EC, 0xFFFBEA, 0x5E9C7F, 0x2F6B53],
    [0x1D2B4F, 0x4F6FA8, 0xF2F2E9, 0x2B3A5C, 0x121A30],
  ]

  private static func draw(seed: UInt64) -> CGImage? {
    let size = 480
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    var state = seed
    func next() -> CGFloat { state = state &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(state >> 33) / CGFloat(1 << 31) }
    let scene = scenes[Int(seed % UInt64(scenes.count))].map { value in
      CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    let s = CGFloat(size)
    if let sky = CGGradient(colorsSpace: nil, colors: [scene[1], scene[0]] as CFArray, locations: [0, 1]) {
      context.drawLinearGradient(sky, start: CGPoint(x: 0, y: s * 0.35), end: CGPoint(x: 0, y: s), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    let sun = 18 + next() * 26
    context.setFillColor(scene[2])
    context.fillEllipse(in: CGRect(x: s * (0.15 + next() * 0.6), y: s * (0.55 + next() * 0.25), width: sun, height: sun))
    for (layer, base) in [(3, 0.38 + next() * 0.15), (4, 0.18 + next() * 0.12)] {
      context.setFillColor(scene[layer])
      context.beginPath()
      context.move(to: CGPoint(x: 0, y: 0))
      context.addLine(to: CGPoint(x: 0, y: s * base))
      let peaks = 3 + Int(next() * 3)
      for i in 1...peaks {
        let x = s * CGFloat(i) / CGFloat(peaks)
        context.addQuadCurve(to: CGPoint(x: x, y: s * (base + (next() - 0.5) * 0.12)),
          control: CGPoint(x: x - s / CGFloat(peaks * 2), y: s * (base + 0.04 + next() * 0.14)))
      }
      context.addLine(to: CGPoint(x: s, y: 0))
      context.closePath()
      context.fillPath()
    }
    return context.makeImage()
  }
}

import CoreGraphics
import SwiftUI

/// Synthetic "photos" for catalog scenarios: simple landscapes drawn from the
/// photo identifier, so pages that frame photos (P1) can be reviewed without
/// reading any real photo library. Same identifier, same picture.
enum SampleImages {
  nonisolated(unsafe) private static var cache: [String: Image] = [:]

  static func image(for id: String) -> Image? {
    if let cached = cache[id] { return cached }
    guard let picture = draw(seed: id.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }) else { return nil }
    let image = Image(decorative: picture, scale: 1)
    cache[id] = image
    return image
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

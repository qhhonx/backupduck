// Derive system templates from the approved AppIcon pixels, never a redrawn duck.
import AppKit
import CryptoKit
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = try Data(contentsOf: root.appendingPathComponent("assets/AppIcon.png"))
let original = NSBitmapImageRep(data: source)!
let width = original.pixelsWide, height = original.pixelsHigh
let mask = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
  for x in 0..<width {
    let color = original.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
    // Ivory is neutral. Original blue wing and eye become transparent negative
    // space; the warm body and bill share the system template tint.
    let saturation = (max(r, g, b) - min(r, g, b)) / max(max(r, g, b), 0.001)
    let opacity = r > b && r >= g * 0.95 ? min(1, max(0, (saturation - 0.08) / 0.25)) : 0
    let offset = y * mask.bytesPerRow + x * 4
    mask.bitmapData![offset] = 0; mask.bitmapData![offset + 1] = 0; mask.bitmapData![offset + 2] = 0
    mask.bitmapData![offset + 3] = UInt8((opacity * 255).rounded())
    if opacity > 0.5 { minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y) }
  }
}
precondition(minX < maxX && minY < maxY, "Brand source must contain the approved warm duck mark")
let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
let cropped = mask.cgImage!.cropping(to: bounds)!
let mark = NSImage(cgImage: cropped, size: bounds.size)
func template(canvas: Int, markSize: CGFloat) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  let scale = markSize / max(bounds.width, bounds.height)
  let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSGraphicsContext.current!.imageInterpolation = .high
  mark.draw(in: CGRect(x: (CGFloat(canvas) - size.width) / 2,
    y: (CGFloat(canvas) - size.height) / 2, width: size.width, height: size.height))
  NSGraphicsContext.restoreGraphicsState()
  return rep
}
let menu = template(canvas: 400, markSize: 360)
let png = menu.representation(using: .png, properties: [:])!
try png.write(to: root.appendingPathComponent("assets/BackupDuckMonochrome.png"))
let output = root.appendingPathComponent("apps/apple/Resources/DuckMenuBar.pdf")
let consumer = CGDataConsumer(url: output as CFURL)!
var media = CGRect(x: 0, y: 0, width: 20, height: 20)
let context = CGContext(consumer: consumer, mediaBox: &media, nil)!
context.beginPDFPage(nil); context.interpolationQuality = .high
context.draw(menu.cgImage!, in: media)
context.endPDFPage(); context.closePDF()
// Prototype and Android consume the same original-pixel mask, no drawn path.
let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 20 20\"><image width=\"20\" height=\"20\" href=\"data:image/png;base64,\(png.base64EncodedString())\"/></svg>"
try svg.write(to: root.appendingPathComponent("assets/BackupDuckMonochrome.svg"), atomically: true, encoding: .utf8)
let android = template(canvas: 432, markSize: 248).representation(using: .png, properties: [:])!
try android.write(to: root.appendingPathComponent("apps/android/app/src/main/res/drawable-nodpi/ic_launcher_duck_monochrome.png"))
// Notification icons use opaque alpha geometry; theme-dependent strokes can
// disappear in system chrome. Keep the original mark on a compact 24 dp canvas.
for (density, pixels) in [("mdpi", 24), ("hdpi", 36), ("xhdpi", 48), ("xxhdpi", 72), ("xxxhdpi", 96)] {
  let directory = root.appendingPathComponent("apps/android/app/src/main/res/drawable-\(density)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let notification = template(canvas: pixels, markSize: CGFloat(pixels) * 0.875)
  try notification.representation(using: .png, properties: [:])!
    .write(to: directory.appendingPathComponent("ic_notification_duck.png"))
}
print("Exported original AppIcon mark: \(Int(bounds.width))x\(Int(bounds.height)); source SHA256 \(SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined())")

import AppKit
import Compression
import CryptoKit

print("reduceMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion), lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled), screens=\(NSScreen.screens.count)")

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
      image.bytesPerRow <= limit / image.height, let raw = image.dataProvider?.data else { print("codec guard 1 failed"); return nil }
    let count = image.bytesPerRow * image.height
    guard CFDataGetLength(raw) >= count else { print("codec guard 2 failed"); return nil }
    let bytes = Data((raw as Data).prefix(count))
    var compressed = Data(count: count + 4096)
    let size = compressed.withUnsafeMutableBytes { output in
      bytes.withUnsafeBytes { input in
        compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
          input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZFSE)
      }
    }
    guard size > 0 else { print("codec guard 3 failed"); return nil }
    compressed.count = size
    let record = Record(key: key, width: image.width, height: image.height, rowBytes: image.bytesPerRow,
      componentBits: image.bitsPerComponent, pixelBits: image.bitsPerPixel, bitmapInfo: image.bitmapInfo.rawValue,
      intent: image.renderingIntent.rawValue, colorName: space.name as String?,
      colorProfile: space.copyICCData() as Data?, headroom: image.contentHeadroom,
      checksum: Data(SHA256.hash(data: bytes)), pixels: compressed)
    let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
    guard let data = try? encoder.encode(record), data.count <= limit,
      let restored = decode(data, key: key), let restoredSpace = restored.colorSpace,
      CFEqual(space, restoredSpace), restored.bitmapInfo == image.bitmapInfo else { print("codec guard 4 failed"); return nil }
    return data
  }
  static func decode(_ data: Data, key: String) -> CGImage? {
    guard data.count <= limit, let record = try? PropertyListDecoder().decode(Record.self, from: data),
      record.key == key, record.width > 0, record.height > 0, record.width <= 16384, record.height <= 16384,
      [8, 16, 32].contains(record.componentBits), record.pixelBits > 0, record.pixelBits <= 128,
      record.rowBytes >= (record.width * record.pixelBits + 7) / 8,
      record.rowBytes <= limit / record.height, record.headroom.isFinite, record.headroom >= 0,
      record.checksum.count == SHA256.byteCount, !record.pixels.isEmpty,
      let intent = CGColorRenderingIntent(rawValue: record.intent) else { print("codec guard 5 failed"); return nil }
    let space = record.colorName.flatMap { CGColorSpace(name: $0 as CFString) }
      ?? record.colorProfile.flatMap { CGColorSpace(iccData: $0 as CFData) }
    guard let space, space.model == .rgb else { print("codec guard 6 failed"); return nil }
    if let profile = record.colorProfile, space.copyICCData() as Data? != profile { return nil }
    let count = record.rowBytes * record.height
    var raw = Data(count: count + 1)
    let decoded = raw.withUnsafeMutableBytes { output in
      record.pixels.withUnsafeBytes { input in
        compression_decode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
          input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZFSE)
      }
    }
    guard decoded == count else { print("codec guard 7 failed"); return nil }
    raw.count = count
    guard Data(SHA256.hash(data: raw)) == record.checksum,
      let provider = CGDataProvider(data: raw as CFData),
      var image = CGImage(width: record.width, height: record.height, bitsPerComponent: record.componentBits,
        bitsPerPixel: record.pixelBits, bytesPerRow: record.rowBytes, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: record.bitmapInfo), provider: provider,
        decode: nil, shouldInterpolate: true, intent: intent) else { print("codec guard 8 failed"); return nil }
    if record.headroom > 0, image.contentHeadroom != record.headroom {
      guard let tagged = CGImageCreateCopyWithContentHeadroom(record.headroom, image) else { print("codec guard 9 failed"); return nil }
      image = tagged
    }
    return image
  }
}

for name in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
  let space = CGColorSpace(name: name)!
  let context = CGContext(data: nil, width: 40, height: 24, bitsPerComponent: 8,
    bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(colorSpace: space, components: [0.2, 0.5, 0.8, 1])!)
  context.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
  let image = context.makeImage()!
  let original = image.colorSpace!
  let named = original.name.flatMap { CGColorSpace(name: $0) }
  let profile = original.copyICCData()
  let fromProfile = profile.flatMap { CGColorSpace(iccData: $0) }
  let namedProfile = named?.copyICCData()
  let originalProfileData = profile as Data? ?? Data()
  let namedProfileData = namedProfile as Data? ?? Data()
  let differing = zip(originalProfileData, namedProfileData).enumerated().compactMap { $0.element.0 == $0.element.1 ? nil : $0.offset }
  print("space=\(name) original=\(String(describing: original.name)) namedEqual=\(named.map { CFEqual(original, $0) } ?? false) profileEqual=\(fromProfile.map { CFEqual(original, $0) } ?? false) profileSizes=\(originalProfileData.count)/\(namedProfileData.count) differentBytes=\(differing.prefix(25)) bitmapInfo=\(image.bitmapInfo.rawValue) headroom=\(image.contentHeadroom)")
  guard let record = MacDetailBitmap.encode(image, key: "probe"),
    let restored = MacDetailBitmap.decode(record, key: "probe"),
    restored.contentHeadroom == image.contentHeadroom else { fatalError("SDR bitmap did not round-trip") }
  print("encoded=\(record.count)")
}

enum DuckSpacing { static let large: CGFloat = 24 }
enum MacGridFooter {
  static let minimumHeight: CGFloat = 56
  static let topInset: CGFloat = 14
  static func attributed(total: String, notes: [String]) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping
    paragraph.firstLineHeadIndent = DuckSpacing.large; paragraph.headIndent = DuckSpacing.large
    paragraph.tailIndent = -DuckSpacing.large
    // An empty paragraph can take a different font metric on older AppKit.
    let countLine = total.isEmpty && !notes.isEmpty ? "\u{00A0}" : total
    let text = ([countLine] + notes).joined(separator: "\n")
    let result = NSMutableAttributedString(string: text, attributes: [
      .font: NSFont.preferredFont(forTextStyle: .caption1),
      .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
    if !total.isEmpty {
      result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: (total as NSString).length))
    }
    return result
  }
  static func textHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
    let cell = NSTextFieldCell(textCell: "")
    cell.attributedStringValue = text
    cell.wraps = true; cell.isScrollable = false; cell.usesSingleLineMode = false
    cell.lineBreakMode = .byWordWrapping
    return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(1, width),
      height: .greatestFiniteMagnitude)).height)
  }
  static func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
    max(minimumHeight, textHeight(text, width: width) + topInset * 2)
  }
}

let notes = ["To a receiver with a long device name", "Check cloud backup after reviewing the receiving device."]
let waiting = MacGridFooter.height(MacGridFooter.attributed(total: "", notes: notes), width: 220)
let ready = MacGridFooter.height(MacGridFooter.attributed(total: "150 items", notes: notes), width: 220)
print("footer waiting=\(waiting) ready=\(ready)")
precondition(waiting == ready, "The footer must reserve the same count line while waiting")

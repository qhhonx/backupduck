import CoreImage.CIFilterBuiltins
import SwiftUI

/// The approved duck poses (design/constitution.md#brand-character). Decorative:
/// hidden from assistive technology. At most one per screen.
struct DuckIllustration: View {
  enum Pose: String { case welcome, pairing, empty, done, waiting, premium }
  let pose: Pose
  var size: CGFloat = 120
  var body: some View {
    Image("Duck" + pose.rawValue.capitalized)
      .resizable().scaledToFit()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

/// First-run step marks: a yellow circle, the blue wing and an orange sparkle,
/// sized to the same visual weight. The numeral sits on each mark's horizontal
/// shared axis so the three line up (the wing is shifted so its thick front
/// carries the numeral), and keeps one size across marks.
struct DuckStepMark: View {
  let number: Int
  var scale: CGFloat = 1
  @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

  var body: some View {
    let s = unit * scale
    ZStack {
      switch number {
      case 1: Image("MarkCircle").resizable().frame(width: 36 * s, height: 36 * s)
      // The wing's thick front sits on the shared axis, so its numeral stays inside the shape.
      case 2: Image("MarkWing").resizable().frame(width: 44 * s, height: 22 * s).offset(x: 7.8 * s)
      default: Image("MarkSparkle").resizable().frame(width: 40 * s, height: 40 * s)
      }
      Text(number.formatted())
        .font(.system(size: 17 * s, weight: .bold, design: .rounded)) // design-exception: numeral sized to its mark, scaled with Dynamic Type
        .foregroundStyle(number == 1 ? DuckBrand.Illustration.ink : .white) // design-exception: numeral on a brand mark
        .offset(y: number == 2 ? 3 * s : 0)
    }
    .frame(width: 54 * s, height: 40 * s)
    .accessibilityHidden(true)
  }
}

/// A QR code for a short text, drawn crisply at any size.
struct DuckQRCode: View {
  let text: String
  var body: some View {
    if let image = Self.render(text) {
      Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
        .accessibilityLabel(Text(verbatim: text))
    }
  }
  static func render(_ text: String) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    return CIContext().createCGImage(output, from: output.extent)
  }
}

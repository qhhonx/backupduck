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

/// Catalog-only opt-in to the same solid-mark fallback, without changing OS settings.
private struct DuckStepMarkReducedTransparencyKey: EnvironmentKey {
  static let defaultValue = false
}
extension EnvironmentValues {
  var duckStepMarkReducedTransparency: Bool {
    get { self[DuckStepMarkReducedTransparencyKey.self] }
    set { self[DuckStepMarkReducedTransparencyKey.self] = newValue }
  }
}

/// V6: numeral-free marks, optically balanced within one shared centre slot.
/// The source wing keeps its original aspect ratio and has no positional offset.
struct DuckStepMark: View {
  let number: Int
  var scale: CGFloat = 1
  var strength: Double = 1
  @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.duckStepMarkReducedTransparency) private var previewReduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  private var color: Color {
    switch number {
    case 1: DuckBrand.duckYellow
    case 2: DuckBrand.wingBlue
    default: DuckBrand.beakOrange
    }
  }
  var body: some View {
    let s = unit * scale
    let weight = strength < 1 && (reduceTransparency || previewReduceTransparency || contrast == .increased) ? 0.55 : strength
    // Blend onto the opaque page role before masking: faint marks never rely on
    // translucent material, and accessibility modes strengthen their silhouette.
    ZStack {
      DuckRole.background
      color.opacity(weight)
    }
    .mask {
      switch number {
      case 1: Image("MarkCircle").resizable().frame(width: 32 * s, height: 32 * s)
      case 2: Image("MarkWing").resizable().scaledToFit().frame(width: 48 * s, height: 24 * s)
      default: Image("MarkSparkle").resizable().frame(width: 44 * s, height: 44 * s)
      }
    }
    .frame(width: 54 * s, height: 44 * s)
    .accessibilityHidden(true)
  }
}

/// One stable row, with a single localized progress element for assistive technology.
struct DuckStepProgress: View {
  let current: Int
  var body: some View {
    HStack(spacing: DuckSpacing.small) {
      ForEach(1...3, id: \.self) { number in
        DuckStepMark(number: number, strength: number == current ? 1 : 0.25)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Self.label(current))
  }
  static func label(_ step: Int) -> String {
    String(format: NSLocalizedString("onboarding_step_progress", comment: ""), step, 3)
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

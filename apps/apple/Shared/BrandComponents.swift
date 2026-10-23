import CoreImage.CIFilterBuiltins
import SwiftUI

/// Chinese display clauses are native text runs laid out as indivisible units.
/// This avoids SwiftUI's emergency character wrapping across invisible joiners.
enum DuckDisplayHeadline {
  static func clauses(_ value: String) -> [String] {
    guard value.range(of: "\\p{Han}", options: .regularExpression) != nil else { return [value] }
    var result: [String] = []
    var clause = ""
    for character in value {
      clause.append(character)
      if character == "，" || character == "。" {
        result.append(clause)
        clause = ""
      }
    }
    if !clause.isEmpty { result.append(clause) }
    return result
  }

  static func text(_ key: String) -> some View {
    text(verbatim: NSLocalizedString(key, comment: ""))
  }

  static func text(verbatim value: String) -> some View {
    DuckDisplayHeadlineText(value: value)
  }
}

private struct DuckDisplayHeadlineText: View {
  let value: String
  @Environment(\.multilineTextAlignment) private var alignment
  var body: some View {
    let clauses = DuckDisplayHeadline.clauses(value)
    Group {
      if clauses.count > 1 {
        DuckHeadlineClauseLayout(alignment: alignment) {
          ForEach(clauses.indices, id: \.self) { index in
            Text(verbatim: clauses[index]).fixedSize()
          }
        }
      } else {
        Text(verbatim: value)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: value))
  }
}

/// Each line takes as many whole clauses as fit. Font and Dynamic Type remain
/// inherited from the display headline; no point size or forced line count lives here.
private struct DuckHeadlineClauseLayout: Layout {
  let alignment: TextAlignment

  private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
    var result: [[Int]] = []
    var row: [Int] = []
    var used: CGFloat = 0
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      if !row.isEmpty, used + size.width > width {
        result.append(row); row = []; used = 0
      }
      row.append(index); used += size.width
    }
    if !row.isEmpty { result.append(row) }
    return result
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let width = proposal.width ?? sizes.reduce(0) { $0 + $1.width }
    let lines = rows(subviews, width: width)
    return CGSize(width: min(width, lines.map { row in row.reduce(0) { $0 + sizes[$1].width } }.max() ?? 0),
      height: lines.reduce(0) { total, row in total + (row.map { sizes[$0].height }.max() ?? 0) })
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in rows(subviews, width: bounds.width) {
      let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
      let width = sizes.reduce(0) { $0 + $1.width }
      let height = sizes.map(\.height).max() ?? 0
      let offset = alignment == .center ? (bounds.width - width) / 2 : alignment == .trailing ? bounds.width - width : 0
      var x = bounds.minX + offset
      for (index, size) in zip(row, sizes) {
        subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
        x += size.width
      }
      y += height
    }
  }
}

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

/// V6: a square column with optically matched silhouettes. Geometry belongs to
/// the illustration, independently of page spacing and the adjacent text.
struct DuckStepMark: View {
  let number: Int
  var active = true
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
  private var fill: AnyShapeStyle {
    if active { return AnyShapeStyle(color) }
    // The inactive mark has no brand hue. Use the native tertiary text role;
    // accessibility's solid/high-contrast fallback uses secondary text.
    if reduceTransparency || previewReduceTransparency || contrast == .increased {
      return AnyShapeStyle(.secondary)
    }
    return AnyShapeStyle(.tertiary)
  }
  var body: some View {
    Rectangle().fill(fill)
      .mask {
        switch number {
        case 1: Image("MarkCircle").resizable().frame(width: 24 * unit, height: 24 * unit)
        case 2: Image("MarkWing").resizable().scaledToFit().frame(width: 36 * unit, height: 18 * unit)
        default: Image("MarkSparkle").resizable().frame(width: 34 * unit, height: 34 * unit)
        }
      }
      .frame(width: 36 * unit, height: 36 * unit)
      .accessibilityHidden(true)
  }
}

/// One stable row, with a single localized progress element for assistive technology.
struct DuckStepProgress: View {
  let current: Int
  var body: some View {
    HStack(spacing: DuckSpacing.small) {
      ForEach(1...3, id: \.self) { number in
        DuckStepMark(number: number, active: number == current)
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

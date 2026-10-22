import SwiftUI

/// The first-run reward (design/flows.md § First run, step 6): the first photo
/// travels from this device into the Pixel, the Pixel confirms it, and only then
/// does the caller say so. One motion with one cause; no loop while waiting.
/// Reduce Motion shows the settled state without spatial movement.
struct FirstPhotoFlight: View {
  /// The photo being sent. Nil shows a neutral photo tile (no photo library).
  let sourceID: String?
  let senderName: String
  let receiverName: String
  /// True once the photo is saved to the Pixel's Photos.
  let landed: Bool
  var onArrive: () -> Void = {}

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var progress: CGFloat = 0
  @State private var arrived = false

  private static let width: CGFloat = 280
  private static let tile: CGFloat = 72
  private static let pixel = CGSize(width: 76, height: 136)
  /// Where the tile settles: centred on the Pixel's screen, scaled to fit it.
  private static let landedScale: CGFloat = 0.62

  var body: some View {
    VStack(spacing: 10) {
      ZStack(alignment: .topLeading) {
        HStack(alignment: .center, spacing: 0) {
          RoundedRectangle(cornerRadius: 14)
            .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .frame(width: Self.tile, height: Self.tile)
            .opacity(progress > 0 ? 1 : 0)
          Spacer(minLength: 0)
          pixel
        }
        .frame(width: Self.width, height: Self.pixel.height)
        photo
          .frame(width: Self.tile, height: Self.tile)
          .modifier(Flight(progress: progress, start: start, end: end, endScale: Self.landedScale))
      }
      HStack {
        Text(senderName).frame(width: Self.tile + 24)
        Spacer(minLength: 0)
        Text(receiverName).frame(width: Self.pixel.width + 24)
      }
      .font(.caption).foregroundStyle(.secondary).lineLimit(1)
      .frame(width: Self.width + 24)
    }
    // The adjacent status block owns the current fact, including blocked states.
    .accessibilityHidden(true)
    .onAppear { if landed { fly() } }
    .onChange(of: landed) { _, value in if value { fly() } }
  }

  // Tile positions are top-leading offsets of the tile inside the stage.
  private var start: CGPoint { CGPoint(x: 0, y: (Self.pixel.height - Self.tile) / 2) }
  private var end: CGPoint {
    CGPoint(x: Self.width - Self.pixel.width / 2 - Self.tile / 2, y: (Self.pixel.height - Self.tile) / 2)
  }

  private var photo: some View {
    Group {
      if let sourceID {
        AssetThumbnail(sourceID: sourceID, size: Self.tile)
      } else {
        RoundedRectangle(cornerRadius: 8).fill(DuckGlyph.blue.gradient)
          .overlay(Image(systemName: "photo").font(.system(size: 26, weight: .medium)).foregroundStyle(.white)) // design-exception: glyph sized to the illustrated photo tile
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .shadow(color: .black.opacity(progress > 0 && progress < 1 ? 0.18 : 0), radius: 8, y: 4) // design-exception: lift only while the tile is in flight
  }

  private var pixel: some View {
    RoundedRectangle(cornerRadius: 16)
      .fill(DuckRole.groupedSurface)
      .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, lineWidth: 1.5))
      .overlay(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)).padding(7))
      .overlay(alignment: .topTrailing) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 26)).symbolRenderingMode(.palette) // design-exception: badge sized to the Pixel drawing
          .foregroundStyle(.white, DuckRole.saved) // design-exception: check on the saved badge
          .background(Circle().fill(DuckRole.background).padding(2))
          .offset(x: 10, y: -10)
          .scaleEffect(arrived ? 1 : 0.6).opacity(arrived ? 1 : 0)
      }
      .frame(width: Self.pixel.width, height: Self.pixel.height)
  }

  private func fly() {
    guard !arrived else { return }
    if reduceMotion {
      progress = 1; arrived = true; onArrive(); return
    }
    // Brief hold so the eye finds the tile before it moves.
    withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.75).delay(0.15)) { progress = 1 } completion: {
      withAnimation(.spring(duration: 0.32, bounce: 0)) { arrived = true }
      onArrive()
    }
  }
}

/// Moves the tile along an upward arc from `start` to `end`, scaling it down.
private struct Flight: GeometryEffect {
  var progress: CGFloat
  let start: CGPoint
  let end: CGPoint
  let endScale: CGFloat
  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  func effectValue(size: CGSize) -> ProjectionTransform {
    let t = progress
    let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 64)
    let u = 1 - t
    let x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
    let y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
    let scale = 1 + (endScale - 1) * t
    let transform = CGAffineTransform(translationX: x + size.width * (1 - scale) / 2, y: y + size.height * (1 - scale) / 2)
      .scaledBy(x: scale, y: scale)
    return ProjectionTransform(transform)
  }
}

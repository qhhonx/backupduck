import SwiftUI

/// Exercises the production reduced-motion path in Catalog without OS changes.
private struct FirstPhotoReducedMotionKey: EnvironmentKey {
  static let defaultValue = false
}
extension EnvironmentValues {
  var duckFirstPhotoReducedMotion: Bool {
    get { self[FirstPhotoReducedMotionKey.self] }
    set { self[FirstPhotoReducedMotionKey.self] = newValue }
  }
}

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
  @Environment(\.duckFirstPhotoReducedMotion) private var previewReduceMotion
  @State private var progress: CGFloat = 0
  @State private var arrived = false

  // Illustration metrics: equal device slots and a photo that fits both screens.
  private static let width: CGFloat = 264
  private static let tile: CGFloat = 40
  private static let device = CGSize(width: 64, height: 120)
  private static let landedScale: CGFloat = 1

  var body: some View {
    VStack(spacing: DuckSpacing.small) {
      ZStack(alignment: .topLeading) {
        HStack(spacing: 0) {
          device("iphone")
          Spacer(minLength: 0)
          device("smartphone")
        }
        .frame(width: Self.width, height: Self.device.height)
        photo
          .frame(width: Self.tile, height: Self.tile)
          .modifier(Flight(progress: progress, start: start, end: end, endScale: Self.landedScale))
        Image(systemName: "checkmark.circle.fill")
          .font(.title2).symbolRenderingMode(.palette)
          .foregroundStyle(DuckRole.background, DuckRole.saved)
          .background(Circle().fill(DuckRole.background).padding(2))
          .scaleEffect(arrived ? 1 : 0.6).opacity(arrived ? 1 : 0)
          .offset(x: Self.width - DuckSpacing.medium, y: -DuckSpacing.xSmall)
      }
      HStack(alignment: .top, spacing: DuckSpacing.medium) {
        Text(senderName).frame(width: 120)
        Spacer(minLength: 0)
        VStack(spacing: DuckSpacing.xxSmall) {
          Text(receiverName)
          Text("onboarding_pixel_photos")
        }.frame(width: 120)
      }
      .font(.caption).foregroundStyle(.secondary)
      .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      .frame(width: Self.width + 56)
    }
    // The adjacent status block owns the current fact, including blocked states.
    .accessibilityHidden(true)
    .onAppear { if landed { fly() } }
    .onChange(of: landed) { _, value in if value { fly() } }
  }

  // Tile positions are top-leading offsets inside the stage, centred in each glyph.
  private var start: CGPoint {
    CGPoint(x: (Self.device.width - Self.tile) / 2, y: (Self.device.height - Self.tile) / 2)
  }
  private var end: CGPoint {
    CGPoint(x: Self.width - (Self.device.width + Self.tile) / 2, y: start.y)
  }

  private var photo: some View {
    Group {
      if let sourceID {
        AssetThumbnail(sourceID: sourceID, size: Self.tile)
      } else {
        RoundedRectangle(cornerRadius: DuckRadius.control).fill(DuckRole.groupedSurface)
          .overlay(Image(systemName: "photo").font(.title3).foregroundStyle(.secondary))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: DuckRadius.control))
    .shadow(color: .black.opacity(progress > 0 && progress < 1 ? 0.18 : 0), radius: 8, y: 4) // design-exception: lift only while the tile is in flight
  }

  private func device(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .resizable().scaledToFit()
      .foregroundStyle(DuckRole.secondaryText)
      .frame(width: Self.device.width, height: Self.device.height)
  }

  private func fly() {
    guard !arrived else { return }
    if reduceMotion || previewReduceMotion {
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

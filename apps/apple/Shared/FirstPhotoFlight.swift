import Photos
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
  @State private var flying = false
  @State private var thumbnail: LibraryImage?
  @State private var thumbnailRequest = PHInvalidImageRequestID
  private static let thumbnails = ThumbnailPipeline()

  /// Device artwork with its transparent screen opening, measured as fractions
  /// of the image (Illustrations.xcassets DeviceIPhone / DevicePixel).
  private struct DeviceArt {
    let asset: String
    let size: CGSize
    let screen: CGRect
    let radius: CGFloat
    init(asset: String, aspect: CGFloat, height: CGFloat, screen: CGRect, radius: CGFloat) {
      self.asset = asset
      size = CGSize(width: height * aspect, height: height)
      self.screen = CGRect(x: screen.minX * size.width, y: screen.minY * height,
        width: screen.width * size.width, height: screen.height * height)
      self.radius = radius * size.width
    }
  }
  private static let width: CGFloat = 264
  private static let sender = DeviceArt(asset: "DeviceIPhone", aspect: 546 / 1151, height: 136,
    screen: CGRect(x: 0.04945, y: 0.02259, width: 0.89927, height: 0.95482), radius: 0.09707)
  // Sized so both screen openings are the same height; the photo then fits both.
  private static let receiver = DeviceArt(asset: "DevicePixel", aspect: 534 / 1152, height: 138.13,
    screen: CGRect(x: 0.05431, y: 0.02691, width: 0.89139, height: 0.94010), radius: 0.06554)
  private static let screen = sender.screen.size
  private static let stageHeight = max(sender.size.height, receiver.size.height)

  var body: some View {
    VStack(spacing: DuckSpacing.small) {
      ZStack(alignment: .topLeading) {
        HStack(spacing: 0) {
          device(Self.sender, showsPhoto: true)
          Spacer(minLength: 0)
          device(Self.receiver, showsPhoto: arrived)
        }
        .frame(width: Self.width, height: Self.stageHeight)
        photo
          .frame(width: Self.screen.width, height: Self.screen.height)
          .modifier(Flight(progress: progress, start: start, end: end, endScale: 1))
          // The tile lifts off the sender only when the flight starts, so the
          // sender's Dynamic Island stays visible while the photo rests there.
          .opacity(!flying || arrived || reduceMotion || previewReduceMotion ? 0 : 1)
          .animation(nil, value: arrived)
        Image(systemName: "checkmark.circle.fill")
          .font(.title2).symbolRenderingMode(.palette)
          .foregroundStyle(DuckRole.background, DuckRole.saved)
          .background(Circle().fill(DuckRole.background).padding(2))
          .scaleEffect(reduceMotion || previewReduceMotion ? 1 : arrived ? 1 : 0.6).opacity(arrived ? 1 : 0)
          .offset(x: Self.width - DuckSpacing.medium, y: -DuckSpacing.xSmall)
      }
      HStack(alignment: .top, spacing: DuckSpacing.medium) {
        VStack(spacing: DuckSpacing.xxSmall) {
          Text(verbatim: "iPhone")
          Text("onboarding_sender_photos")
        }.frame(width: 120)
        Spacer(minLength: 0)
        VStack(spacing: DuckSpacing.xxSmall) {
          Text(verbatim: "Pixel")
          Text("onboarding_pixel_photos")
        }.frame(width: 120)
      }
      .font(.caption).foregroundStyle(.secondary)
      .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      .frame(width: Self.width + 56)
      DuckIllustration(pose: .done, size: 72)
        .opacity(arrived ? 1 : 0)
    }
    // The adjacent status block owns the current fact, including blocked states.
    .accessibilityHidden(true)
    .task(id: sourceID) {
      Self.thumbnails.cancel(thumbnailRequest)
      thumbnail = nil
      guard BackupEnvironment.usesPhotoLibrary, let sourceID,
        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [sourceID], options: photoLibraryFetchOptions()).firstObject else { return }
      thumbnailRequest = Self.thumbnails.request(asset, pixels: Self.screen.height * 3) { image, _ in
        if let image { thumbnail = image }
      }
    }
    .onDisappear { Self.thumbnails.cancel(thumbnailRequest) }
    .onAppear { if landed { fly() } }
    .onChange(of: landed) { _, value in if value { fly() } }
  }

  // Tile positions are top-leading offsets inside the stage: each device is
  // vertically centred, and the tile is centred on its screen opening.
  private static func origin(_ art: DeviceArt, x: CGFloat) -> CGPoint {
    CGPoint(x: x + art.screen.midX - screen.width / 2,
      y: (stageHeight - art.size.height) / 2 + art.screen.midY - screen.height / 2)
  }
  private var start: CGPoint { Self.origin(Self.sender, x: 0) }
  private var end: CGPoint { Self.origin(Self.receiver, x: Self.width - Self.receiver.size.width) }

  // All three nodes render the same delivered bitmap in the same rectangular
  // clip. A square thumbnail followed by a narrower frame clips its corners.
  private var screenPhoto: some View {
    ZStack {
      Rectangle().fill(DuckRole.groupedSurface)
      if let sourceID, let sample = BackupEnvironment.sampleThumbnail?(sourceID) {
        sample.resizable().scaledToFill()
      } else if let thumbnail {
        #if os(macOS)
        Image(nsImage: thumbnail).resizable().scaledToFill()
        #else
        Image(uiImage: thumbnail).resizable().scaledToFill()
        #endif
      } else {
        Image(systemName: "photo").font(.title3).foregroundStyle(.secondary)
      }
    }
    .frame(width: Self.screen.width, height: Self.screen.height)
    // Between the two openings' radii; each bezel masks the rest at rest.
    .clipShape(RoundedRectangle(cornerRadius: (Self.sender.radius + Self.receiver.radius) / 2))
  }
  private var photo: some View {
    screenPhoto
      .shadow(color: .black.opacity(progress > 0 && progress < 1 ? 0.18 : 0), radius: 8, y: 4) // design-exception: lift only while the tile is in flight
  }

  /// The photo sits under the artwork, whose opaque bezel and camera cut-outs
  /// mask it exactly.
  private func device(_ art: DeviceArt, showsPhoto: Bool) -> some View {
    ZStack(alignment: .topLeading) {
      // An empty screen reads as a phone that is off, in both appearances.
      RoundedRectangle(cornerRadius: art.radius).fill(DuckMedia.scrim)
        .frame(width: art.screen.width, height: art.screen.height)
        .offset(x: art.screen.minX, y: art.screen.minY)
      if sourceID != nil {
        screenPhoto.opacity(showsPhoto ? 1 : 0)
          .animation(reduceMotion || previewReduceMotion ? .easeInOut(duration: 0.12) : nil, value: arrived)
          .offset(x: art.screen.midX - Self.screen.width / 2, y: art.screen.midY - Self.screen.height / 2)
      }
      Image(art.asset).resizable().interpolation(.high)
        .frame(width: art.size.width, height: art.size.height)
    }
    .frame(width: art.size.width, height: art.size.height, alignment: .topLeading)
  }

  private func fly() {
    guard !arrived else { return }
    if reduceMotion || previewReduceMotion {
      var instant = Transaction(); instant.disablesAnimations = true
      withTransaction(instant) { progress = 1 }
      withAnimation(.easeInOut(duration: 0.12)) { arrived = true }
      onArrive(); return
    }
    var instant = Transaction(); instant.disablesAnimations = true
    withTransaction(instant) { flying = true }
    // Brief hold so the eye finds the tile before it moves.
    withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.75).delay(0.15)) { progress = 1 } completion: {
      withAnimation(.spring(duration: 0.32, bounce: 0)) { arrived = true }
      onArrive()
    }
  }
}

/// Moves the complete screen tile along an upward arc between exact screen frames.
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

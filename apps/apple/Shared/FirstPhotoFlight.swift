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
  @StateObject private var library = OnboardingLibrarySamples(limit: FirstPhotoFlight.gridLimit)
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
  private static let stageHeight = max(sender.size.height, receiver.size.height)

  // Both screens show a Photos library the way the library grid does: three
  // columns, oldest first. A library that fits starts under the status bar
  // with any partial row last; a longer one is scrolled to its newest photos
  // at the bottom. The Pixel starts as an empty Photos page, because its
  // contents are not known here, and the photo lands in its first slot.
  private static let gridColumns = 3
  private static let gridGap: CGFloat = 1
  private static func side(_ art: DeviceArt) -> CGFloat {
    (art.screen.width - gridGap * CGFloat(gridColumns - 1)) / CGFloat(gridColumns)
  }
  /// The status bar's share of an iPhone screen's height.
  private static func statusInset(_ art: DeviceArt) -> CGFloat { art.screen.height * 0.07 }
  static let gridLimit = gridColumns * Int(ceil(sender.screen.height / (side(sender) + gridGap)))
  /// The frame of item `index` (0 is the oldest) among `total`, in screen coordinates.
  private static func slot(_ index: Int, of total: Int, in art: DeviceArt) -> CGRect {
    let side = side(art), pitch = side + gridGap
    let rows = (max(total, 1) + gridColumns - 1) / gridColumns
    let height = CGFloat(rows) * pitch - gridGap
    let top = height <= art.screen.height - statusInset(art) ? statusInset(art) : art.screen.height - height
    return CGRect(x: CGFloat(index % gridColumns) * pitch, y: top + CGFloat(index / gridColumns) * pitch,
      width: side, height: side)
  }
  /// The sender's visible items, newest first; nil is the photo being sent
  /// when it has no identity (no photo library). The sent photo is always
  /// among them: a photo older than the visible window counts as the newest.
  private var senderItems: [String?] {
    var ids: [String?] = library.assets.map(\.localIdentifier)
    if !ids.contains(sourceID) { ids.insert(sourceID, at: 0) }
    return ids
  }
  private var senderSlots: [(id: String?, frame: CGRect)] {
    let items = senderItems, total = max(library.total, items.count)
    return items.enumerated().compactMap { offset, id in
      let frame = Self.slot(total - 1 - offset, of: total, in: Self.sender)
      return frame.maxY > 0 ? (id, frame) : nil
    }
  }
  var body: some View {
    VStack(spacing: DuckSpacing.small) {
      ZStack(alignment: .topLeading) {
        HStack(spacing: 0) {
          device(Self.sender)
          Spacer(minLength: 0)
          device(Self.receiver)
        }
        .frame(width: Self.width, height: Self.stageHeight)
        photo
          .modifier(Flight(progress: progress, start: start, end: end))
          // The copy exists only while it moves; the slots show the photo at rest.
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
      thumbnailRequest = Self.thumbnails.request(asset, pixels: Self.side(Self.sender) * 3) { image, _ in
        if let image { thumbnail = image }
      }
    }
    .onDisappear { Self.thumbnails.cancel(thumbnailRequest) }
    .onAppear { if landed { fly() } }
    .onChange(of: landed) { _, value in if value { fly() } }
  }

  private static func screenOrigin(_ art: DeviceArt, x: CGFloat) -> CGPoint {
    CGPoint(x: x + art.screen.minX, y: (stageHeight - art.size.height) / 2 + art.screen.minY)
  }
  /// The copy leaves the sent photo's slot in the iPhone grid…
  private var start: CGRect {
    let origin = Self.screenOrigin(Self.sender, x: 0)
    let frame = senderSlots.first { $0.id == sourceID }?.frame ?? Self.slot(0, of: 1, in: Self.sender)
    return frame.offsetBy(dx: origin.x, dy: origin.y)
  }
  /// …and lands in the first slot of the Pixel's library.
  private var end: CGRect {
    let origin = Self.screenOrigin(Self.receiver, x: Self.width - Self.receiver.size.width)
    return Self.slot(0, of: 1, in: Self.receiver).offsetBy(dx: origin.x, dy: origin.y)
  }

  // The sent photo's slot, the moving copy and the landed tile render the
  // same delivered bitmap with the same fill crop.
  private var photoFill: some View {
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
        Image(systemName: "photo").font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
  private var photo: some View {
    photoFill
      .shadow(color: .black.opacity(progress > 0 && progress < 1 ? 0.18 : 0), radius: 4, y: 2) // design-exception: lift only while the tile is in flight
  }

  /// A lit screen with its library; the artwork's bezel and camera cut-outs
  /// mask it exactly.
  private func device(_ art: DeviceArt) -> some View {
    ZStack(alignment: .topLeading) {
      screenContent(art)
        .frame(width: art.screen.width, height: art.screen.height, alignment: .topLeading)
        .background(DuckRole.background)
        .clipShape(RoundedRectangle(cornerRadius: art.radius))
        .offset(x: art.screen.minX, y: art.screen.minY)
      Image(art.asset).resizable().interpolation(.high)
        .frame(width: art.size.width, height: art.size.height)
    }
    .frame(width: art.size.width, height: art.size.height, alignment: .topLeading)
  }

  /// The sender keeps the sent photo in its slot: a backup copies it, so a
  /// copy is what flies. The Pixel shows it once it has landed.
  @ViewBuilder private func screenContent(_ art: DeviceArt) -> some View {
    let side = Self.side(art)
    ZStack(alignment: .topLeading) {
      if art.asset == Self.sender.asset {
        ForEach(Array(senderSlots.enumerated()), id: \.offset) { _, slot in
          Group {
            if slot.id == sourceID { photoFill } else if let id = slot.id {
              AssetThumbnail(sourceID: id, size: side, cornerRadius: 0)
            }
          }
          .frame(width: side, height: side).clipped()
          .offset(x: slot.frame.minX, y: slot.frame.minY)
        }
      } else {
        let frame = Self.slot(0, of: 1, in: art)
        photoFill.frame(width: side, height: side).clipped()
          .offset(x: frame.minX, y: frame.minY)
          .opacity(arrived ? 1 : 0)
          .animation(reduceMotion || previewReduceMotion ? .easeInOut(duration: 0.12) : nil, value: arrived)
      }
    }
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

/// Moves the photo along an upward arc from its slot on the iPhone to its slot
/// on the Pixel, filling the frame it passes.
private struct Flight: ViewModifier, Animatable {
  var progress: CGFloat
  let start: CGRect
  let end: CGRect
  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  func body(content: Content) -> some View {
    let t = progress, u = 1 - t
    let control = CGPoint(x: (start.midX + end.midX) / 2, y: min(start.midY, end.midY) - 64)
    let center = CGPoint(x: u * u * start.midX + 2 * u * t * control.x + t * t * end.midX,
      y: u * u * start.midY + 2 * u * t * control.y + t * t * end.midY)
    let size = CGSize(width: start.width + (end.width - start.width) * t,
      height: start.height + (end.height - start.height) * t)
    content
      .frame(width: size.width, height: size.height).clipped()
      .offset(x: center.x - size.width / 2, y: center.y - size.height / 2)
  }
}

/// The newest allowed items and the library's size. A limited selection can
/// finish after access is reported, so the samples reload whenever the
/// library changes.
@MainActor final class OnboardingLibrarySamples: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
  @Published private(set) var assets: [PHAsset] = []
  @Published private(set) var total = 0
  private let limit: Int
  init(limit: Int) {
    self.limit = limit
    super.init()
    if let samples = BackupEnvironment.onboardingSamples {
      let all = samples(); assets = Array(all.prefix(limit)); total = all.count; return
    }
    guard BackupEnvironment.usesPhotoLibrary else { return }
    PHPhotoLibrary.shared().register(self)
    reload()
  }
  deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
  nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
    Task { @MainActor in self.reload() }
  }
  private func reload() {
    let limit = limit
    Task {
      let (fetched, count) = await Task.detached(priority: .userInitiated) {
        let options = photoLibraryFetchOptions(for: .all)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: options)
        return (fetch.objects(at: IndexSet(integersIn: 0..<min(limit, fetch.count))), fetch.count)
      }.value
      if fetched.map(\.localIdentifier) != assets.map(\.localIdentifier) { assets = fetched }
      if total != count { total = count }
    }
  }
}

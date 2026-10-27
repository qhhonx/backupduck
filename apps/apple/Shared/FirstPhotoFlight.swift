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
/// does the caller say so. While the page stays open, every later photo the
/// Pixel saves flies the same way, one at a time. Nothing moves without a
/// saved photo, and photos saved faster than the flights appear in place.
/// Reduce Motion shows each settled state without spatial movement.
struct FirstPhotoFlight: View {
  /// The photo being sent. Nil shows a neutral photo tile (no photo library).
  let sourceID: String?
  /// Photos the Pixel has saved to its Photos, in arrival order.
  var saved: [String] = []
  let senderName: String
  let receiverName: String
  /// True once the photo is saved to the Pixel's Photos.
  let landed: Bool
  var onArrive: () -> Void = {}

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.duckFirstPhotoReducedMotion) private var previewReduceMotion
  /// One photo tile; a nil identity is the first photo without a library.
  private struct Tile: Equatable { let id: String? }
  @State private var progress: CGFloat = 0
  @State private var arrived = false
  /// The copy in flight and its path, fixed when it leaves.
  @State private var moving: Tile?
  @State private var path = (start: CGRect.zero, end: CGRect.zero, entersFromTop: false)
  /// The Pixel's library in arrival order, and whether a slot is held for
  /// the copy in flight.
  @State private var shown: [Tile] = []
  @State private var reserved = false
  @StateObject private var library = OnboardingLibrarySamples(limit: FirstPhotoFlight.gridLimit)

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
  // contents are not known here, and fills with the photos it saves. One tile
  // size on both screens lets a copy keep its size from slot to slot.
  private static let gridColumns = 3
  private static let gridGap: CGFloat = 1
  private static let side = min(sender.screen.width, receiver.screen.width) / CGFloat(gridColumns)
    - gridGap * CGFloat(gridColumns - 1) / CGFloat(gridColumns)
  /// The status bar's share of an iPhone screen's height.
  private static func statusInset(_ art: DeviceArt) -> CGFloat { art.screen.height * 0.07 }
  static let gridLimit = gridColumns * Int(ceil(sender.screen.height / (side + gridGap)))
  /// The frame of item `index` (0 is the oldest) among `total`, in screen coordinates.
  private static func slot(_ index: Int, of total: Int, in art: DeviceArt) -> CGRect {
    let pitch = side + gridGap
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
  private var pixelTotal: Int { shown.count + (reserved ? 1 : 0) }
  private var reduced: Bool { reduceMotion || previewReduceMotion }

  var body: some View {
    VStack(spacing: DuckSpacing.small) {
      ZStack(alignment: .topLeading) {
        HStack(spacing: 0) {
          device(Self.sender)
          Spacer(minLength: 0)
          device(Self.receiver)
        }
        .frame(width: Self.width, height: Self.stageHeight)
        if let moving {
          tile(moving.id)
            .shadow(color: .black.opacity(progress > 0 && progress < 1 ? 0.18 : 0), radius: 4, y: 2) // design-exception: lift only while the tile is in flight
            .modifier(Flight(progress: progress, start: path.start, end: path.end, entersFromTop: path.entersFromTop))
        }
        Image(systemName: "checkmark.circle.fill")
          .font(.title2).symbolRenderingMode(.palette)
          .foregroundStyle(DuckRole.background, DuckRole.saved)
          .background(Circle().fill(DuckRole.background).padding(2))
          .scaleEffect(reduced ? 1 : arrived ? 1 : 0.6).opacity(arrived ? 1 : 0)
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
    .onAppear { if landed { flyFirst() } }
    .onChange(of: landed) { _, value in if value { flyFirst() } }
    .onChange(of: saved) { _, _ in advance() }
  }

  private static func screenOrigin(_ art: DeviceArt, x: CGFloat) -> CGPoint {
    CGPoint(x: x + art.screen.minX, y: (stageHeight - art.size.height) / 2 + art.screen.minY)
  }
  /// A copy leaves its photo's slot in the iPhone grid. An older photo outside
  /// the visible newest window enters from the top of the screen instead.
  private func start(for id: String?) -> (frame: CGRect, entersFromTop: Bool) {
    let origin = Self.screenOrigin(Self.sender, x: 0)
    if let frame = senderSlots.first(where: { $0.id == id })?.frame {
      return (frame.offsetBy(dx: origin.x, dy: origin.y), false)
    }
    let top = Self.slot(1, of: Self.gridColumns, in: Self.sender)
    return (top.offsetBy(dx: origin.x, dy: origin.y), true)
  }
  /// The next free slot in the Pixel's library.
  private var nextSlot: CGRect {
    let origin = Self.screenOrigin(Self.receiver, x: Self.width - Self.receiver.size.width)
    return Self.slot(shown.count, of: shown.count + 1, in: Self.receiver).offsetBy(dx: origin.x, dy: origin.y)
  }

  @ViewBuilder private func tile(_ id: String?) -> some View {
    if let id {
      AssetThumbnail(sourceID: id, size: Self.side, cornerRadius: 0)
    } else {
      ZStack {
        Rectangle().fill(DuckRole.groupedSurface)
        Image(systemName: "photo").font(.caption2).foregroundStyle(.secondary)
      }.frame(width: Self.side, height: Self.side)
    }
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

  /// The sender keeps every photo in its slot: a backup copies it, so a copy
  /// is what flies. The Pixel shows each photo once it has landed.
  @ViewBuilder private func screenContent(_ art: DeviceArt) -> some View {
    ZStack(alignment: .topLeading) {
      if art.asset == Self.sender.asset {
        ForEach(Array(senderSlots.enumerated()), id: \.offset) { _, slot in
          tile(slot.id).offset(x: slot.frame.minX, y: slot.frame.minY)
        }
      } else {
        ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
          let frame = Self.slot(index, of: pixelTotal, in: art)
          tile(item.id).offset(x: frame.minX, y: frame.minY).transition(.opacity)
        }
      }
    }
  }

  private func flyFirst() {
    guard !arrived, moving == nil else { return }
    if reduced {
      withAnimation(.easeInOut(duration: 0.12)) { shown = [Tile(id: sourceID)]; arrived = true }
      onArrive(); advance(); return
    }
    // Brief hold so the eye finds the tile before it moves.
    launch(sourceID, hold: 0.15) {
      withAnimation(.spring(duration: 0.32, bounce: 0)) { arrived = true }
      onArrive()
    }
  }
  /// Flies the newest photo the Pixel has saved and not yet shown. Photos
  /// saved while a copy was in flight appear in place, so the page never
  /// falls behind the Pixel.
  private func advance() {
    guard arrived, moving == nil else { return }
    let pending = saved.map { Tile(id: $0) }.filter { !shown.contains($0) }
    guard let next = pending.last else { return }
    if reduced || pending.count > 1 {
      withAnimation(.easeInOut(duration: reduced ? 0.12 : 0.2)) {
        shown.append(contentsOf: reduced ? pending : pending.dropLast())
      }
      if reduced { return }
    }
    // A short pause between flights keeps each one readable.
    launch(next.id, hold: 0.6) {}
  }
  private func launch(_ id: String?, hold: Double, landed: @escaping () -> Void) {
    let departure = start(for: id)
    var instant = Transaction(); instant.disablesAnimations = true
    withTransaction(instant) {
      path = (departure.frame, nextSlot, departure.entersFromTop); progress = 0; moving = Tile(id: id)
    }
    // The Pixel makes room first, so its library never jumps when the copy lands.
    withAnimation(.easeInOut(duration: 0.3).delay(hold)) { reserved = true }
    withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.75).delay(hold)) { progress = 1 } completion: {
      withTransaction(instant) { shown.append(Tile(id: id)); reserved = false; moving = nil }
      landed()
      advance()
    }
  }
}

/// Moves a copy along an upward arc from its slot on the iPhone to its slot
/// on the Pixel. A copy entering from above the visible grid fades in.
private struct Flight: ViewModifier, Animatable {
  var progress: CGFloat
  let start: CGRect
  let end: CGRect
  let entersFromTop: Bool
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
      .opacity(entersFromTop ? min(1, t / 0.2) : 1)
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

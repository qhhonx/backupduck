import AVFoundation
import UIKit

struct CalendarGridAsset: Equatable {
  let id: String
  let date: Date?
  let aspect: CGFloat
  var videoDuration: String? = nil
  var live = false
  /// Modification time in milliseconds: an edit invalidates stored thumbnails.
  var revision: Int64 = 0
}
enum CalendarGridLevel: Int, CaseIterable { case years, months, all }
struct CalendarGridTile {
  let id: String
  let asset: Int
  let members: Range<Int>
  let label: String
  let frame: CGRect
}
struct CalendarGridGeometry {
  var tiles: [CalendarGridTile] = []
  var headings: [(String, CGRect)] = []
  var coverChoices: [String: [Int]] = [:]
  var height: CGFloat = 0
  var maximumTileHeight: CGFloat = 1
  var leadingSlots = 0
  var level = CalendarGridLevel.all
  var columns = 3
  /// Dense overviews are drawn by `CalendarDenseCanvas`, not per-photo cells.
  var dense: Bool { level == .all && columns >= 10 }
  init(
    assets: [CalendarGridAsset], level: CalendarGridLevel, width: CGFloat, columns: Int,
    originalAspect: Bool, leadingSlots: Int = 0
  ) {
    guard width > 0 else { return }
    self.leadingSlots = leadingSlots
    self.level = level
    self.columns = columns
    let calendar = Calendar.current
    func buckets(_ component: Calendar.Component, range: Range<Int>) -> [(Date?, Range<Int>)] {
      var result: [(Date?, Range<Int>)] = []
      for i in range {
        let date = assets[i].date.flatMap { calendar.dateInterval(of: component, for: $0)?.start }
        if let last = result.last, last.0 == date {
          result[result.count - 1].1 = last.1.lowerBound..<(i + 1)
        } else {
          result.append((date, i..<(i + 1)))
        }
      }
      return result
    }
    var y: CGFloat = 0
    switch level {
    case .all:
      let gap = Self.gap(columns: columns)
      let side = Self.side(width: width, columns: columns)
      var row: [(Int, CGFloat)] = []
      var rowY: CGFloat = 0
      func appendRow() {
        guard !row.isEmpty else { return }
        // A single column shows each photo at its own aspect, like Photos.
        let height =
          originalAspect || columns == 1
          ? min(side * (columns == 1 ? 1.5 : 1.8),
            max(side * (columns == 1 ? 0.5 : 0.55), row.map { side / max(0.2, $0.1) }.max() ?? side))
          : side
        for item in row {
          let i = item.0
          let col = (i + leadingSlots) % columns
          let rect = CGRect(x: CGFloat(col) * (side + gap), y: rowY, width: side, height: height)
          tiles.append(
            CalendarGridTile(
              id: assets[i].id, asset: i, members: i..<(i + 1), label: "", frame: rect))
        }
        rowY += height + gap
        row.removeAll(keepingCapacity: true)
      }
      for i in assets.indices {
        row.append((i, assets[i].aspect))
        if (i + leadingSlots) % columns == columns - 1 { appendRow() }
      }
      appendRow()
      y = rowY
      if columns >= 10 {
        for (date, range) in buckets(columns >= 20 ? .year : .month, range: assets.indices) {
          let title =
            date.map {
              columns >= 20
                ? $0.formatted(.dateTime.year()) : $0.formatted(.dateTime.year().month(.wide))
            } ?? NSLocalizedString("design_capture_unknown", comment: "")
          if tiles.indices.contains(range.lowerBound) {
            headings.append(
              (
                title,
                CGRect(x: 12, y: tiles[range.lowerBound].frame.minY + 6, width: 240, height: 30)
              ))
          }
        }
      }
    case .years:
      y = 16
      for (date, range) in buckets(.year, range: assets.indices) {
        let cover = range.upperBound - 1
        let title =
          date.map { $0.formatted(.dateTime.year()) }
          ?? NSLocalizedString("design_capture_unknown", comment: "")
        coverChoices["year:\(title)"] = buckets(.month, range: range).map { $0.1.upperBound - 1 }
        let rect = CGRect(x: 20, y: y, width: width - 40, height: (width - 40) * 0.76)
        tiles.append(
          CalendarGridTile(
            id: "year:\(title)", asset: cover, members: range, label: title, frame: rect))
        y = rect.maxY + 24
      }
    case .months:
      y = 12
      for (month, range) in buckets(.month, range: assets.indices) {
        let title =
          month.map { $0.formatted(.dateTime.year().month(.wide)) }
          ?? NSLocalizedString("design_capture_unknown", comment: "")
        headings.append((title, CGRect(x: 20, y: y, width: width - 40, height: 40)))
        y += 48
        let allDays = buckets(.day, range: range)
        // Sample at most six day covers, retaining every period member for navigation.
        let count = min(6, allDays.count)
        let days = (0..<count).map { slot -> (Date?, Range<Int>) in
          let first = slot * allDays.count / count
          let last = (slot + 1) * allDays.count / count - 1
          return (allDays[last].0, allDays[first].1.lowerBound..<allDays[last].1.upperBound)
        }
        let cursor = 0, block = 0
        if count > 0 {
          let content = width - 40
          let gap: CGFloat = 6
          let u = (content - gap * 2) / 3
          var frames: [CGRect] = []
          func tile(_ x: Int, _ row: Int, _ w: Int = 1, _ h: Int = 1) -> CGRect {
            CGRect(
              x: 20 + CGFloat(x) * (u + gap), y: y + CGFloat(row) * (u + gap),
              width: CGFloat(w) * u + CGFloat(w - 1) * gap,
              height: CGFloat(h) * u + CGFloat(h - 1) * gap)
          }
          switch count {
          case 6:
            frames = [tile(0, 0, 2, 2), tile(2, 0), tile(2, 1), tile(0, 2), tile(1, 2), tile(2, 2)]
          case 5:
            frames = [tile(0, 0, 2, 2), tile(2, 0), tile(2, 1), tile(0, 2, 2), tile(2, 2)]
          case 4:
            frames = [tile(0, 0, 3, 2), tile(0, 2), tile(1, 2), tile(2, 2)]
          case 3:
            frames = [tile(0, 0, 2, 2), tile(2, 0), tile(2, 1)]
          case 2:
            let half = (content - gap) / 2
            frames = [
              CGRect(x: 20, y: y, width: half, height: half * 4 / 3),
              CGRect(x: 20 + half + gap, y: y, width: half, height: half * 4 / 3),
            ]
          default:
            frames = [CGRect(x: 20, y: y, width: content, height: content * 0.65)]
          }
          if (block + (month.map { calendar.component(.month, from: $0) } ?? 1)) % 2 == 0,
            count >= 3, count != 4
          {
            frames = frames.map {
              CGRect(
                x: width - 20 - ($0.maxX - 20), y: $0.minY,
                width: $0.width, height: $0.height)
            }
          }
          // Mirrored mosaics read down the small left column before the large cover.
          if (block + (month.map { calendar.component(.month, from: $0) } ?? 1)) % 2 == 0,
            count >= 3, count != 4
          {
            frames.sort { $0.minX == $1.minX ? $0.minY < $1.minY : $0.minX < $1.minX }
          }
          for slot in 0..<count {
            let day = days[cursor + slot]
            let cover = days[cursor + slot].1.upperBound - 1
            let label = day.0.map { $0.formatted(.dateTime.day()) } ?? "—"
            tiles.append(
              CalendarGridTile(
                id: "day:\(cover)", asset: cover, members: day.1,
                label: label, frame: frames[slot]))
          }
          y = (frames.map(\.maxY).max() ?? y) + 16
        }
        y += 16
      }
    }
    if level == .months {
      tiles.sort {
        $0.frame.minY == $1.frame.minY
          ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
      }
    }
    height = level == .all ? max(0, y - 2) : y + 16
    maximumTileHeight = tiles.map { $0.frame.height }.max() ?? 1
  }
  /// Dense month/year overviews are gapless mosaics, as in Photos.
  static func gap(columns: Int) -> CGFloat { columns >= 10 ? 0 : 2 }
  static func side(width: CGFloat, columns: Int) -> CGFloat {
    (width - CGFloat(columns - 1) * gap(columns: columns)) / CGFloat(columns)
  }
  /// Horizontal lattice pitch: one cell plus its gap.
  static func pitch(width: CGFloat, columns: Int) -> CGFloat {
    side(width: width, columns: columns) + gap(columns: columns)
  }
  func visible(in rectangle: CGRect) -> Range<Int> {
    var low = 0
    var high = tiles.count
    while low < high {
      let mid = (low + high) / 2
      if tiles[mid].frame.minY < rectangle.minY - maximumTileHeight {
        low = mid + 1
      } else {
        high = mid
      }
    }
    let first = low
    high = tiles.count
    while low < high {
      let mid = (low + high) / 2
      if tiles[mid].frame.minY < rectangle.maxY { low = mid + 1 } else { high = mid }
    }
    return first..<max(first, low)
  }
}

final class CalendarGridLayout: UICollectionViewLayout {
  static let headingKind = "calendar.heading"
  var geometry = CalendarGridGeometry(
    assets: [], level: .all, width: 1, columns: 3, originalAspect: false)
  var level = CalendarGridLevel.all
  func frame(_ i: Int) -> CGRect {
    geometry.tiles.indices.contains(i) ? geometry.tiles[i].frame : .zero
  }
  override var collectionViewContentSize: CGSize {
    CGSize(width: collectionView?.bounds.width ?? 1, height: geometry.height)
  }
  override func layoutAttributesForItem(at path: IndexPath) -> UICollectionViewLayoutAttributes? {
    guard geometry.tiles.indices.contains(path.item) else { return nil }
    let a = UICollectionViewLayoutAttributes(forCellWith: path)
    a.frame = frame(path.item)
    return a
  }
  override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]?
  {
    let indices = geometry.dense ? 0..<0 : geometry.visible(in: rect)
    var out = indices.compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    for i in visibleHeadings(in: rect) {
      if let a = heading(i) { out.append(a) }
    }
    return out
  }
  func visibleHeadings(in rect: CGRect) -> [Int] {
    guard !geometry.headings.isEmpty else { return [] }
    let pin =
      (collectionView?.bounds.minY ?? rect.minY) + (collectionView?.adjustedContentInset.top ?? 0)
      + 4
    var low = 0
    var high = geometry.headings.count
    while low < high {
      let mid = (low + high) / 2
      if geometry.headings[mid].1.minY <= pin { low = mid + 1 } else { high = mid }
    }
    let first = max(0, low - 1)
    var visible: [Int] = []
    var bottom = -CGFloat.greatestFiniteMagnitude
    for i in first..<geometry.headings.count {
      guard let a = heading(i) else { continue }
      if a.frame.minY >= rect.maxY { break }
      if a.frame.maxY > rect.minY, a.frame.minY >= bottom + 10 {
        visible.append(i)
        bottom = a.frame.maxY
      }
    }
    return visible
  }
  func heading(_ i: Int) -> UICollectionViewLayoutAttributes? {
    guard geometry.headings.indices.contains(i) else { return nil }
    let a = UICollectionViewLayoutAttributes(
      forSupplementaryViewOfKind: Self.headingKind,
      with: IndexPath(item: i, section: 0))
    a.frame = geometry.headings[i].1
    if let view = collectionView {
      let pin = view.bounds.minY + view.adjustedContentInset.top + 4
      a.frame.origin.y = max(a.frame.minY, pin)
    }
    a.zIndex = 30
    return a
  }
  override func layoutAttributesForSupplementaryView(ofKind kind: String, at path: IndexPath)
    -> UICollectionViewLayoutAttributes?
  { heading(path.item) }
  override func shouldInvalidateLayout(forBoundsChange bounds: CGRect) -> Bool {
    bounds.width != collectionView?.bounds.width || !geometry.headings.isEmpty
  }
}

final class CalendarGlassHeading: UICollectionReusableView {
  let label = UILabel(), glass = UIVisualEffectView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
      glass.effect = UIGlassEffect(style: .regular)
    } else {
      glass.effect = UIBlurEffect(style: .systemChromeMaterial)
    }
    glass.layer.cornerRadius = 12
    glass.clipsToBounds = true
    addSubview(glass)
    glass.contentView.addSubview(label)
    label.font = .preferredFont(forTextStyle: .headline)
    label.textColor = DuckRole.primaryTextUIColor
    label.accessibilityIdentifier = "calendar.date_badge"
  }
  /// Dense pills read like Photos: a light pill with a quiet year and a dark
  /// month, or the year alone in the yearly overview.
  static func pillText(_ text: String, yearly: Bool) -> NSAttributedString {
    let title = NSMutableAttributedString(
      string: text, attributes: [
        .foregroundColor: DuckMedia.labelTextUIColor, .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
      ])
    if !yearly, let year = text.range(of: "[0-9]{4}年?", options: .regularExpression) {
      title.addAttribute(
        .foregroundColor, value: DuckMedia.labelTextSecondaryUIColor, range: NSRange(year, in: text))
    }
    return title
  }
  func title(_ text: String, dense: Bool, yearly: Bool) {
    glass.overrideUserInterfaceStyle = dense ? .light : .unspecified
    label.font = .systemFont(ofSize: dense ? 15 : 20, weight: .semibold)
    label.accessibilityIdentifier = "calendar.period_heading"
    if dense {
      label.attributedText = Self.pillText(text, yearly: yearly)
    } else {
      label.attributedText = nil
      label.textColor = DuckRole.primaryTextUIColor
      label.text = text
    }
    setNeedsLayout()
  }
  required init?(coder: NSCoder) { fatalError() }
  /// Shows or hides the heading through its effect and text, which animate;
  /// an ancestor's alpha does not fade a glass effect.
  func reveal(_ visible: Bool) {
    if visible {
      if glass.effect == nil {
        glass.effect = !UIAccessibility.isReduceTransparencyEnabled
          ? { if #available(iOS 26.0, *) { return UIGlassEffect(style: .regular) }
              return UIBlurEffect(style: .systemChromeMaterial) }()
          : UIBlurEffect(style: .systemChromeMaterial)
      }
      label.alpha = 1
    } else {
      glass.effect = nil
      label.alpha = 0
    }
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    reveal(true)
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    glass.frame = CGRect(
      x: 0, y: 0, width: min(bounds.width, label.intrinsicContentSize.width + 20),
      height: bounds.height)
    label.frame = glass.bounds.insetBy(dx: 10, dy: 3)
  }
}
/// A late fallback must not replace pixels already presented for the same asset.
func calendarPreferredImage(_ current: UIImage?, _ incoming: UIImage?, aspect: CGFloat? = nil) -> UIImage? {
  guard let incoming else { return current }
  guard let current else { return incoming }
  func edge(_ image: UIImage) -> CGFloat {
    image.cgImage.map { CGFloat(max($0.width, $0.height)) }
      ?? max(image.size.width, image.size.height) * image.scale
  }
  if let aspect {
    let matches: (UIImage) -> Bool = { abs(log(($0.size.width / max(1,$0.size.height)) / max(0.01,aspect))) < 0.05 }
    if matches(current) && !matches(incoming) { return current }
    if !matches(current) && matches(incoming), edge(incoming) >= edge(current) { return incoming }
  }
  return edge(incoming) < edge(current) ? current : incoming
}

/// Native-size decorations are transformed with the complete animated cell.
final class CalendarTileDecorations: UIView {
  let check = UIImageView(), duration = UILabel(), stateMark = UIImageView(), liveMark = UIImageView()
  let placeholder = UIImageView()
  struct State {
    let duration: String?
    let live: UIImage?
    let status: UIImage?
    let statusTint: UIColor
    let checkHidden: Bool
    let imageOpacity: Float
  }
  var state: State {
    State(duration: duration.text, live: liveMark.image, status: stateMark.image,
      statusTint: stateMark.tintColor, checkHidden: check.isHidden, imageOpacity: imageOpacity)
  }
  func apply(_ value: State) {
    duration.text = value.duration; liveMark.image = value.live
    stateMark.image = value.status; stateMark.tintColor = value.statusTint
    check.isHidden = value.checkHidden; imageOpacity = value.imageOpacity
    setNeedsLayout()
  }
  /// Resolved once: SwiftUI color bridging and symbol lookup are measurable
  /// when a launch creates a screen of cells. Colors stay dynamic.
  @MainActor enum Style {
    static let photo = UIImage(systemName: "photo"), cloud = UIImage(systemName: "icloud")
    static let secondary = DuckRole.secondaryTextUIColor, subtle = DuckRole.mediaPlaceholderUIColor
    static let failure = DuckRole.failureUIColor, saved = DuckRole.savedUIColor
    static var symbols: [String: UIImage] = [:]
    static func symbol(_ name: String) -> UIImage? {
      if let image = symbols[name] { return image }
      let image = UIImage(systemName: name)
      symbols[name] = image
      return image
    }
  }
  func thumbnail(hasImage: Bool, cloud: Bool) {
    placeholder.isHidden = hasImage
    let symbol = cloud ? Style.cloud : Style.photo
    if placeholder.image !== symbol { placeholder.image = symbol }
  }
  var imageOpacity: Float = 1
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    placeholder.image = Style.photo
    placeholder.tintColor = Style.secondary
    placeholder.contentMode = .scaleAspectFit
    addSubview(placeholder)
    DuckMediaSelection.configure(check)
    check.isHidden = true
    addSubview(check)
    duration.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    duration.textColor = DuckMedia.onMediaUIColor
    addSubview(duration)
    stateMark.contentMode = .scaleAspectFit
    addSubview(stateMark)
    liveMark.tintColor = DuckMedia.onMediaUIColor
    liveMark.contentMode = .scaleAspectFit
    addSubview(liveMark)
    // design/library.md § Tile marks: every mark on a photo is a white glyph
    // or text with a soft shadow, as Photos draws
    // them; no pills, circles or colored fills.
    for mark in [duration, stateMark, liveMark] as [UIView] {
      mark.backgroundColor = .clear
      mark.clipsToBounds = false
      mark.layer.shadowColor = DuckMedia.shadowCGColor
      mark.layer.shadowOpacity = 0.45
      mark.layer.shadowRadius = 2
      mark.layer.shadowOffset = CGSize(width: 0, height: 0.5)
    }
    duration.textAlignment = .right
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    placeholder.frame = CGRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32)
    check.frame = DuckMediaSelection.frame(in: bounds)
    let durationRight = check.isHidden ? bounds.width - 6 : check.frame.minX - 6
    let durationWidth = min(49, max(1, durationRight - 6))
    duration.frame = CGRect(x: durationRight - durationWidth, y: bounds.height - 24, width: durationWidth, height: 18)
    duration.isHidden = duration.text == nil || bounds.width < 80
    stateMark.frame = CGRect(x: bounds.width - 26, y: 6, width: 20, height: 20)
    stateMark.isHidden = stateMark.image == nil || bounds.width < 80
    liveMark.frame = CGRect(x: 6, y: 6, width: 20, height: 20)
    liveMark.isHidden = liveMark.image == nil || bounds.width < 80
  }
  func selection(_ selected: Bool, enabled: Bool) {
    // Use the shared selection contract for both the badge and photo opacity.
    DuckMediaSelection.apply(selected, enabled: enabled, badge: check, image: Self.opacityProbe)
    imageOpacity = Float(Self.opacityProbe.alpha)
  }
  private static let opacityProbe = UIImageView()
  func backupState(_ state: String?, visible: Bool) {
    let symbol = libraryTileSymbol(state)
    stateMark.image = visible ? symbol.flatMap {
      UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    } : nil
    stateMark.tintColor = DuckMedia.onMediaUIColor
    stateMark.contentMode = .center
    stateMark.backgroundColor = .clear
    stateMark.clipsToBounds = false
    stateMark.layer.shadowColor = DuckMedia.shadowCGColor
    stateMark.layer.shadowOpacity = 0.45
    stateMark.layer.shadowRadius = 2
    stateMark.layer.shadowOffset = CGSize(width: 0, height: 0.5)
    setNeedsLayout()
  }
}

struct CalendarTilePresentation {
  let image: UIImage?
  let cloud: Bool
  let badges: CalendarTileDecorations.State?
}

final class CalendarGridCell: UICollectionViewCell {
  let image = UIImageView(), label = UILabel(), scrim = CAGradientLayer()
  let decorations = CalendarTileDecorations()
  var placeholder: UIImageView { decorations.placeholder }
  var check: UIImageView { decorations.check }
  var duration: UILabel { decorations.duration }
  var stateMark: UIImageView { decorations.stateMark }
  var liveMark: UIImageView { decorations.liveMark }
  var resumeThumbnail: (() -> Void)?
  var accessibilityToggle: (() -> Bool)?
  var cancel: (() -> Void)?, assetID = "", coverAsset: Int?
  var assetAspect: CGFloat?
  var thumbnailCloud = false
  /// The shown pixels are an upscaled stored placeholder, not the cell's rendition.
  private(set) var softImage = false
  /// Created only for a playing video cover; most cells never need one.
  private var videoLayerStorage: AVPlayerLayer?
  var videoLayer: AVPlayerLayer {
    if let videoLayerStorage { return videoLayerStorage }
    let layer = AVPlayerLayer()
    videoLayerStorage = layer
    return layer
  }
  var videoLoop: NSObjectProtocol?
  var videoReady: NSKeyValueObservation?
  func playCover(_ item: AVPlayerItem) {
    stopCover()
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    videoLayer.player = player
    videoLayer.videoGravity = .resizeAspectFill
    image.layer.addSublayer(videoLayer)
    videoLayer.frame = image.bounds
    videoLoop = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item, queue: .main
    ) { [weak player] _ in
      player?.seek(to: .zero)
      player?.play()
    }
    videoReady = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
      [weak self] layer, _ in
      Task { @MainActor in
        if layer.isReadyForDisplay, self?.videoLayer.player != nil {
          self?.accessibilityValue = NSLocalizedString("calendar_muted_video", comment: "")
        }
      }
    }
    player.play()
  }
  func stopCover() {
    videoReady = nil
    accessibilityValue = nil
    videoLayerStorage?.player?.pause()
    videoLayerStorage?.player = nil
    videoLayerStorage?.removeFromSuperlayer()
    if let videoLoop { NotificationCenter.default.removeObserver(videoLoop) }
    videoLoop = nil
  }
  override init(frame: CGRect) {
    super.init(frame: frame)
    image.contentMode = .scaleAspectFill
    image.clipsToBounds = true
    contentView.addSubview(image)
    contentView.backgroundColor = CalendarTileDecorations.Style.subtle
    scrim.colors = [DuckMedia.scrimGradientCGColor, UIColor.clear.cgColor]
    contentView.layer.addSublayer(scrim)
    label.font = .systemFont(ofSize: 23, weight: .semibold)
    label.textColor = DuckMedia.onMediaUIColor
    contentView.addSubview(label)
    contentView.addSubview(decorations)
    isAccessibilityElement = true
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    image.frame = contentView.bounds
    videoLayerStorage?.frame = image.bounds
    scrim.frame = CGRect(x: 0, y: 0, width: bounds.width, height: min(110, bounds.height))
    label.frame = CGRect(x: 16, y: 12, width: max(1, bounds.width - 32), height: 32)
    decorations.frame = contentView.bounds
    decorations.layoutIfNeeded()
  }
  /// The cell's overlays alone (top shadow, period label, badges) at native
  /// size on a transparent canvas, for transitions that move its photo.
  func decorationSnapshot() -> UIImage? {
    let labelShown = !label.isHidden && !(label.text ?? "").isEmpty
    let badges = [decorations.duration, decorations.liveMark, decorations.stateMark, decorations.check]
      .contains { !$0.isHidden }
    guard labelShown || badges || !scrim.isHidden, bounds.width > 0 else { return nil }
    layoutIfNeeded()
    let hidden = (image.isHidden, decorations.placeholder.isHidden)
    let background = contentView.backgroundColor
    image.isHidden = true; decorations.placeholder.isHidden = true; contentView.backgroundColor = .clear
    defer {
      image.isHidden = hidden.0; decorations.placeholder.isHidden = hidden.1
      contentView.backgroundColor = background
    }
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = traitCollection.displayScale
    return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
      contentView.layer.render(in: context.cgContext)
    }
  }
  func thumbnail(_ value: UIImage?, cloud: Bool, soft: Bool = false) {
    thumbnailCloud = cloud
    let previous = image.image
    image.image = calendarPreferredImage(image.image, value, aspect: assetAspect)
    if image.image !== previous { softImage = soft }
    decorations.thumbnail(hasImage: image.image != nil, cloud: cloud)
  }
  func selection(_ selected: Bool, enabled: Bool) {
    decorations.selection(selected, enabled: enabled)
    image.alpha = CGFloat(decorations.imageOpacity)
    accessibilityTraits = selected ? [.button, .selected] : [.button]
  }
  func backupState(_ state: String?, visible: Bool) {
    decorations.backupState(state, visible: visible)
    accessibilityHint = visible && state != nil ? NSLocalizedString(libraryTileAccessibilityKey(state), comment: "") : nil
  }
  override func accessibilityActivate() -> Bool { accessibilityToggle?() ?? super.accessibilityActivate() }
  override func prepareForReuse() {
    super.prepareForReuse()
    accessibilityToggle = nil
    cancel?()
    cancel = nil
    stopCover()
    coverAsset = nil
    resumeThumbnail = nil; assetAspect = nil
    thumbnailCloud = false
    softImage = false
    assetID = ""
    image.image = nil
    placeholder.isHidden = false
    isHidden = false
  }
}

private final class CalendarPhotoAccessibilityElement: UIAccessibilityElement {
  var activate: () -> Bool = { false }
  override func accessibilityActivate() -> Bool { activate() }
}

/// Dense month/year overviews show up to about two thousand photos per screen.
/// One collection cell per photo made UIKit's cell management dominate scrolling
/// (measured with Time Profiler), so these levels draw strips of rows into a few
/// bitmap layers instead, the level-of-detail approach large photo grids use.
/// The collection still owns scrolling, content size and period headings;
/// geometry answers hit testing.
final class CalendarDenseCanvas: UIView {
  static let rowsPerStrip = 8
  final class Strip {
    let layer = CALayer()
    var rows: Range<Int> = 0..<0
    var requests: [Int: () -> Void] = [:]
    /// Owned by the render queue; drawn incrementally, never redrawn whole.
    var context: CGContext?
    var origin: CGFloat = 0
    private let generationLock = NSLock()
    private var generationValue = 0
    var generation: Int {
      get { generationLock.lock(); defer { generationLock.unlock() }; return generationValue }
      set { generationLock.lock(); generationValue = newValue; generationLock.unlock() }
    }
    var publishGeneration: Int?
    var drawnAssets: Set<Int> = []
    var publishedAssets: Set<Int> = []
    var bitmap: CGImage?
  }
  var cachedImage: (Int) -> UIImage? = { _ in nil }
  /// Thread-safe decoded-table lookup, called on the render queue so a full
  /// strip of hits costs the main thread nothing.
  var tableLookup: ((Int) -> CGImage?)?
  var prepare: ([Int]) -> Void = { _ in }
  var request: (Int, CGFloat, @escaping (UIImage?) -> Void) -> (() -> Void)? = { _, _, _ in nil }
  var didPublish: (() -> Void)?
  var geometry = CalendarGridGeometry(assets: [], level: .all, width: 1, columns: 31, originalAspect: false)
  var columns = 31
  var fill = true
  private var strips: [Int: Strip] = [:]
  private var pool: [Strip] = []
  private var generation = 0
  /// Bitmap drawing runs off the main thread; layers only adopt finished images.
  let renderQueue = DispatchQueue(label: "app.backupduck.dense-canvas", qos: .userInitiated)
  private var canvasColor: UIColor { UIColor.systemBackground.resolvedColor(with: traitCollection) }
  private let actions: [String: CAAction] = [
    "contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "hidden": NSNull(),
  ]
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    layer.actions = actions
  }
  required init?(coder: NSCoder) { fatalError() }
  /// Mask bounded bitmap strips, never the full library-sized canvas.
  func hidePreviewTile(_ frame: CGRect?) {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    for strip in strips.values {
      guard let frame, strip.layer.frame.intersects(frame) else { strip.layer.mask = nil; continue }
      let mask = CAShapeLayer(), path = UIBezierPath(rect: strip.layer.bounds)
      path.append(UIBezierPath(rect: frame.offsetBy(dx: -strip.layer.frame.minX, dy: -strip.layer.frame.minY)))
      mask.fillRule = .evenOdd; mask.path = path.cgPath
      strip.layer.mask = mask
    }
  }
  var rowCount: Int { (geometry.tiles.count + geometry.leadingSlots + columns - 1) / max(1, columns) }
  func rowFrame(_ row: Int) -> CGRect {
    let first = max(0, row * columns - geometry.leadingSlots)
    guard geometry.tiles.indices.contains(first) else { return .zero }
    let frame = geometry.tiles[first].frame
    return CGRect(x: 0, y: frame.minY, width: bounds.width, height: frame.height)
  }
  func reset(_ geometry: CalendarGridGeometry, columns: Int, fill: Bool) {
    for (key, strip) in strips { recycle(strip); strips.removeValue(forKey: key) }
    self.geometry = geometry
    self.columns = columns
    self.fill = fill
  }
  func stop() { reset(geometry, columns: columns, fill: fill) }
  func update(visible: CGRect, scale: CGFloat) {
    guard !geometry.tiles.isEmpty else { return }
    let rect = visible.insetBy(dx: 0, dy: -visible.height * 0.35)
    let range = geometry.visible(in: rect)
    guard let firstTile = range.first, let lastTile = range.last else { return }
    let firstStrip = (firstTile + geometry.leadingSlots) / columns / Self.rowsPerStrip
    let lastStrip = (lastTile + geometry.leadingSlots) / columns / Self.rowsPerStrip
    var keep = Set<Int>()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for index in firstStrip...max(firstStrip, lastStrip) {
      keep.insert(index)
      if strips[index] != nil { continue }
      let strip = pool.popLast() ?? Strip()
      strip.layer.actions = actions
      strip.rows = (index * Self.rowsPerStrip)..<min(rowCount, (index + 1) * Self.rowsPerStrip)
      // Strips abut on whole device pixels, so no seam shows between them.
      let top = rowFrame(strip.rows.lowerBound).minY
      let next = strip.rows.upperBound < rowCount
        ? rowFrame(strip.rows.upperBound).minY
        : rowFrame(max(strip.rows.lowerBound, strip.rows.upperBound - 1)).maxY
      let y0 = (top * scale).rounded() / scale, y1 = (next * scale).rounded() / scale
      strip.layer.frame = CGRect(x: 0, y: y0, width: bounds.width, height: max(1 / scale, y1 - y0))
      strip.layer.backgroundColor = canvasColor.cgColor
      strip.layer.masksToBounds = true
      strip.layer.contentsGravity = .resize
      strip.origin = y0
      generation += 1
      strip.generation = generation
      layer.addSublayer(strip.layer)
      strips[index] = strip
      begin(strip, scale: scale)
    }
    for (index, strip) in strips where !keep.contains(index) {
      recycle(strip); strips.removeValue(forKey: index)
    }
    CATransaction.commit()
  }
  /// Draws a fresh strip bitmap on the render queue: decoded-table hits first,
  /// then the main thread resolves only the misses from memory caches or
  /// requests; each arrival later draws only its own tile.
  private func begin(_ strip: Strip, scale: CGFloat) {
    let size = strip.layer.frame.size
    let pixelScale = scale
    let first = max(0, strip.rows.lowerBound * columns - geometry.leadingSlots)
    let last = min(geometry.tiles.count, strip.rows.upperBound * columns - geometry.leadingSlots)
    guard first < last else { return }
    let tiles = (first..<last).map { (geometry.tiles[$0].asset, geometry.tiles[$0].frame.offsetBy(dx: 0, dy: -strip.origin)) }
    let token = strip.generation, fill = fill, color = canvasColor.cgColor, lookup = tableLookup
    renderQueue.async { [weak self, weak strip] in
      guard let strip, strip.generation == token else { return }
      let width = Int((size.width * pixelScale).rounded()), height = Int((size.height * pixelScale).rounded())
      guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
      else { return }
      context.interpolationQuality = .medium
      // UIKit's top-left origin.
      context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: pixelScale, y: -pixelScale)
      context.setFillColor(color); context.fill(CGRect(origin: .zero, size: size))
      strip.context = context
      strip.drawnAssets = []
      var misses: [(Int, CGRect)] = []
      for (asset, rect) in tiles {
        if let image = lookup?(asset) {
          Self.draw(image, in: rect, fill: fill, scale: pixelScale, context: context)
          strip.drawnAssets.insert(asset)
        } else { misses.append((asset, rect)) }
      }
      self?.publish(strip, generation: token)
      guard !misses.isEmpty else { return }
      DispatchQueue.main.async { [weak self, weak strip] in
        guard let self, let strip, strip.generation == token else { return }
        self.resolve(misses, in: strip, generation: token, scale: scale)
      }
    }
  }
  /// Main thread: memory-cache hits draw at once, the rest are requested.
  private func resolve(_ misses: [(Int, CGRect)], in strip: Strip, generation token: Int, scale: CGFloat) {
    prepare(misses.compactMap { cachedImage($0.0) == nil ? $0.0 : nil })
    var ready: [(Int, CGRect, CGImage)] = [], missing: [(Int, CGRect)] = []
    for (asset, rect) in misses {
      if let image = cachedImage(asset)?.cgImage { ready.append((asset, rect, image)) }
      else { missing.append((asset, rect)) }
    }
    if !ready.isEmpty { draw(ready, into: strip, generation: token) }
    // The strip's context already exists (created before this hop), so an
    // in-memory hit that calls back synchronously draws into the right bitmap.
    for (asset, rect) in missing {
      strip.requests[asset] = request(asset, max(40, geometry.tiles[asset].frame.width * scale)) {
        [weak self, weak strip] image in
        guard let self, let strip, strip.generation == token, let image = image?.cgImage else { return }
        self.draw([(asset, rect, image)], into: strip, generation: token)
      } ?? {}
    }
  }
  private func draw(_ tiles: [(Int, CGRect, CGImage)], into strip: Strip, generation token: Int) {
    let fill = fill, scale = window?.screen.scale ?? traitCollection.displayScale
    renderQueue.async { [weak self, weak strip] in
      guard let strip, strip.generation == token, let context = strip.context else { return }
      for (asset,rect,image) in tiles {
        Self.draw(image,in: rect,fill: fill,scale: scale,context: context)
        strip.drawnAssets.insert(asset)
      }
      self?.publish(strip, generation: token)
    }
  }
  /// Runs on the render queue; adopts at most one image per strip per frame.
  private func publish(_ strip: Strip, generation token: Int) {
    guard strip.publishGeneration != token else { return }
    strip.publishGeneration = token
    DispatchQueue.main.async { [weak self, weak strip] in
      guard let self, let strip else { return }
      self.renderQueue.async { [weak self,weak strip] in
        guard let strip else { return }
        if strip.publishGeneration == token { strip.publishGeneration = nil }
        guard strip.generation == token,let image = strip.context?.makeImage() else { return }
        let painted = strip.drawnAssets
        DispatchQueue.main.async { [weak self,weak strip] in
          guard let strip,strip.generation == token else { return }
          CATransaction.begin(); CATransaction.setDisableActions(true)
          strip.layer.contents = image
          strip.bitmap = image
          strip.publishedAssets = painted
          CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async { self?.didPublish?() }
          }
          CATransaction.commit()
        }
      }
    }
  }
  /// The visible bitmap owns its pixels independently of evictable caches.
  /// Crop only already-published media when the next gesture takes ownership.
  func displayedImage(_ asset: Int) -> UIImage? {
    guard geometry.tiles.indices.contains(asset),
      let strip = strips[(asset+geometry.leadingSlots)/columns/Self.rowsPerStrip],
      strip.publishedAssets.contains(asset),let bitmap = strip.bitmap,
      strip.layer.bounds.width > 0 else { return nil }
    let scale = CGFloat(bitmap.width)/strip.layer.bounds.width
    let tile = geometry.tiles[asset].frame.offsetBy(dx: 0,dy: -strip.origin)
    let x0 = (tile.minX*scale).rounded(),y0 = (tile.minY*scale).rounded()
    let crop = CGRect(x: x0,y: y0,width: (tile.maxX*scale).rounded()-x0,
      height: (tile.maxY*scale).rounded()-y0).intersection(CGRect(x: 0,y: 0,width: bitmap.width,height: bitmap.height))
    guard !crop.isEmpty,let image = bitmap.cropping(to: crop) else { return nil }
    return UIImage(cgImage: image,scale: scale,orientation: .up)
  }
  /// Fraction of tiles in `visible` whose pixels are already on screen.
  func coverage(in visible: CGRect) -> Double {
    let range = geometry.visible(in: visible)
    var shown = 0, total = 0
    for index in range where geometry.tiles[index].frame.intersects(visible) {
      total += 1
      if let strip = strips[(index + geometry.leadingSlots) / columns / Self.rowsPerStrip],
        strip.publishedAssets.contains(geometry.tiles[index].asset) { shown += 1 }
    }
    return total == 0 ? 1 : Double(shown) / Double(total)
  }
  func isReady(in visible: CGRect) -> Bool {
    let range = geometry.visible(in: visible)
    guard let first = range.first,let last = range.last else { return true }
    let low = (first+geometry.leadingSlots)/columns/Self.rowsPerStrip
    let high = (last+geometry.leadingSlots)/columns/Self.rowsPerStrip
    return (low...high).allSatisfy { strips[$0]?.bitmap != nil }
  }
  private static func draw(_ image: CGImage, in raw: CGRect, fill: Bool, scale: CGFloat,
    context: CGContext) {
    // Tile edges land on bitmap pixels: no half-covered seams between tiles.
    func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
    let rect = CGRect(x: snap(raw.minX), y: snap(raw.minY),
      width: snap(raw.maxX) - snap(raw.minX), height: snap(raw.maxY) - snap(raw.minY))
    let w = CGFloat(image.width), h = CGFloat(image.height)
    let factor = fill ? max(rect.width / w, rect.height / h) : min(rect.width / w, rect.height / h)
    let size = CGSize(width: w * factor, height: h * factor)
    context.saveGState()
    context.clip(to: rect)
    // The context is flipped for UIKit coordinates; images draw upright.
    let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
      width: size.width, height: size.height)
    context.translateBy(x: 0, y: target.midY * 2)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: target)
    context.restoreGState()
  }
  private func recycle(_ strip: Strip) {
    strip.requests.values.forEach { $0() }
    strip.requests = [:]
    strip.generation = -1
    strip.publishedAssets = []
    strip.bitmap = nil
    strip.layer.removeFromSuperlayer()
    strip.layer.contents = nil
    renderQueue.async { [weak strip] in strip?.context = nil }
    if pool.count < 24 { pool.append(strip) }
  }
}

/// UIKit can deliver a final changed callback while its touch count still
/// includes a lifted finger. Track live touches before forwarding the event so
/// that this callback cannot replace the two-finger focus with one endpoint.
final class CalendarPinchGesture: UIPinchGestureRecognizer {
  private var liveTouches = Set<UITouch>()
  func focus(in view: UIView) -> CGPoint? {
    let points = liveTouches.filter { $0.phase != .ended && $0.phase != .cancelled }.map {
      $0.location(in: view)
    }
    guard points.count == 2 else { return nil }
    return CGPoint(x: (points[0].x + points[1].x) * 0.5, y: (points[0].y + points[1].y) * 0.5)
  }
  /// Current distance between the two live fingers, in window points.
  func distance() -> CGFloat? {
    let points = liveTouches.filter { $0.phase != .ended && $0.phase != .cancelled }.map {
      $0.location(in: nil)
    }
    guard points.count == 2 else { return nil }
    return hypot(points[0].x - points[1].x, points[0].y - points[1].y)
  }
  /// Finger distance when the second finger landed, before UIKit's own
  /// recognition movement.
  private(set) var downDistance: CGFloat?
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    liveTouches.formUnion(touches)
    if downDistance == nil { downDistance = distance() }
    super.touchesBegan(touches, with: event)
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    liveTouches.subtract(touches)
    super.touchesEnded(touches, with: event)
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    liveTouches.subtract(touches)
    super.touchesCancelled(touches, with: event)
  }
  override func reset() {
    liveTouches.removeAll()
    downDistance = nil
    super.reset()
  }
}

/// A second finger transfers input to pinch and restores the range baseline.
final class CalendarRangeGesture: UILongPressGestureRecognizer {
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    let active =
      event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count
      ?? touches.count
    if active > 1 {
      state = state == .began || state == .changed ? .cancelled : .failed
      return
    }
    super.touchesBegan(touches, with: event)
  }
}

/// Native accessories own placement; content supplies only its controls.
final class CalendarSelectionControls: UIView {
  let countButton = UIButton(type: .system)
  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(countButton)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    let width = min(bounds.width - 32, max(130, countButton.intrinsicContentSize.width + 32))
    countButton.frame = CGRect(
      x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
  }
}
/// Observe public view geometry without accessing UIKit implementation objects.
/// Unlike a predictive morph callback, geometry is available only after layout.
final class CalendarNativeBarObserver: NSObject {
  weak var owner: CalendarGridController?
  private weak var bar: UITabBar?
  private var clock: CADisplayLink?
  private(set) var available = false
  private(set) var minimized = false
  init(owner: CalendarGridController) { self.owner = owner }
  @discardableResult func start(_ bar: UITabBar) -> Bool {
    if self.bar === bar, clock != nil { return true }
    stop()
    self.bar = bar
    available = true
    let link = CADisplayLink(target: self, selector: #selector(sample))
    link.add(to: .main, forMode: .common)
    clock = link
    sample()
    return true
  }
  func stop() {
    clock?.invalidate()
    clock = nil
    bar = nil
    available = false
    minimized = false
  }
  /// The same public geometry drives detection and period placement. No class
  /// names, selectors, ivars or keys from UIKit's implementation are consulted.
  static func compactFrame(in view: UIView, relativeTo host: UIView) -> CGRect? {
    guard !view.isHidden, view.alpha > 0.01 else { return nil }
    if view is UIControl, (36...64).contains(view.bounds.width),
      (36...64).contains(view.bounds.height), abs(view.bounds.width - view.bounds.height) < 10 {
      return view.convert(view.bounds, to: host)
    }
    for child in view.subviews {
      if let frame = compactFrame(in: child, relativeTo: host) { return frame }
    }
    return nil
  }
  @objc private func sample() {
    guard let bar, !bar.isHidden, let host = bar.superview else { return }
    let next = Self.compactFrame(in: bar, relativeTo: host) != nil
    guard next != minimized else { return }
    minimized = next
    owner?.nativeBarMorphed(minimized: next)
  }
}

/// Live pinch stage for the All grid. Each face is one density's geometry drawn
/// as virtualized tile layers on a shared lattice: every face shows the same
/// on-screen cell pitch, aligned on its focal photo, so a density change only
/// crossfades cell contents while gaps stay put. Tiles read the image cache and
/// fill in as requests complete; nothing is baked into viewport bitmaps, so a
/// tile is never painted blank because its pixels arrived late.
final class CalendarZoomStage: UIView {
  struct TileKey: Hashable { let row: Int; let column: Int }
  final class Tile: CALayer {
    let photo = CALayer()
    var decorations: CalendarTileDecorations?
    var presentedImage: UIImage?
    var columns = 5
    var assetAspect: CGFloat?
    var cloud = false
    func display(_ image: UIImage?, cloud: Bool = false) {
      presentedImage = calendarPreferredImage(presentedImage, image, aspect: assetAspect)
      self.cloud = cloud
      photo.contents = presentedImage?.cgImage
      decorations?.thumbnail(hasImage: presentedImage != nil, cloud: cloud)
    }
    override init() {
      super.init()
      addSublayer(photo)
      photo.contentsGravity = .resizeAspectFill
      // Large renditions shrunk to dense sizes otherwise shimmer frame to frame.
      photo.minificationFilter = .trilinear
      masksToBounds = true
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }
  }
  final class Face {
    let columns: Int
    let geometry: CalendarGridGeometry
    /// Focal point in this face's layout coordinates.
    var focus: CGPoint
    /// Natural lattice pitch of this density at scale 1.
    let pitch: CGFloat
    let container = CALayer()
    let content = CALayer()
    struct Coverage: Equatable { let first: Int; let last: Int; let left: Int; let right: Int }
    var denseCoverage: Coverage?
    var tiles: [TileKey: Tile] = [:]
    var requests: [TileKey: () -> Void] = [:]
    var pills: [Int: CALayer] = [:]
    var opacity: CGFloat = 0
    init(columns: Int, geometry: CalendarGridGeometry, focus: CGPoint, pitch: CGFloat) {
      self.columns = columns
      self.geometry = geometry
      self.focus = focus
      self.pitch = pitch
      content.anchorPoint = .zero
      container.addSublayer(content)
    }
  }
  /// Configures a tile layer for an asset at a pixel tier and returns a
  /// cancellation for any request it started.
  var configureTile: (CALayer, Int, CGFloat) -> (() -> Void)? = { _, _, _ in nil }
  var configureDecorations: (CalendarTileDecorations, Int) -> Void = { _, _ in }
  var pillImage: (String, Bool) -> CGImage? = { _, _ in nil }
  private(set) var faces: [Int: Face] = [:]
  private(set) var shownColumns: Int
  /// Displayed lattice pitch and the screen point holding every face's focus.
  var pitch: CGFloat
  var focus: CGPoint
  private var pool: [Tile] = []
  private var link: CADisplayLink?
  private var laidOut: (CGFloat, CGPoint, CGFloat)?
  var focalFraction = CGPoint(x: 0.5, y: 0.5)
  /// Scoped to construction of one face; every displayed tile then owns its pixels.
  var seedTiles: [String: CalendarTilePresentation] = [:]
  /// Every face clips its pixels to the gap of the face being shown, switched in
  /// one frame as in Photos: dividers never thin below a pixel or flicker while
  /// the photo contents crossfade underneath.
  var displayedGap: CGFloat {
    guard let face = faces[shownColumns] else { return 0 }
    return CalendarGridGeometry.gap(columns: face.columns) * pitch / face.pitch
  }
  /// Rounds a coordinate to the device pixel grid.
  func snap(_ value: CGFloat) -> CGFloat { (value * displayScale).rounded() / displayScale }
  func updateFocalFraction(_ value: CGPoint) {
    let gap = displayedGap
    for face in faces.values {
      let scale = pitch / face.pitch
      let correction = (gap - CalendarGridGeometry.gap(columns: face.columns) * scale) / scale
      face.focus.x += (value.x - focalFraction.x) * correction
      face.focus.y += (value.y - focalFraction.y) * correction
    }
    focalFraction = value
  }
  func presentations(_ columns: Int) -> [String: CalendarTilePresentation] {
    guard let face = faces[columns] else { return [:] }
    var values: [String: CalendarTilePresentation] = [:]
    for tile in face.tiles.values where tile.convert(tile.bounds,to: layer).intersects(bounds) {
      guard let id = tile.photo.name else { continue }
      values[id] = CalendarTilePresentation(image: tile.presentedImage, cloud: tile.cloud,
        badges: face.columns <= 5 ? tile.decorations?.state : nil)
    }
    return values
  }
  private var settle: (start: CFTimeInterval, pitch: CGFloat, focus: CGPoint, velocity: CGFloat,
    targetPitch: CGFloat, targetFocus: CGPoint, done: () -> Void)?
  private struct Blend {
    var from: [Int: CGFloat]
    var target: Int
    var larger: Int?
    var phase: CGFloat
    var start: CFTimeInterval
    var requested: CFTimeInterval
    var duration: CFTimeInterval
  }
  private var blend: Blend?
  private var faceOrder: [Int] = []
  /// Visible critically damped release, not a private framework parameter.
  /// Fitted to Photos release recordings (decay 0.60/0.28/0.11 at 0.1/0.2/0.3 s).
  static let settleOmega: CGFloat = 12.5
  static let gridFadeDuration: CFTimeInterval = 1.2
  static let overviewFadeDuration: CFTimeInterval = 0.85
  /// Outgoing faces stay opaque until the shown face has most of its pixels,
  /// bounded so cloud-only media cannot hold a crossfade indefinitely.
  static let pixelWait: CFTimeInterval = 0.5
  let displayScale: CGFloat
  private let tileActions: [String: CAAction] = [
    "contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "frame": NSNull(),
    "opacity": NSNull(), "hidden": NSNull(), "sublayers": NSNull(),
  ]
  init(frame: CGRect, columns: Int, pitch: CGFloat, focus: CGPoint, displayScale: CGFloat) {
    shownColumns = columns
    self.pitch = pitch
    self.focus = focus
    self.displayScale = displayScale
    super.init(frame: frame)
    isUserInteractionEnabled = false
    clipsToBounds = true
  }
  required init?(coder: NSCoder) { fatalError() }
  var settling: Bool { settle != nil }
  func start() {
    guard link == nil else { return }
    let display = CADisplayLink(target: self, selector: #selector(tick))
    display.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    display.add(to: .main, forMode: .common)
    link = display
  }
  func pause() {
    link?.invalidate(); link = nil
    settle = nil
  }
  func stop() {
    pause()
    blend = nil
    for face in faces.values { discard(face) }
    faces = [:]; faceOrder = []
  }
  @discardableResult func addFace(columns: Int, geometry: CalendarGridGeometry, focus: CGPoint,
    pitch: CGFloat, opacity: CGFloat) -> Face {
    if let existing = faces[columns] { return existing }
    if seedTiles.isEmpty {
      for source in faces.values.sorted(by: { $0.opacity < $1.opacity }) {
        for (id, value) in presentations(source.columns) {
          if columns >= 10, let image = value.image,
            max(image.size.width, image.size.height) * image.scale > 128 { continue }
          seedTiles[id] = value
        }
      }
    }
    let face = Face(columns: columns, geometry: geometry, focus: focus, pitch: pitch)
    face.container.actions = tileActions
    face.container.frame = bounds
    face.content.actions = tileActions
    face.content.bounds = bounds
    face.opacity = opacity
    face.container.opacity = Float(opacity)
    layer.addSublayer(face.container)
    faces[columns] = face
    faceOrder.append(columns)
    layout(face)
    seedTiles = [:]
    return face
  }
  /// Weights describe the visible mixture, independently of layer order. Keeping
  /// the order stable avoids a compositing jump when a partial fade reverses.
  func show(_ columns: Int, animated: Bool, at now: CFTimeInterval = CACurrentMediaTime()) {
    guard faces[columns] != nil else { return }
    advanceBlend(to: now)
    if !animated {
      shownColumns = columns; blend = nil
      for face in faces.values { face.opacity = face.columns == columns ? 1 : 0 }
      applyOpacities(); prune()
      return
    }
    guard columns != shownColumns else { return }
    shownColumns = columns
    let from = faces.mapValues(\.opacity)
    let active = from.keys.filter { from[$0, default: 0] > 0.0001 || $0 == columns }
    let larger = active.count == 2 ? active.min() : nil
    let curved = active.allSatisfy { $0 <= 5 }
    let weight = larger.map { from[$0, default: 0] } ?? 0
    let phase = curved ? sqrt(weight) : weight
    let end: CGFloat = larger == columns ? 1 : 0
    let full = curved ? Self.gridFadeDuration : Self.overviewFadeDuration
    let remaining = larger == nil ? 1 - from[columns, default: 0] : abs(end - phase)
    blend = Blend(from: from, target: columns, larger: larger, phase: phase,
      start: now, requested: now, duration: max(0.001, full * Double(remaining)))
  }
  private func advanceBlend(to now: CFTimeInterval) {
    guard var b = blend else { return }
    if let target = faces[b.target], loaded(target) < 0.8, now - b.requested < Self.pixelWait {
      b.start = now; blend = b
      return
    }
    let t = min(1, max(0, CGFloat((now - b.start) / b.duration)))
    if let larger = b.larger {
      let end: CGFloat = larger == b.target ? 1 : 0
      let phase = b.phase + (end - b.phase) * t
      let curved = b.from.keys.filter { b.from[$0, default: 0] > 0.0001 || $0 == b.target }
        .allSatisfy { $0 <= 5 }
      let weight = curved ? phase * phase : phase
      for face in faces.values {
        if face.columns == larger { face.opacity = weight }
        else if face.columns == b.target || b.from[face.columns, default: 0] > 0.0001 {
          face.opacity = 1 - weight
        } else { face.opacity = 0 }
      }
    } else {
      // A fast gesture can reach a third density before the previous pair has
      // finished. Preserve its current composite as the outgoing mixture.
      for face in faces.values {
        face.opacity = b.from[face.columns, default: 0] * (1 - t)
          + (face.columns == b.target ? t : 0)
      }
    }
    if t >= 1 { blend = nil }
    applyOpacities()
  }
  private func applyOpacities() {
    var above: CGFloat = 0
    for count in faceOrder.reversed() {
      guard let face = faces[count] else { continue }
      face.container.opacity = Float(min(1, max(0, face.opacity / max(0.000001, 1 - above))))
      above += face.opacity
    }
  }
  /// Moves the shared focus to a new screen point without moving any pixels.
  func reanchor(_ point: CGPoint) {
    for face in faces.values {
      let scale = pitch / face.pitch
      face.focus.x += (point.x - focus.x) / scale
      face.focus.y += (point.y - focus.y) / scale
    }
    focus = point
  }
  /// A release keeps the running crossfade continuous but finishes it with the
  /// settle, instead of holding a settled pose (and its unloaded tiles) for the
  /// rest of a long held-gesture fade.
  func hurryBlend(within limit: CFTimeInterval, at now: CFTimeInterval = CACurrentMediaTime()) {
    advanceBlend(to: now)
    guard var b = blend else { return }
    let t = min(1, max(0, (now - b.start) / b.duration))
    let remaining = (1 - t) * b.duration
    guard remaining > limit else { b.requested = now - Self.pixelWait; blend = b; return }
    let duration = b.duration * limit / remaining
    b.duration = duration
    b.start = now - t * duration
    b.requested = now - Self.pixelWait
    blend = b
  }
  func setSettle(pitch target: CGFloat, focus targetFocus: CGPoint, velocity: CGFloat,
    done: @escaping () -> Void) {
    // Limit carried velocity so a fast release cannot overshoot visibly.
    let limit = abs(target - pitch) * Self.settleOmega
    settle = (CACurrentMediaTime(), pitch, focus, max(-limit, min(limit, velocity)), target,
      targetFocus, done)
  }
  /// Stops an in-flight settle at its current pose, for an interrupting gesture.
  func freeze() { settle = nil }
  /// Fraction of a face's visible tiles that already show pixels.
  func loaded(_ face: Face) -> CGFloat {
    guard !face.tiles.isEmpty else { return 1 }
    return CGFloat(face.tiles.values.reduce(0) { $0 + ($1.photo.contents == nil ? 0 : 1) }) / CGFloat(face.tiles.count)
  }
  @objc private func tick() { advance(to: CACurrentMediaTime()) }
  /// Also permits deterministic checks of held and interrupted transitions.
  func advance(to now: CFTimeInterval) {
    advanceBlend(to: now)
    let fading = blend != nil
    prune()
    if let s = settle {
      let t = CGFloat(now - s.start), w = Self.settleOmega
      func spring(_ x0: CGFloat, _ target: CGFloat, _ v0: CGFloat) -> CGFloat {
        target + (x0 - target + (v0 + w * (x0 - target)) * t) * exp(-w * t)
      }
      pitch = spring(s.pitch, s.targetPitch, s.velocity)
      focus = CGPoint(x: spring(s.focus.x, s.targetFocus.x, 0), y: spring(s.focus.y, s.targetFocus.y, 0))
      if t > 0.1, abs(pitch - s.targetPitch) < 0.05, hypot(focus.x - s.targetFocus.x, focus.y - s.targetFocus.y) < 0.25,
        !fading
      {
        pitch = s.targetPitch; focus = s.targetFocus
        layoutAll()
        settle = nil
        s.done()
        return
      }
    }
    layoutAll()
  }
  func layoutAll() {
    let gap = displayedGap
    if let last = laidOut, last.0 == pitch, last.1 == focus, last.2 == gap { return }
    laidOut = (pitch, focus, gap)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for face in faces.values { layout(face) }
    CATransaction.commit()
  }
  private func layout(_ face: Face) {
    let scale = pitch / max(0.01, face.pitch)
    let gap = displayedGap
    let delta = gap - CalendarGridGeometry.gap(columns: face.columns) * scale
    let correction = CGPoint(x: focalFraction.x * delta, y: focalFraction.y * delta)
    let visible = CGRect(
      x: face.focus.x - focus.x / scale, y: face.focus.y - focus.y / scale,
      width: bounds.width / scale, height: bounds.height / scale).insetBy(dx: -4 / scale, dy: -4 / scale)
    var keep = Set<TileKey>()
    let range = face.geometry.visible(in: visible)
    let side = face.geometry.tiles.first?.frame.width ?? face.pitch
    // Rows extend beyond their resting horizontal crop while scaled down. Each
    // extra slot reads its chronological neighbor; no row is stretched or blank.
    let firstColumn = Int(floor(visible.minX / face.pitch))
    let lastColumn = Int(ceil(visible.maxX / face.pitch))
    // Gapless mosaics move as one node. Revisit tile membership only when a row
    // or column crosses the viewport, instead of mutating thousands per tick.
    let grouped = face.columns >= 10 && gap == 0
    if grouped {
      face.content.position = CGPoint(x: focus.x-face.focus.x*scale,y: focus.y-face.focus.y*scale)
      face.content.setAffineTransform(CGAffineTransform(scaleX: scale,y: scale))
      let coverage = Face.Coverage(first: range.first ?? 0,last: range.last ?? -1,left: firstColumn,right: lastColumn)
      if face.denseCoverage == coverage { layoutPills(face,scale: scale); return }
      face.denseCoverage = coverage
    } else {
      face.denseCoverage = nil
      face.content.setAffineTransform(.identity); face.content.position = .zero
    }
    var rows = Set<Int>()
    for i in range {
      let row = (i + face.geometry.leadingSlots) / face.columns
      guard rows.insert(row).inserted else { continue }
      let rowFrame = face.geometry.tiles[i].frame
      for column in firstColumn...max(firstColumn, lastColumn) {
        let asset = row * face.columns + column - face.geometry.leadingSlots
        guard face.geometry.tiles.indices.contains(asset), keep.count < 5000 else { continue }
        let tile = face.geometry.tiles[asset]
        let frame = CGRect(x: CGFloat(column) * face.pitch, y: rowFrame.minY,
          width: side, height: rowFrame.height)
        guard frame.intersects(visible) else { continue }
        let key = TileKey(row: row, column: column)
        keep.insert(key)
        let tileLayer: Tile
        if let existing = face.tiles[key] { tileLayer = existing } else {
          tileLayer = pool.popLast() ?? makeTile()
          tileLayer.columns = face.columns
          tileLayer.presentedImage = nil
          tileLayer.photo.contents = nil
          tileLayer.cloud = false
          tileLayer.backgroundColor = (face.columns <= 5 ? DuckRole.mediaPlaceholderUIColor : UIColor.systemBackground).cgColor
          if face.columns <= 5 {
            let badges = tileLayer.decorations ?? CalendarTileDecorations()
            tileLayer.decorations = badges
            tileLayer.addSublayer(badges.layer)
            configureDecorations(badges, tile.asset)
            tileLayer.photo.opacity = badges.imageOpacity
            badges.thumbnail(hasImage: false, cloud: false)
          } else {
            tileLayer.decorations?.layer.removeFromSuperlayer()
            tileLayer.photo.opacity = 1
          }
          face.content.addSublayer(tileLayer)
          face.tiles[key] = tileLayer
          face.requests[key] = configureTile(tileLayer.photo, tile.asset, max(40, side * displayScale))
        }
        // Edges snap to device pixels from the lattice, so every divider in a
        // frame has the same pixel width and adjacent dense tiles never seam.
        if grouped {
          let x0 = snap(frame.minX),y0 = snap(frame.minY)
          tileLayer.frame = CGRect(x: x0,y: y0,width: snap(frame.maxX)-x0,height: snap(frame.maxY)-y0)
        } else {
          let faceGap = CalendarGridGeometry.gap(columns: face.columns)
          let left = focus.x+(frame.minX-face.focus.x)*scale+correction.x
          let top = focus.y+(frame.minY-face.focus.y)*scale+correction.y
          let gapPixels = gap > 0 ? max(1/displayScale,snap(gap)) : 0
          let x0 = snap(left),y0 = snap(top)
          let x1 = snap(left+(frame.width+faceGap)*scale)-gapPixels
          let y1 = snap(top+(frame.height+faceGap)*scale)-gapPixels
          tileLayer.frame = CGRect(x: x0,y: y0,width: max(0.1,x1-x0),height: max(0.1,y1-y0))
        }
        tileLayer.photo.frame = tileLayer.bounds
        if face.columns <= 5, let badges = tileLayer.decorations {
          // Lay out once in the face's native cell coordinates, then transform
          // the entire decoration node, including fonts, padding and corners.
          badges.bounds = CGRect(origin: .zero, size: frame.size)
          badges.layer.anchorPoint = .zero
          badges.layer.position = .zero
          badges.layer.setAffineTransform(CGAffineTransform(
            scaleX: tileLayer.bounds.width / max(1, frame.width),
            y: tileLayer.bounds.height / max(1, frame.height)))
          badges.layoutIfNeeded()
        }
      }
    }
    for (i, tileLayer) in face.tiles where !keep.contains(i) {
      face.requests.removeValue(forKey: i)?()
      recycle(tileLayer)
      face.tiles.removeValue(forKey: i)
    }
    layoutPills(face, scale: scale)
  }
  /// Dense overviews keep their period pills at reading size while the mosaic
  /// scales; colliding pills are skipped, as in the native collection.
  private func layoutPills(_ face: Face, scale: CGFloat) {
    guard face.columns >= 10, !face.geometry.headings.isEmpty else { return }
    var keep = Set<Int>()
    var bottom = -CGFloat.greatestFiniteMagnitude
    for (i, heading) in face.geometry.headings.enumerated() {
      let y = focus.y + (heading.1.minY - face.focus.y) * scale
      if y > bounds.maxY { break }
      guard y + heading.1.height > bounds.minY, y >= bottom + 10,
        let image = pillImage(heading.0, face.columns >= 20)
      else { continue }
      keep.insert(i)
      let pill = face.pills[i] ?? {
        let created = CALayer()
        created.actions = tileActions
        created.contents = image
        created.contentsScale = displayScale
        face.container.addSublayer(created)
        face.pills[i] = created
        return created
      }()
      let size = CGSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale)
      pill.frame = CGRect(origin: CGPoint(x: heading.1.minX, y: y), size: size)
      bottom = y + size.height
    }
    for (i, pill) in face.pills where !keep.contains(i) {
      pill.removeFromSuperlayer(); face.pills.removeValue(forKey: i)
    }
  }
  private func makeTile() -> Tile {
    let tile = Tile()
    tile.actions = tileActions
    tile.photo.actions = tileActions
    tile.backgroundColor = DuckRole.mediaPlaceholderUIColor.cgColor
    return tile
  }
  private func recycle(_ tile: Tile) {
    tile.removeFromSuperlayer()
    tile.photo.contents = nil
    tile.photo.name = nil
    tile.presentedImage = nil
    if pool.count < 1500 { pool.append(tile) }
  }
  private func discard(_ face: Face) {
    face.requests.values.forEach { $0() }
    face.requests = [:]
    for tile in face.tiles.values { recycle(tile) }
    face.tiles = [:]
    face.pills.values.forEach { $0.removeFromSuperlayer() }
    face.pills = [:]
    face.container.removeFromSuperlayer()
  }
  private func prune() {
    guard blend == nil else { return }
    for (columns, face) in faces where columns != shownColumns && face.opacity <= 0.001 {
      discard(face)
      faces.removeValue(forKey: columns)
      faceOrder.removeAll { $0 == columns }
    }
  }
}

/// Forward the owning TabView delegate instead of replacing its navigation logic.
final class CalendarTabReselection: NSObject, UITabBarControllerDelegate {
  weak var owner: CalendarGridController?
  weak var previous: UITabBarControllerDelegate?
  weak var tabs: UITabBarController?
  weak var lastSelected: UIViewController?
  var beganCompact = false
  func tabBarController(
    _ tabBarController: UITabBarController, shouldSelect viewController: UIViewController
  ) -> Bool {
    beganCompact = owner?.usesNativeMinimization == true
      ? owner?.nativeBarRecentlyCompact == true : owner?.chrome == .browsing
    let allowed =
      previous?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
    return allowed
  }
  func tabBarController(
    _ tabBarController: UITabBarController, didSelect viewController: UIViewController
  ) {
    if lastSelected === viewController { returnToLatest(afterExpanding: beganCompact) }
    lastSelected = viewController
    beganCompact = false
    previous?.tabBarController?(tabBarController, didSelect: viewController)
  }
  @available(iOS 18.0, *)
  func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool
  {
    beganCompact = owner?.usesNativeMinimization == true
      ? owner?.nativeBarRecentlyCompact == true : owner?.chrome == .browsing
    return previous?.tabBarController?(tabBarController, shouldSelectTab: tab)
      ?? tab.viewController.flatMap {
        previous?.tabBarController?(tabBarController, shouldSelect: $0)
      } ?? true
  }
  @available(iOS 18.0, *)
  func tabBarController(
    _ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?
  ) {
    if selectedTab === previousTab { returnToLatest(afterExpanding: beganCompact) }
    beganCompact = false
    let selector = #selector(
      UITabBarControllerDelegate.tabBarController(_:didSelectTab:previousTab:))
    if previous?.responds(to: selector) == true {
      previous?.tabBarController?(
        tabBarController, didSelectTab: selectedTab, previousTab: previousTab)
    } else if let controller = selectedTab.viewController {
      previous?.tabBarController?(tabBarController, didSelect: controller)
    }
  }
  /// A compact tap only expands native navigation. Scroll only for a
  /// reselected, already expanded Library tab.
  func returnToLatest(afterExpanding: Bool) {
    guard !afterExpanding, let owner, owner.active else { return }
    owner.returnToLatest()
  }
  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || (previous?.responds(to: selector) ?? false)
  }
  override func forwardingTarget(for selector: Selector!) -> Any? { previous }
  func restore() { if tabs?.delegate === self { tabs?.delegate = previous } }
}

final class CalendarHeaderTitleView: UIView {
  var preferredWidth: CGFloat = 160 { didSet { invalidateIntrinsicContentSize() } }
  override var intrinsicContentSize: CGSize { CGSize(width: preferredWidth,height: 44) }
  override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }
}

final class CalendarNavigationBar: UINavigationBar {
  var ownsSelectionInput = false
  /// While selecting, the bar keeps every touch inside it, including a disabled
  /// Back Up button, so a tap never reaches the photos behind transparent chrome.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point,with: event)
    return hit ?? (ownsSelectionInput && bounds.contains(point) ? self : nil)
  }
}

final class CalendarNavigationController: UINavigationController {
  override init(rootViewController: UIViewController) {
    super.init(navigationBarClass: CalendarNavigationBar.self,toolbarClass: nil)
    viewControllers = [rootViewController]
  }
  required init?(coder: NSCoder) { super.init(coder: coder) }
  override var preferredStatusBarStyle: UIStatusBarStyle {
    (topViewController as? CalendarGridController)?.photosBehindHeader == false ? .default : .lightContent
  }
}

final class CalendarGridController: UIViewController, UICollectionViewDataSource,
  UICollectionViewDelegate, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate
{
  typealias ImageRequest = (CalendarGridAsset, CGFloat, @escaping (UIImage?, Bool) -> Void) -> (
    () -> Void
  )
  var assets: [CalendarGridAsset] = []
  var requestImage: ImageRequest = { _, _, done in
    done(nil, false)
    return {}
  }
  var requestUncroppedImage: ImageRequest?
  var prefetchImage: ImageRequest?
  var onPreview: (CalendarGridAsset, CGRect) -> Void = { _, _ in }
  var photoMenu: ((CalendarGridAsset) -> UIMenu?)?
  var photoPreview: ((CalendarGridAsset, UIImage?) -> UIViewController?)?
  var photoAccessibilityActions: (CalendarGridAsset) -> [UIAccessibilityCustomAction] = { _ in [] }
  private var hiddenPreviewID: String?
  func setPreviewHidden(_ id: String?) {
    hiddenPreviewID = id
    UIView.performWithoutAnimation {
      for case let cell as CalendarGridCell in grid.visibleCells {
        cell.contentView.isHidden = id != nil && cell.assetID == id
      }
      updatePreviewMask()
    }
  }
  private func updatePreviewMask() {
    let frame = (hiddenPreviewID ?? denseMenuID).flatMap { id in layout.geometry.tiles.first(where: { $0.id == id })?.frame }
    denseCanvas.hidePreviewTile(frame)
  }
  private func photoActions(_ asset: CalendarGridAsset) -> [UIAccessibilityCustomAction] {
    guard !selecting else { return [] }
    var actions = [UIAccessibilityCustomAction(name: NSLocalizedString("library_select", comment: "")) { [weak self] _ in
      guard let self, let index = self.assets.firstIndex(where: { $0.id == asset.id }) else { return false }
      if !self.selecting { self.toggleSelection() }
      self.toggleAsset(index); return true
    }]
    actions += photoAccessibilityActions(asset)
    return actions
  }
  var onSelection: (Set<String>) -> Void = { _ in }
  var onBackup: () -> Void = {}
  var menu: (() -> [UIMenuElement])?
  var requestVideo: (CalendarGridAsset, @escaping (AVPlayerItem?) -> Void) -> (() -> Void) = {
    _, done in
    done(nil)
    return {}
  }
  var stage: CalendarZoomStage?, pinchTrack = PinchTrack()
  /// Resolves many host assets in one bulk fetch before their images are requested.
  var prefetchAssets: ([String]) -> Void = { _ in }
  /// Synchronous decoded small thumbnail (memory-mapped table), when stored.
  var storedImage: (CalendarGridAsset, CGFloat) -> UIImage? = { _, _ in nil }
  /// Any small stored thumbnail, shown upscaled in a larger cropped cell until
  /// its own rendition arrives (Photos shows a soft image, never an empty cell).
  var placeholderImage: (CalendarGridAsset) -> UIImage? = { _ in nil }
  let pillImages = NSCache<NSString, UIImage>()
  var motionPreparation: DispatchWorkItem?
  var zoomPixelRequests: [() -> Void] = []
  var adjacentRequests: [() -> Void] = [], adjacentWarmKey: String?
  var scrollingToLatest = false
  /// A Years/Months pinch triggers one level change per gesture, as in Photos.
  var coverPinchTriggered = false
  var coverTimer: Timer?, coverCancel: (() -> Void)?, coverPlaybackID: String?
  weak var playingCoverCell: CalendarGridCell?
  var focusedCoverPeriod: String?
  var coverIndices: [String: Int] = [:]
  var lastCoverChange: CFTimeInterval = 0
  var tabReselection: CalendarTabReselection?
  var motionSourceIDs = Set<String>(), motionDestinationIDs = Set<String>()
  var backupFeedback = "", backupAdded = false
  var canBackup = false
  var indexing = false
  var displayedTotal: Int?
  /// The library's backup view, named in the subtitle when it is not All Photos (design/library.md).
  var viewTitle: String?
  private var subtitleViewTitle: String?
  var onVisibleChange: () -> Void = {}
  var photoStates: [String: String] = [:]
  var selected = Set<String>()
  /// Like Photos, the next launch opens at three columns after one/three, and at
  /// five after five columns or any overview/calendar level.
  static let densityKey = "calendarGridLaunchColumns"
  static var rememberedColumns: Int {
    UserDefaults.standard.integer(forKey: densityKey) == 5 ? 5 : 3
  }
  var level = CalendarGridLevel.all { didSet { rememberDensity() } }
  var columns = CalendarGridController.rememberedColumns { didSet { rememberDensity() } }
  var originalAspect = false, selecting = false
  func rememberDensity() {
    let value = level == .all && columns <= 3 ? 3 : 5
    if UserDefaults.standard.integer(forKey: Self.densityKey) != value {
      UserDefaults.standard.set(value, forKey: Self.densityKey)
    }
  }
  let layout = CalendarGridLayout(), titleLabel = UILabel(), subtitleLabel = UILabel()
  lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
  let headerBackdrop = UIView(), headerFade = CAGradientLayer()
  let titleView = CalendarHeaderTitleView(),
    dock = UISegmentedControl(items: [
      NSLocalizedString("calendar_years", comment: ""),
      NSLocalizedString("calendar_months", comment: ""),
      NSLocalizedString("calendar_all", comment: ""),
    ]), bottom = UIView()
  let libraryButton = UIButton(type: .system)
  let browsingControls = UIView(), selectionControls = CalendarSelectionControls(),
    periodSurface = UIVisualEffectView()
  var selectedButton: UIButton { selectionControls.countButton }
  let transitionImages = NSCache<NSString, UIImage>()
  let transitionSmallImages = NSCache<NSString, UIImage>()
  var adoptingTiles: [String: CalendarTilePresentation] = [:]
  var adoptionCover: CalendarZoomStage?
  var periodFocusAssetID: String?
  var subtitleRange: ClosedRange<Int>?
  var subtitleAtRecentEdge: Bool?
  var subtitleIndexing: Bool?, subtitleTotal: Int?
  var denseDateLabels: [Date: String] = [:]
  enum Chrome { case navigation, browsing, selection }
  var nativeBarObserver: CalendarNativeBarObserver?
  var restoringNativeNavigation = false
  var chrome: Chrome = .navigation, chromeMotion: UIViewPropertyAnimator?,
    expandedNavigation = false
  var filterItem: UIBarButtonItem!, selectItem: UIBarButtonItem!, closeItem: UIBarButtonItem!,
    backupItem: UIBarButtonItem!, moreItem: UIBarButtonItem!
  var headerSelecting: Bool?
  weak var tabOwner: UITabBarController?
  weak var contentOwner: UIViewController?
  var spring: UIViewPropertyAnimator?, transitionOverlay: UIView?
  var anchor: Int?, anchorFraction = CGPoint(x: 0.5, y: 0.5), anchorPoint = CGPoint.zero
  var leadingSlots = 0
  var width: CGFloat = 0, hasPosition = false, changing = false, nativeBarCompact = false
  var geometryCache: [String: CalendarGridGeometry] = [:], geometryVersion = UUID(),
    geometryWork: Task<Void, Never>?
  let intervalFormatter: DateIntervalFormatter = {
    let formatter = DateIntervalFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()
  var chromeUpdating = false
  var active = false
  var rangeLink: CADisplayLink?, rangeTime: CFTimeInterval = 0, rangePoint = CGPoint.zero
  var selectionBaseline = Set<String>(), selectionStart: Int?, selectionAdding = true,
    selectionModeBeforeRange = false
  /// One column, three, five, then dense month and year overviews (Photos stops).
  let columnStops = [1, 3, 5, 15, 31]
  override func viewDidLoad() {
    super.viewDidLoad()
    LaunchTrace.mark("grid view loaded")
    transitionImages.totalCostLimit = 24 * 1024 * 1024
    transitionImages.countLimit = 8192
    transitionSmallImages.totalCostLimit = 16 * 1024 * 1024
    transitionSmallImages.countLimit = 8192
    view.backgroundColor = UIColor.systemBackground
    grid.backgroundColor = .clear
    grid.dataSource = self
    grid.delegate = self
    grid.contentInsetAdjustmentBehavior = .never
    grid.accessibilityIdentifier = "library.grid"
    announceDensity()
    grid.register(CalendarGridCell.self, forCellWithReuseIdentifier: "calendar.asset")
    grid.register(
      CalendarGlassHeading.self, forSupplementaryViewOfKind: CalendarGridLayout.headingKind,
      withReuseIdentifier: "calendar.heading")
    view.addSubview(grid)
    grid.showsVerticalScrollIndicator = false
    grid.alwaysBounceVertical = true
    setContentScrollView(grid, for: .all)
    if #available(iOS 26.0, *) {
      grid.topEdgeEffect.isHidden = true
      grid.bottomEdgeEffect.isHidden = true
    }
    grid.panGestureRecognizer.maximumNumberOfTouches = 1
    configureDenseCanvas()
    NotificationCenter.default.addObserver(forName: UIAccessibility.voiceOverStatusDidChangeNotification,
      object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.syncDenseCanvas() }
    }
    for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willResignActiveNotification] {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.saveLaunchSnapshot() }
      }
    }
    NotificationCenter.default.addObserver(forName: Notification.Name("LibraryThumbnailsCleared"),
      object: nil, queue: .main) { _ in Self.clearLaunchSnapshot() }
    let denseTap = UITapGestureRecognizer(target: self, action: #selector(denseTap(_:)))
    denseTap.delegate = self
    grid.addGestureRecognizer(denseTap)
    let pinch = CalendarPinchGesture(target: self, action: #selector(pinch(_:)))
    pinch.delegate = self
    grid.addGestureRecognizer(pinch)
    let long = CalendarRangeGesture(target: self, action: #selector(rangeSelect(_:)))
    long.minimumPressDuration = 0.4
    long.delegate = self
    grid.addGestureRecognizer(long)
    grid.addInteraction(UIContextMenuInteraction(delegate: self))
    titleLabel.text = NSLocalizedString("nav_library", comment: "")
    titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
    titleLabel.textColor = DuckMedia.onMediaUIColor
    subtitleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
      for: .systemFont(ofSize: 15, weight: .semibold), maximumPointSize: 22)
    subtitleLabel.adjustsFontSizeToFitWidth = true
    subtitleLabel.minimumScaleFactor = 0.8
    subtitleLabel.textColor = DuckMedia.onMediaSecondaryUIColor
    subtitleLabel.accessibilityIdentifier = "library.count"
    titleView.addSubview(titleLabel)
    // The subtitle belongs below the native navigation bar, not in an oversized
    // 72-point bar item. A semantic edge fade keeps it legible over light media.
    headerBackdrop.isUserInteractionEnabled = false
    headerBackdrop.layer.addSublayer(headerFade)
    view.addSubview(headerBackdrop)
    view.addSubview(subtitleLabel)
    titleView.frame = CGRect(
      x: 0, y: 0, width: max(selecting ? 70 : 105, min(160, view.bounds.width - (selecting ? 280 : 238))), height: 44)
    titleLabel.frame = CGRect(x: 0, y: 0, width: titleView.bounds.width, height: 39)
    let titleItem = UIBarButtonItem(customView: titleView)
    if #available(iOS 26.0, *) { titleItem.hidesSharedBackground = true }
    navigationItem.leftBarButtonItem = titleItem
    selectItem = UIBarButtonItem(
      title: NSLocalizedString("select", comment: ""), style: .plain, target: self, action: #selector(toggleSelection))
    selectItem.accessibilityIdentifier = "library.select_mode"
    closeItem = UIBarButtonItem(
      barButtonSystemItem: .close, target: self, action: #selector(toggleSelection))
    closeItem.accessibilityIdentifier = "library.select_mode"
    closeItem.accessibilityLabel = NSLocalizedString("settings_done", comment: "")
    filterItem = UIBarButtonItem(
      image: UIImage(systemName: "line.3.horizontal.decrease"), style: .plain, target: nil,
      action: nil)
    filterItem.accessibilityIdentifier = "library.filter"
    filterItem.accessibilityLabel = NSLocalizedString("media_type", comment: "")
    moreItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: nil)
    moreItem.accessibilityIdentifier = "library.more"
    moreItem.accessibilityLabel = NSLocalizedString("folder_more", comment: "")
    refreshMenu()
    updateHeader(animated: false)
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    navigationController?.navigationBar.standardAppearance = appearance
    navigationController?.navigationBar.scrollEdgeAppearance = appearance
    navigationController?.navigationBar.compactAppearance = appearance
    navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    navigationController?.navigationBar.tintColor = DuckMedia.onMediaUIColor
    dock.selectedSegmentIndex = 2
    dock.accessibilityIdentifier = "library.view_mode"
    dock.addTarget(self, action: #selector(levelChosen), for: .valueChanged)
    if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
      periodSurface.effect = UIGlassEffect(style: .regular)
    } else {
      periodSurface.effect = UIBlurEffect(style: .systemChromeMaterial)
    }
    if #available(iOS 26.0, *) { periodSurface.cornerConfiguration = .capsule() }
    else { periodSurface.layer.cornerRadius = 25 }
    periodSurface.clipsToBounds = true
    periodSurface.contentView.addSubview(dock)
    browsingControls.addSubview(periodSurface)
    libraryButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
    libraryButton.accessibilityLabel = NSLocalizedString("calendar_navigation", comment: "")
    libraryButton.accessibilityIdentifier = "calendar.navigation"
    libraryButton.addAction(
      UIAction { [weak self] _ in
        self?.expandedNavigation = true
        self?.updateChrome()
      }, for: .touchUpInside)
    browsingControls.addSubview(libraryButton)
    view.addSubview(browsingControls)
    selectedButton.addAction(
      UIAction { [weak self] _ in self?.reviewSelection() }, for: .touchUpInside)
    selectedButton.accessibilityIdentifier = "calendar.review_selected"
    // Retain the backup action's enabled state for the selection overflow menu.
    backupItem = UIBarButtonItem(
      title: NSLocalizedString("calendar_backup_short", comment: ""), style: .done, target: self, action: #selector(backUpSelected))
    if #available(iOS 26.0, *) { backupItem.style = .prominent }
    backupItem.tintColor = DuckGlyph.blueUIColor
    backupItem.isEnabled = false
    backupItem.accessibilityIdentifier = "calendar.backup_selected"
    backupItem.accessibilityLabel = NSLocalizedString("calendar_backup_action",comment: "")
    view.addSubview(selectionControls)
    var normal: UIButton.Configuration
    if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
      normal = .prominentGlass()
    } else {
      normal = .bordered()
    }
    selectedButton.configuration = normal
    normal.baseBackgroundColor = DuckRole.elevatedSurfaceUIColor
    normal.cornerStyle = .capsule
    normal.baseForegroundColor = DuckRole.primaryTextUIColor
    normal.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { original in
      var result = original
      result.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
        for: .systemFont(ofSize: 17, weight: .semibold), maximumPointSize: 22)
      return result
    }
    libraryButton.configuration = normal
    browsingControls.isHidden = true
    selectionControls.isHidden = true
    loadLaunchSnapshot()
  }
  func setBackupFeedback(title: String, added: Bool) {
    guard backupFeedback != title || backupAdded != added else { return }
    backupFeedback = title; backupAdded = added
    headerSelecting = nil
  }
  @objc func backUpSelected() {
    guard canBackup, !selected.isEmpty else { return }
    onBackup()
  }
  func refreshMenu() {
    filterItem?.menu = displayMenu()
    let backup = UIAction(title: NSLocalizedString("calendar_backup_action", comment: ""),
      image: UIImage(systemName: "arrow.up"), attributes: canBackup && !selected.isEmpty ? [] : .disabled) { [weak self] _ in
      self?.backUpSelected()
    }
    moreItem?.menu = UIMenu(children: [backup, displayMenu()])
  }
  func updateHeader(animated: Bool) {
    guard headerSelecting != selecting else { return }
    headerSelecting = selecting
    titleView.preferredWidth = max(selecting ? 70 : 105, min(160, view.bounds.width - (selecting ? 280 : 238)))
    titleView.frame.size.width = titleView.preferredWidth
    titleLabel.frame.size.width = titleView.bounds.width
    // Transparent chrome still owns its entire selection header, including the
    // subtitle strip below the navigation buttons and the gaps between them.
    headerBackdrop.isUserInteractionEnabled = selecting
    grid.scrollsToTop = !selecting
    (navigationController?.navigationBar as? CalendarNavigationBar)?.ownsSelectionInput = selecting
    // The same item objects persist across the switch and the change is
    // animated, so the bar uses the system transition (a glass morph on iOS 26)
    // instead of replacing its groups at once.
    let items: [UIBarButtonItem] = selecting ? [backupItem, closeItem]
      : backupAdded ? [backupItem, selectItem, filterItem] : [selectItem, filterItem]
    navigationItem.setRightBarButtonItems(items, animated: animated && !UIAccessibility.isReduceMotionEnabled)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    LaunchTrace.mark("grid view appeared")
    active = true
    startCoverClock()
    installTabReselection()
    tabOwner = tabBarController
    contentOwner = tabBarController?.selectedViewController
    if #available(iOS 26.0, *), let tabs = tabBarController {
      if nativeBarObserver == nil { nativeBarObserver = CalendarNativeBarObserver(owner: self) }
      // Follow the native bar through public laid-out geometry.
      let native = nativeBarObserver?.start(tabs.tabBar) == true
      tabs.tabBarMinimizeBehavior = native ? .onScrollUp : .never
      contentOwner?.setContentScrollView(grid, for: .all)
    }
    rebuildIfNeeded()
    updateChrome()
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    active = false
    adjacentRequests.forEach { $0() }; adjacentRequests = []; adjacentWarmKey = nil
    stopMotion()
    nativeBarObserver?.stop()
    nativeBarCompact = false
    setNativePeriod(false, animated: false)
    stopCoverPlayback()
    coverTimer?.invalidate()
    coverTimer = nil
    tabReselection?.restore()
    tabReselection = nil
    stopRange(revert: true)
    chromeMotion?.stopAnimation(true)
    chromeMotion = nil
    if tabOwner?.selectedViewController !== contentOwner { restoreNavigation() }
  }
  func restoreNavigation() {
    tabReselection?.restore()
    tabReselection = nil
    coverTimer?.invalidate()
    coverTimer = nil
    stopCoverPlayback()
    periodSurface.removeFromSuperview()
    nativeBarCompact = false
    if #available(iOS 26.0, *) {
      tabOwner?.tabBarMinimizeBehavior = .never
      nativeBarObserver?.stop()
      contentOwner?.setContentScrollView(nil, for: .bottom)
    }
    if #available(iOS 18.0, *) { tabOwner?.setTabBarHidden(false, animated: false) }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // Bounds and center stay valid while a level change scales the collection.
    grid.bounds.size = view.bounds.size
    grid.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    let titleWidth = max(selecting ? 70 : 105, min(160, view.bounds.width - (selecting ? 280 : 238)))
    titleView.preferredWidth = titleWidth
    titleView.frame.size.width = titleWidth
    titleLabel.frame.size.width = titleWidth
    let subtitleHeight = subtitleLabel.font.lineHeight + 4
    let titleRect = titleLabel.convert(titleLabel.bounds,to:view)
    subtitleLabel.frame = CGRect(
      x: titleRect.minX, y: max(view.window?.safeAreaInsets.top ?? 0, titleRect.maxY),
      width: view.bounds.width - titleRect.minX - 20, height: subtitleHeight)
    let headerLevel = level
    let headerColumns = stage == nil ? columns : pinchTrack.headerColumns
    let showsInterval = headerLevel == .all && headerColumns <= 5
    headerBackdrop.frame = CGRect(
      x: 0, y: 0, width: view.bounds.width,
      height: showsInterval ? subtitleLabel.frame.maxY + 16 : view.safeAreaInsets.top + 16)
    headerFade.frame = headerBackdrop.bounds
    headerBackdrop.isHidden = navigationController?.isNavigationBarHidden == true
    subtitleLabel.isHidden = !showsInterval
    updateMediaHeader()
    updateHeaderFade()
    titleLabel.adjustsFontSizeToFitWidth = true
    titleLabel.minimumScaleFactor = 0.75
    let home = view.window?.safeAreaInsets.bottom ?? 34
    grid.contentInset = gridInsets(showsInterval: showsInterval)
    let frame = CGRect(
      x: 0, y: view.bounds.height - home - 60, width: view.bounds.width, height: 44)
    browsingControls.frame = frame
    if selectionControls.superview === view {
      selectionControls.frame = frame
    }
    libraryButton.frame = CGRect(x: 16, y: 0, width: 50, height: 50)
    if periodSurface.superview === browsingControls {
      periodSurface.frame = CGRect(x: 72, y: 0, width: view.bounds.width - 144, height: 50)
    }
    if dock.superview === periodSurface.contentView {
      dock.bounds = CGRect(origin:.zero,size:CGSize(width:periodSurface.bounds.width-8,height:periodSurface.bounds.height-8))
      dock.center = CGPoint(x:periodSurface.bounds.midX,y:periodSurface.bounds.midY)
    }
    // Exclude glass navigation from the collection's accessible interaction
    // rectangle while keeping its visual viewport beneath the native bars.
    var interactionBottom = view.bounds.height - home - 8
    if let tabs = tabBarController, !tabs.tabBar.isHidden {
      let bar = tabs.tabBar.convert(tabs.tabBar.bounds, to: view)
      if bar.minY > view.safeAreaInsets.top { interactionBottom = min(interactionBottom, bar.minY) }
    }
    if !browsingControls.isHidden {
      interactionBottom = min(interactionBottom, browsingControls.frame.minY)
    }
    if selecting { interactionBottom = min(interactionBottom, selectionControls.frame.minY) }
    let interactionTop = view.safeAreaInsets.top + 8
    grid.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(
      CGRect(
        x: 0, y: interactionTop, width: view.bounds.width,
        height: max(1, interactionBottom - interactionTop)), in: view)
    rebuildIfNeeded()
    updateChrome()
    syncDenseCanvas()
    layoutLaunchCover()
  }
  /// Collection insets for a header with or without the interval subtitle.
  func gridInsets(showsInterval: Bool) -> UIEdgeInsets {
    let subtitleHeight = subtitleLabel.font.lineHeight + 4
    return UIEdgeInsets(
      top: view.safeAreaInsets.top + (showsInterval ? subtitleHeight - 4 : 4), left: 0,
      bottom: view.safeAreaInsets.bottom + 6, right: 0)
  }
  /// Light-on-photo chrome only when photos actually lie behind the header. A
  /// short view (a backup view with a few photos) leaves the canvas there.
  var photosBehindHeader: Bool {
    guard !assets.isEmpty else { return false }
    // Before the grid has a size, keep the media contrast so launch never flashes.
    guard grid.bounds.height > 0, grid.bounds.width > 0 else { return true }
    let content: CGFloat
    if level == .all {
      // Estimated from the count, so it is right the moment photos are set,
      // without waiting for the geometry rebuild.
      let columnCount = CGFloat(max(columns, 1))
      content = (CGFloat(assets.count) / columnCount).rounded(.up) * grid.bounds.width / columnCount
    } else {
      content = layout.geometry.height
    }
    return content + grid.adjustedContentInset.top + grid.adjustedContentInset.bottom > grid.bounds.height
  }
  private var headerOverPhotos: Bool?
  func updateMediaHeader() {
    let hasMedia = photosBehindHeader
    // This runs from layout, including while scrolling: refresh the status bar only on a change.
    if headerOverPhotos != hasMedia {
      headerOverPhotos = hasMedia
      navigationController?.setNeedsStatusBarAppearanceUpdate()
    }
    titleLabel.textColor = hasMedia ? DuckMedia.onMediaUIColor : DuckRole.primaryTextUIColor
    subtitleLabel.textColor = hasMedia ? DuckMedia.onMediaSecondaryUIColor : DuckRole.secondaryTextUIColor
    headerBackdrop.isHidden = !hasMedia || navigationController?.isNavigationBarHidden == true
    navigationController?.navigationBar.overrideUserInterfaceStyle = hasMedia ? .dark : .unspecified
    navigationController?.navigationBar.tintColor = hasMedia ? DuckMedia.onMediaUIColor : DuckRole.accentUIColor
  }
  func updateHeaderFade() {
    // Native bars retain their own materials; no extra scrolling shadow or
    // custom gradient appears when the underlying collection becomes visible.
    headerFade.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor]
    headerFade.locations = [0, 1]
  }
  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      updateHeaderFade()
      // V1: existing raster strips must adopt the new system surface as well.
      denseCanvasKey = ""
      syncDenseCanvas()
    }
  }
  /// Library changes (iCloud sync adds or updates items continuously) must not
  /// interrupt browsing. Identical rebuilds are ignored; a change during any
  /// motion waits for it to finish. Pixels already on screen stay cached, and
  /// the same photo keeps its screen position (or the view stays at the newest
  /// edge), instead of recentering and reloading every thumbnail.
  var pendingAssets: [CalendarGridAsset]?
  var motionActive: Bool {
    changing || stage != nil || adoptionCover != nil || selectionStart != nil
  }
  func replaceAssets(_ values: [CalendarGridAsset]) {
    if values == assets { pendingAssets = nil; return }
    if isViewLoaded, !assets.isEmpty, motionActive { pendingAssets = values; return }
    pendingAssets = nil
    let first = assets.isEmpty
    var anchorID: String?, anchorScreenY: CGFloat = 0
    let measurable = isViewLoaded && grid.bounds.height > 0 && !first
    let atNewest = measurable && clampedOffset(.greatestFiniteMagnitude) - grid.contentOffset.y < 24
    if measurable, !atNewest, let id = focusedAsset(),
      let index = assets.firstIndex(where: { $0.id == id }),
      let tile = layout.geometry.tiles.firstIndex(where: { $0.members.contains(index) })
    {
      anchorID = id
      anchorScreenY = layout.frame(tile).minY - grid.contentOffset.y
    }
    // Items added before the oldest edge keep every existing row's composition.
    if level == .all, !first, values.count > assets.count,
      values.suffix(assets.count).elementsEqual(assets)
    {
      let added = values.count - assets.count
      leadingSlots = ((leadingSlots - added) % columns + columns) % columns
    }
    stopRange(revert: false)
    stopMotion()
    geometryWork?.cancel()
    geometryVersion = UUID()
    geometryCache = [:]
    adjacentRequests.forEach { $0() }; adjacentRequests = []; adjacentWarmKey = nil
    assets = values
    if let id = periodFocusAssetID, !values.contains(where: { $0.id == id }) { periodFocusAssetID = nil }
    updateMediaHeader()
    view.setNeedsLayout()
    coverIndices = [:]
    denseDateLabels = [:]
    subtitleRange = nil
    subtitleAtRecentEdge = nil
    width = 0
    hasPosition = !first
    guard isViewLoaded else { return }
    rebuildIfNeeded()
    if atNewest {
      scrollToLatest()
    } else if let anchorID, let index = assets.firstIndex(where: { $0.id == anchorID }),
      let tile = layout.geometry.tiles.firstIndex(where: { $0.members.contains(index) })
    {
      grid.contentSize = layout.collectionViewContentSize
      place(layout.frame(tile).minY - anchorScreenY)
    }
    updateChrome()
    syncDenseCanvas()
    if first { revealGridUnderLaunchCover() }
    // The host publishes a newest slice first; the benchmark waits for the rest.
    scheduleBenchmark(fullLibrary: !first || values.count < 600)
  }
  /// Applies a library change that arrived while motion was running.
  func applyPendingAssets() {
    DispatchQueue.main.async { [weak self] in
      guard let self, let values = self.pendingAssets, !self.motionActive else { return }
      self.replaceAssets(values)
    }
  }
  func rebuildIfNeeded() {
    guard grid.bounds.width > 0, width != grid.bounds.width else { return }
    width = grid.bounds.width
    layout.level = level
    layout.geometry = geometry()
    grid.reloadData()
    grid.layoutIfNeeded()
    if !hasPosition {
      scrollToLatest()
      hasPosition = true
    }
    warmGeometry()
    let version = geometryVersion
    DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { [weak self] in
      guard let self,self.geometryVersion == version else { return }
      self.warmAdjacentScenes()
    }
  }
  func geometry() -> CalendarGridGeometry {
    let key = geometryKey(
      level, width: width, columns: columns, aspect: originalAspect, leading: leadingSlots)
    if let cached = geometryCache[key] { return cached }
    let result = CalendarGridGeometry(
      assets: assets, level: level, width: width, columns: columns, originalAspect: originalAspect,
      leadingSlots: leadingSlots)
    if geometryCache.count > 7 {
      // Calendar covers stay warm when successive All-grid densities churn.
      geometryCache = geometryCache.filter { !$0.key.hasPrefix("2|") }
    }
    geometryCache[key] = result
    return result
  }
  nonisolated static func geometryKey(
    _ level: CalendarGridLevel, width: CGFloat, columns: Int, aspect: Bool, leading: Int = 0
  ) -> String {
    level == .all
      ? "\(level.rawValue)|\(width)|\(columns)|\(aspect)|\(leading)" : "\(level.rawValue)|\(width)"
  }
  func geometryKey(
    _ level: CalendarGridLevel, width: CGFloat, columns: Int, aspect: Bool, leading: Int = 0
  ) -> String {
    Self.geometryKey(level, width: width, columns: columns, aspect: aspect, leading: leading)
  }
  func warmGeometry() {
    geometryWork?.cancel()
    let snapshot = assets
    let width = width
    let version = geometryVersion
    let targetColumns = columns
    let aspect = originalAspect
    let task = Task.detached(priority: .utility) {
      var result: [String: CalendarGridGeometry] = [:]
      for mode in [CalendarGridLevel.years, .months] {
        guard !Task.isCancelled else { break }
        result[Self.geometryKey(mode, width: width, columns: targetColumns, aspect: aspect)] =
          CalendarGridGeometry(
            assets: snapshot, level: mode, width: width, columns: targetColumns,
            originalAspect: aspect)
      }
      return result
    }
    geometryWork = Task { [weak self] in
      let values = await withTaskCancellationHandler(
        operation: { await task.value }, onCancel: { task.cancel() })
      guard let self, !Task.isCancelled, self.geometryVersion == version, self.width == width else {
        return
      }
      self.geometryCache.merge(values) { old, _ in old }
    }
  }
  func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
  func collectionView(_ view: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    layout.geometry.tiles.count
  }
  func collectionView(_ view: UICollectionView, cellForItemAt path: IndexPath)
    -> UICollectionViewCell
  {
    LaunchTrace.mark("first grid cell")
    let cell =
      view.dequeueReusableCell(withReuseIdentifier: "calendar.asset", for: path)
      as! CalendarGridCell
    guard layout.geometry.tiles.indices.contains(path.item) else { return cell }
    let tile = layout.geometry.tiles[path.item]
    let displayed = coverIndices[tile.id] ?? tile.asset
    let asset = assets[displayed]
    cell.contentView.isHidden = hiddenPreviewID == asset.id
    cell.accessibilityCustomActions = level == .all ? photoActions(asset) : nil
    cell.coverAsset = displayed
    cell.liveMark.image = asset.live ? CalendarTileDecorations.Style.symbol("livephoto") : nil
    cell.assetID = asset.id
    cell.image.contentMode = originalAspect && level == .all ? .scaleAspectFit : .scaleAspectFill
    cell.label.text = tile.label
    cell.label.isHidden = level == .all
    cell.scrim.isHidden = level == .all
    cell.contentView.layer.cornerRadius = level == .all ? 0 : 12
    cell.contentView.clipsToBounds = true
    cell.accessibilityIdentifier = "library.asset." + asset.id
    cell.accessibilityLabel =
      tile.label.isEmpty ? asset.date?.formatted(date: .abbreviated, time: .shortened) : tile.label
    cell.isHidden = changing && motionDestinationIDs.contains(asset.id)
    cell.selection(selected.contains(asset.id), enabled: selecting && level == .all)
    cell.duration.text = asset.videoDuration
    cell.backupState(photoStates[asset.id], visible: !selecting && level == .all)
    let presented = adoptingTiles[asset.id]
    if let badges = presented?.badges {
      cell.decorations.apply(badges)
      cell.image.alpha = CGFloat(badges.imageOpacity)
    }
    let uncropped = level == .all && columns == 1
    cell.assetAspect = uncropped ? asset.aspect : nil
    if let image = presented?.image ?? transitionImages.object(forKey: asset.id as NSString) {
      cell.thumbnail(image, cloud: presented?.cloud ?? false)
    } else {
      let soft = uncropped ? nil : placeholderImage(asset)
      if soft != nil { LaunchTrace.mark("first table placeholder") }
      cell.thumbnail(soft, cloud: false, soft: true)
    }
    cell.resumeThumbnail = { [weak self, weak cell, weak view] in
      guard let self, let cell, let view, cell.assetID == asset.id else { return }
      let request = uncropped ? self.requestUncroppedImage ?? self.requestImage : self.requestImage
      cell.cancel = request(asset, max(40,self.layout.frame(path.item).width * view.traitCollection.displayScale)) {
        [weak self, weak cell] image, cloud in
        guard cell?.assetID == asset.id else { return }
        if let image { self?.rememberImage(image, for: asset.id, aspect: uncropped ? asset.aspect : nil) }
        cell?.thumbnail(image ?? self?.transitionImages.object(forKey:asset.id as NSString), cloud: cloud)
      }
    }
    cell.resumeThumbnail?()
    return cell
  }
  // Dense browsing has no collection cells. Resolve one tile from its existing
  // geometry and bitmap canvas rather than materializing a grid of views.
  private var denseMenuPreview: UIImageView?
  private var denseMenuID: String?
  private weak var photoMenuSourceView: UIView?
  func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    guard !selecting, level == .all,
      !motionActive, let index = item(at: location), layout.geometry.tiles.indices.contains(index) else { return nil }
    let tile = layout.geometry.tiles[index], asset = assets[layout.geometry.tiles[index].asset]
    denseMenuPreview?.removeFromSuperview(); denseMenuID = nil
    if let cell = grid.cellForItem(at: IndexPath(item: index, section: 0)) as? CalendarGridCell,
      cell.assetID == asset.id {
      photoMenuSourceView = cell.image
    } else {
      let preview = UIImageView(image: denseCanvas.displayedImage(tile.asset) ?? placeholderImage(asset))
      preview.frame = tile.frame; preview.contentMode = .scaleAspectFill; preview.clipsToBounds = true
      grid.addSubview(preview); denseMenuPreview = preview; photoMenuSourceView = preview
      denseMenuID = asset.id; updatePreviewMask()
    }
    let poster = (photoMenuSourceView as? UIImageView)?.image
      ?? transitionImages.object(forKey: asset.id as NSString) ?? denseCanvas.displayedImage(tile.asset)
    return UIContextMenuConfiguration(identifier: asset.id as NSString, previewProvider: { [weak self] in
      self?.photoPreview?(asset, poster)
    }) { [weak self] _ in self?.photoMenu?(asset) }
  }
  func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
    previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    photoMenuSourceView.map { UITargetedPreview(view: $0) }
  }
  func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
    previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    photoMenuSourceView.map { UITargetedPreview(view: $0) }
  }
  func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
    let preview = denseMenuPreview
    let finish = { [weak self] in
      preview?.removeFromSuperview()
      guard let self, self.denseMenuPreview === preview else { return }
      self.denseMenuPreview = nil; self.photoMenuSourceView = nil; self.denseMenuID = nil
      self.updatePreviewMask()
    }
    if let animator { animator.addCompletion(finish) }
    else { finish() }
  }
  func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionCommitAnimating) {
    guard let id = configuration.identifier as? String else { return }
    animator.preferredCommitStyle = .dismiss
    animator.addCompletion { [weak self] in
      guard let self, let index = self.assets.firstIndex(where: { $0.id == id }) else { return }
      let frame = self.layout.frame(index)
      if !self.grid.bounds.inset(by: self.grid.adjustedContentInset).contains(frame) { self.locateAsset(index) }
      self.onPreview(self.assets[index], self.grid.convert(self.layout.frame(index), to: nil))
    }
  }
  var tracedImages = 0
  func rememberImage(_ image: UIImage, for id: String, aspect: CGFloat? = nil) {
    if LaunchTrace.enabled, tracedImages < 30 {
      tracedImages += 1
      if [1, 10, 30].contains(tracedImages) { LaunchTrace.mark("grid image \(tracedImages)") }
    }
    let cost =
      image.cgImage.map { $0.bytesPerRow * $0.height }
      ?? Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    if max(image.size.width, image.size.height) * image.scale <= 128 {
      transitionSmallImages.setObject(image, forKey: id as NSString, cost: cost)
    }
    let existing = transitionImages.object(forKey:id as NSString)
    guard calendarPreferredImage(existing, image, aspect: aspect) === image else { return }
    transitionImages.setObject(image, forKey: id as NSString, cost: cost)
  }
  // MARK: Launch snapshot

  /// PhotoKit needs about a quarter second at launch before any thumbnail can
  /// exist. Like the system's own app snapshots, the newest edge is rendered from
  /// cached pixels when the app leaves the foreground and shown in the first
  /// frame of the next launch, then removed once real cells hold their images.
  /// It is a rebuildable cache: cleared with thumbnails and never backed up.
  struct LaunchSnapshotInfo: Codable { let columns: Int; let width: CGFloat; let height: CGFloat; let newest: String }
  static var launchSnapshotURL: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("library-launch-snapshot.jpg")
  }
  static var launchSnapshotInfoURL: URL {
    launchSnapshotURL.deletingPathExtension().appendingPathExtension("json")
  }
  static func clearLaunchSnapshot() {
    try? FileManager.default.removeItem(at: launchSnapshotURL)
    try? FileManager.default.removeItem(at: launchSnapshotInfoURL)
  }
  /// Off while evaluating launch without the cover: the decoded tables now give
  /// first-screen cells soft pixels as soon as the library index publishes.
  static let usesLaunchSnapshot = false
  var launchCover: UIImageView?
  var launchSnapshotInfo: LaunchSnapshotInfo?
  var launchSnapshotSaved = false
  func loadLaunchSnapshot() {
    guard Self.usesLaunchSnapshot, let data = try? Data(contentsOf: Self.launchSnapshotInfoURL),
      let info = try? JSONDecoder().decode(LaunchSnapshotInfo.self, from: data),
      info.columns == columns, let image = UIImage(contentsOfFile: Self.launchSnapshotURL.path)
    else { return }
    let cover = UIImageView(image: image)
    cover.contentMode = .scaleToFill
    cover.isUserInteractionEnabled = false
    view.insertSubview(cover, aboveSubview: grid)
    launchCover = cover
    launchSnapshotInfo = info
  }
  func layoutLaunchCover() {
    guard let cover = launchCover, let info = launchSnapshotInfo else { return }
    // A different window size or density would misplace every photo.
    if abs(info.width - view.bounds.width) > 0.5 || abs(info.height - view.bounds.height) > 0.5 {
      removeLaunchCover(animated: false); return
    }
    cover.frame = view.bounds
  }
  /// Fades the cover once the visible cells hold images (bounded wait).
  func revealGridUnderLaunchCover(attempt: Int = 0) {
    guard let cover = launchCover else { return }
    let cells = grid.visibleCells.compactMap { $0 as? CalendarGridCell }
    // Soft placeholders would trade the sharp cover for blur, so they do not count.
    let ready = !cells.isEmpty && cells.filter { $0.image.image != nil && !$0.softImage }.count * 10 >= cells.count * 9
    if (ready && !assets.isEmpty) || attempt >= 40 {
      _ = cover
      removeLaunchCover(animated: true)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
      self?.revealGridUnderLaunchCover(attempt: attempt + 1)
    }
  }
  func removeLaunchCover(animated: Bool) {
    guard let cover = launchCover else { return }
    launchCover = nil
    guard animated, !UIAccessibility.isReduceMotionEnabled else { cover.removeFromSuperview(); return }
    UIView.animate(withDuration: 0.12, animations: { cover.alpha = 0 }) { _ in cover.removeFromSuperview() }
  }
  /// Renders the newest edge of the remembered density from cached pixels.
  func saveLaunchSnapshot() {
    guard Self.usesLaunchSnapshot, isViewLoaded, level == .all, columns <= 5, !assets.isEmpty, stage == nil, !changing,
      grid.bounds.width > 0, view.window != nil
    else { return }
    let geometry = layout.geometry
    let newest = clampedOffset(.greatestFiniteMagnitude)
    let viewport = CGRect(x: 0, y: newest, width: grid.bounds.width, height: grid.bounds.height)
    let tiles = geometry.visible(in: viewport).filter { geometry.tiles[$0].frame.intersects(viewport) }
    let cached = tiles.filter {
      let id = assets[geometry.tiles[$0].asset].id as NSString
      return transitionImages.object(forKey: id) != nil || transitionSmallImages.object(forKey: id) != nil
    }
    // Never persist a mostly blank screen.
    guard !tiles.isEmpty, cached.count * 10 >= tiles.count * 9 else { return }
    let image = sceneImage(viewport: viewport)
    let snapshot = UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
      UIColor.systemBackground.setFill(); UIRectFill(CGRect(origin: .zero, size: view.bounds.size))
      image.draw(in: grid.frame)
    }
    let info = LaunchSnapshotInfo(columns: columns, width: view.bounds.width, height: view.bounds.height,
      newest: assets.last?.id ?? "")
    DispatchQueue.global(qos: .utility).async {
      guard let data = snapshot.jpegData(compressionQuality: 0.85),
        let json = try? JSONEncoder().encode(info) else { return }
      try? data.write(to: Self.launchSnapshotURL, options: .atomic)
      try? json.write(to: Self.launchSnapshotInfoURL, options: .atomic)
    }
  }

  // MARK: Dense scroll benchmark

  /// Launch argument `-dense-scroll-benchmark`: after indexing (and the
  /// thumbnail prefill, when enabled) the 31-column overview scrolls at a fixed
  /// speed and frame hitches and blank tiles are printed. Measurement only.
  static let benchmarking = ProcessInfo.processInfo.arguments.contains("-dense-scroll-benchmark")
  var benchmarkScheduled = false
  var benchmarkLink: CADisplayLink?
  var benchmarkPass = 0, benchmarkStart: CFTimeInterval = 0, benchmarkLast: CFTimeInterval = 0
  var benchmarkIntervals: [Double] = [], benchmarkCoverage: [Double] = [], benchmarkNominal: Double = 0
  func scheduleBenchmark(fullLibrary: Bool) {
    guard Self.benchmarking, fullLibrary, !benchmarkScheduled else { return }
    benchmarkScheduled = true
    // Long prefills must not be cut short by auto-lock.
    UIApplication.shared.isIdleTimerDisabled = true
    var observer: NSObjectProtocol?
    var started = false
    let start = { [weak self] in
      guard let self, !started else { return }
      started = true
      if let observer { NotificationCenter.default.removeObserver(observer) }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.runBenchmark() }
    }
    observer = NotificationCenter.default.addObserver(forName: Notification.Name("ThumbnailPrefillDone"),
      object: nil, queue: .main) { _ in start() }
    let prefill = !ProcessInfo.processInfo.arguments.contains("-no-thumbnail-table")
    // Without tables there is no prefill; with them, cap the wait.
    DispatchQueue.main.asyncAfter(deadline: .now() + (prefill ? 300 : 2)) { start() }
  }
  func runBenchmark() {
    print("[bench] start, tables \(ProcessInfo.processInfo.arguments.contains("-no-thumbnail-table") ? "off" : "on")")
    density(columns: columnStops.last ?? 31, at: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self else { return }
      if self.stage != nil { self.completeStage() }
      self.place(self.clampedOffset(.greatestFiniteMagnitude))
      self.benchmarkPass = 0
      self.startBenchmarkPass()
    }
  }
  func startBenchmarkPass() {
    benchmarkIntervals = []; benchmarkCoverage = []; benchmarkLast = 0; benchmarkStart = 0
    let link = CADisplayLink(target: self, selector: #selector(benchmarkFrame(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    benchmarkLink = link
  }
  @objc func benchmarkFrame(_ link: CADisplayLink) {
    if benchmarkStart == 0 { benchmarkStart = link.timestamp; benchmarkLast = link.timestamp; return }
    benchmarkNominal = link.targetTimestamp - link.timestamp
    benchmarkIntervals.append(link.timestamp - benchmarkLast)
    let dt = link.timestamp - benchmarkLast
    benchmarkLast = link.timestamp
    // Passes: older (up), back to newer (down), older again.
    let direction: CGFloat = benchmarkPass == 1 ? 1 : -1
    grid.contentOffset.y = clampedOffset(grid.contentOffset.y + direction * 3000 * CGFloat(dt))
    benchmarkCoverage.append(denseCanvas.coverage(in: grid.bounds))
    guard link.timestamp - benchmarkStart >= 4 else { return }
    link.invalidate(); benchmarkLink = nil
    let sorted = benchmarkIntervals.sorted()
    let nominal = max(0.004, sorted[sorted.count / 2])
    let hitches = benchmarkIntervals.filter { $0 > nominal * 1.5 }
    let hitchTime = hitches.reduce(0) { $0 + ($1 - nominal) }
    let blank = 1 - benchmarkCoverage.reduce(0, +) / Double(max(1, benchmarkCoverage.count))
    print(String(format: "[bench] pass %d %@: frames %d, frame %.1f ms, hitches %d, hitch time %.0f ms/s, worst %.1f ms, blank avg %.1f%% max %.1f%%, thermal %@",
      benchmarkPass + 1, benchmarkPass == 1 ? "down (revisit)" : "up", benchmarkIntervals.count, nominal * 1000,
      hitches.count, hitchTime * 1000 / 4, (sorted.last ?? 0) * 1000, blank * 100,
      (1 - (benchmarkCoverage.min() ?? 1)) * 100,
      ["nominal", "fair", "serious", "critical"][min(3, ProcessInfo.processInfo.thermalState.rawValue)]))
    benchmarkPass += 1
    if benchmarkPass < 3 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.startBenchmarkPass() }
    } else { print("[bench] done") }
  }

  // MARK: Dense canvas

  let denseCanvas = CalendarDenseCanvas()
  var denseCanvasKey = ""
  /// Keeps the dense canvas aligned with the adopted geometry and viewport.
  func syncDenseCanvas() {
    guard isViewLoaded else { return }
    let g = layout.geometry
    guard g.dense, grid.bounds.width > 0 else {
      if !denseCanvas.isHidden { denseCanvas.isHidden = true; denseCanvas.stop(); denseCanvasKey = "" }
      grid.accessibilityElements = nil; denseCanvas.accessibilityElements = nil; denseAccessibility = [:]
      return
    }
    let key = "\(g.columns)|\(g.leadingSlots)|\(g.tiles.count)|\(g.height)|\(grid.bounds.width)|\(assets.count)"
    if denseCanvas.superview !== grid { grid.insertSubview(denseCanvas, at: 0) }
    if key != denseCanvasKey {
      denseCanvasKey = key
      denseCanvas.reset(g, columns: g.columns, fill: !originalAspect)
      // Value snapshots: the lookup runs on the canvas's render queue.
      let snapshot = assets, stored = storedImage
      let pixels = CalendarGridGeometry.side(width: grid.bounds.width, columns: g.columns) * traitCollection.displayScale
      denseCanvas.tableLookup = { index in
        snapshot.indices.contains(index) ? stored(snapshot[index], pixels)?.cgImage : nil
      }
      denseCanvas.frame = CGRect(x: 0, y: 0, width: grid.bounds.width, height: g.height)
    }
    denseCanvas.isHidden = false
    denseCanvas.update(visible: grid.bounds, scale: traitCollection.displayScale)
    updatePreviewMask()
    updateDenseAccessibility()
  }
  private var denseAccessibility: [String: CalendarPhotoAccessibilityElement] = [:]
  private func updateDenseAccessibility() {
    guard UIAccessibility.isVoiceOverRunning else {
      grid.accessibilityElements = nil; denseCanvas.accessibilityElements = nil; denseAccessibility = [:]; return
    }
    var retained: [String: CalendarPhotoAccessibilityElement] = [:]
    denseCanvas.accessibilityElements = visibleItems().map { index in
      let tile = layout.geometry.tiles[index], asset = assets[tile.asset]
      let element = denseAccessibility[asset.id] ?? CalendarPhotoAccessibilityElement(accessibilityContainer: denseCanvas)
      retained[asset.id] = element
      element.accessibilityLabel = asset.date?.formatted(date: .abbreviated, time: .shortened)
      element.accessibilityTraits = .button
      element.accessibilityFrameInContainerSpace = tile.frame
      element.accessibilityCustomActions = photoActions(asset)
      element.activate = { [weak self] in
        guard let self, let current = self.assets.firstIndex(where: { $0.id == asset.id }) else { return false }
        if self.selecting { self.toggleAsset(current) }
        else { self.onPreview(self.assets[current], self.grid.convert(self.layout.frame(current), to: nil)) }
        return true
      }
      return element
    }
    denseAccessibility = retained
    grid.accessibilityElements = denseCanvas.accessibilityElements
  }
  func configureDenseCanvas() {
    denseCanvas.prepare = { [weak self] indices in
      guard let self, indices.count > 1 else { return }
      self.prefetchAssets(indices.compactMap { self.assets.indices.contains($0) ? self.assets[$0].id : nil })
    }
    denseCanvas.cachedImage = { [weak self] index in
      guard let self, self.assets.indices.contains(index) else { return nil }
      let asset = self.assets[index], id = asset.id as NSString
      if let image = self.adoptingTiles[asset.id]?.image ?? self.transitionSmallImages.object(forKey: id)
        ?? self.transitionImages.object(forKey: id) { return image }
      // Decoded table hit: no request, no decode, no copy.
      let pixels = CalendarGridGeometry.side(width: self.width, columns: self.denseCanvas.columns)
        * self.traitCollection.displayScale
      return self.storedImage(asset, pixels)
    }
    denseCanvas.request = { [weak self] index, pixels, done in
      guard let self, self.assets.indices.contains(index) else { return nil }
      let asset = self.assets[index]
      return self.requestImage(asset, pixels) { [weak self] image, _ in
        guard let image else { return }
        self?.rememberImage(image, for: asset.id)
        done(image)
      }
    }
    denseCanvas.didPublish = { [weak self] in self?.finishDenseAdoption() }
  }
  func finishDenseAdoption() {
    guard let cover = adoptionCover,layout.geometry.dense,denseCanvas.isReady(in: grid.bounds) else { return }
    cover.stop(); cover.removeFromSuperview(); adoptionCover = nil
    applyPendingAssets()
  }
  /// Content-coordinate hit testing that works without per-photo cells.
  func item(at point: CGPoint) -> Int? {
    let g = layout.geometry
    let probe = CGRect(x: point.x - 0.5, y: point.y - 0.5, width: 1, height: 1)
    return g.visible(in: probe).first { g.tiles[$0].frame.contains(point) }
  }
  func visibleItems(in rect: CGRect? = nil) -> [Int] {
    let g = layout.geometry, area = rect ?? grid.bounds
    return g.visible(in: area).filter { g.tiles[$0].frame.intersects(area) }
  }
  @objc func denseTap(_ gesture: UITapGestureRecognizer) {
    guard layout.geometry.dense, let item = item(at: gesture.location(in: grid)) else { return }
    select(item: item)
  }
  func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt path: IndexPath) {
    guard let cell = cell as? CalendarGridCell, cell.cancel == nil else { return }
    cell.resumeThumbnail?()
  }
  func collectionView(
    _ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
    forItemAt path: IndexPath
  ) {
    // A reload may reuse a cell before delivering its previous end-display
    // callback. Do not cancel the new request owned by that visible reuse.
    guard collectionView.indexPath(for: cell) == nil else { return }
    (cell as? CalendarGridCell)?.cancel?()
    (cell as? CalendarGridCell)?.cancel = nil
    (cell as? CalendarGridCell)?.stopCover()
  }
  func collectionView(
    _ view: UICollectionView, viewForSupplementaryElementOfKind kind: String, at path: IndexPath
  ) -> UICollectionReusableView {
    let h =
      view.dequeueReusableSupplementaryView(
        ofKind: kind, withReuseIdentifier: "calendar.heading", for: path) as! CalendarGlassHeading
    if layout.geometry.headings.indices.contains(path.item) {
      h.title(layout.geometry.headings[path.item].0, dense: level == .all, yearly: columns >= 20)
      h.setNeedsLayout()
    }
    return h
  }
  func collectionView(_ view: UICollectionView, didSelectItemAt path: IndexPath) {
    select(item: path.item)
  }
  func select(item: Int) {
    let path = IndexPath(item: item, section: 0)
    guard layout.geometry.tiles.indices.contains(path.item) else { return }
    let tile = layout.geometry.tiles[path.item]
    if level != .all {
      changeLevel(
        level == .years ? .months : .all,
        asset: (grid.cellForItem(at: path) as? CalendarGridCell)?.coverAsset ?? tile.asset,
        from: path)
      return
    }
    if columns > 5 {
      let i = columnStops.firstIndex(of: columns) ?? 3
      density(columns: columnStops[max(2, i - 1)], at: path.item)
      return
    }
    if selecting { toggleAsset(tile.asset); return }
    onPreview(assets[tile.asset], grid.convert(layout.frame(path.item), to: nil))
  }
  func focusedAsset() -> String? {
    if level != .all,let id = periodFocusAssetID { return id }
    guard let index = item(at: CGPoint(x: grid.bounds.midX, y: grid.bounds.midY))
    else { return layout.geometry.tiles.last.map { assets[$0.asset].id } }
    return assets[layout.geometry.tiles[index].asset].id
  }
  func locateAsset(_ asset: Int) {
    guard let tile = layout.geometry.tiles.firstIndex(where: { $0.members.contains(asset) }) else {
      return
    }
    grid.contentSize = layout.collectionViewContentSize
    place(clampedOffset(layout.frame(tile).midY - grid.bounds.height * 0.5))
  }
  /// Places the collection after a layout change. A shrinking content size makes
  /// UIKit animate its automatic offset adjustment; a non-animated set stops
  /// that animation, which would otherwise scroll toward the top afterwards.
  func place(_ y: CGFloat) {
    grid.layoutIfNeeded()
    grid.setContentOffset(CGPoint(x: 0, y: clampedOffset(y)), animated: false)
    grid.layoutIfNeeded()
  }
  func clampedOffset(_ y: CGFloat) -> CGFloat {
    min(
      max(-grid.contentInset.top, y),
      max(
        -grid.contentInset.top,
        grid.contentSize.height - grid.bounds.height + grid.contentInset.bottom))
  }
  func installTabReselection() {
    guard let tabs = tabBarController else { return }
    if let installed = tabReselection, tabs.delegate === installed { return }
    let forwarding = CalendarTabReselection()
    forwarding.owner = self
    forwarding.tabs = tabs
    forwarding.lastSelected = tabs.selectedViewController
    forwarding.previous = tabs.delegate
    tabReselection = forwarding
    tabs.delegate = forwarding
  }
  func returnToLatest() {
    stopMotion(); stopCoverPlayback()
    let target = clampedOffset(.greatestFiniteMagnitude)
    let destination = CGRect(x:0,y:target,width:grid.bounds.width,height:grid.bounds.height)
    warmZoomViewport(viewport:destination)
    scrollingToLatest = true
    grid.setContentOffset(CGPoint(x:0,y:target),animated:!UIAccessibility.isReduceMotionEnabled)
    if UIAccessibility.isReduceMotionEnabled { scrollViewDidEndScrollingAnimation(grid) }
  }
  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    scrollingToLatest = false
    zoomPixelRequests.forEach { $0() }; zoomPixelRequests = []
    onVisibleChange(); warmAdjacentScenes()
  }
  func startCoverClock() {
    coverTimer?.invalidate()
    coverTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.refreshCoverPlayback()
    }
  }
  func stopCoverPlayback() {
    guard coverCancel != nil || coverPlaybackID != nil || playingCoverCell != nil else { return }
    coverCancel?()
    coverCancel = nil
    coverPlaybackID = nil
    playingCoverCell?.stopCover()
    playingCoverCell = nil
  }
  func refreshCoverPlayback() {
    guard active, level != .all, !changing, !grid.isDragging, !grid.isTracking,
      !grid.isDecelerating,
      !UIAccessibility.isReduceMotionEnabled, !ProcessInfo.processInfo.isLowPowerModeEnabled,
      view.window?.windowScene?.activationState == .foregroundActive
    else {
      stopCoverPlayback()
      return
    }
    guard
      let path = grid.indexPathsForVisibleItems.filter({
        grid.convert(layout.frame($0.item), to: view).intersects(
          view.bounds.insetBy(dx: 0, dy: 100))
      }).min(by: {
        abs(layout.frame($0.item).midY - grid.bounds.midY)
          < abs(layout.frame($1.item).midY - grid.bounds.midY)
      }),
      let cell = grid.cellForItem(at: path) as? CalendarGridCell
    else { return }
    let tile = layout.geometry.tiles[path.item]
    if focusedCoverPeriod != tile.id {
      focusedCoverPeriod = tile.id
      lastCoverChange = CACurrentMediaTime()
    }
    if level == .years, CACurrentMediaTime() - lastCoverChange > 5 {
      let candidates = layout.geometry.coverChoices[tile.id] ?? [tile.asset]
      let previous = coverIndices[tile.id] ?? tile.asset
      if candidates.count > 1 {
        let index = candidates[((candidates.firstIndex(of: previous) ?? -1) + 1) % candidates.count]
        let asset = assets[index]
        lastCoverChange = CACurrentMediaTime()
        coverIndices[tile.id] = index
        stopCoverPlayback()
        cell.cancel?()
        cell.assetID = asset.id
        cell.coverAsset = index
        cell.cancel = requestImage(asset, cell.bounds.width * traitCollection.displayScale) {
          [weak self, weak cell] image, cloud in
          guard let cell, cell.assetID == asset.id else { return }
          if let image {
            self?.rememberImage(image, for: asset.id)
            UIView.transition(
              with: cell.image, duration: 0.6,
              options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
              cell.thumbnail(image, cloud: cloud)
            }
          }
        }
      }
    }
    guard let index = cell.coverAsset, assets[index].videoDuration != nil else {
      if coverPlaybackID != nil { stopCoverPlayback() }
      return
    }
    let asset = assets[index]
    guard coverPlaybackID != asset.id else { return }
    stopCoverPlayback()
    coverPlaybackID = asset.id
    coverCancel = requestVideo(asset) { [weak self, weak cell] item in
      guard let self, self.active, self.coverPlaybackID == asset.id, cell?.assetID == asset.id,
        !self.grid.isDragging, !self.grid.isDecelerating, let item
      else { return }
      self.playingCoverCell = cell
      cell?.playCover(item)
    }
  }
  func scrollToLatest() {
    grid.layoutIfNeeded()
    grid.setContentOffset(
      CGPoint(x: 0, y: clampedOffset(.greatestFiniteMagnitude)), animated: false)
    updateChrome()
  }
  @objc func levelChosen() {
    let i =
      focusedAsset().flatMap { id in assets.firstIndex(where: { $0.id == id }) }
      ?? max(0, assets.count - 1)
    changeLevel(CalendarGridLevel(rawValue: dock.selectedSegmentIndex) ?? .all, asset: i, from: nil)
  }
  func changeLevel(_ next: CalendarGridLevel, asset: Int, from: IndexPath?) {
    guard !assets.isEmpty, level != next else { return }
    stopMotion()
    stopCoverPlayback()
    // Resolve real photo identities in the current viewport before rebuilding.
    struct Pose {
      let id: String
      let asset: Int
      let frame: CGRect
      let image: UIImage
      let decorations: UIImage?
    }
    let source = grid.indexPathsForVisibleItems.compactMap { path -> Pose? in
      guard let cell = grid.cellForItem(at: path) as? CalendarGridCell,
        let image = cell.image.image, let index = cell.coverAsset
      else { return nil }
      let frame = grid.convert(layout.frame(path.item), to: view)
      guard frame.intersects(view.bounds) else { return nil }
      return Pose(id: cell.assetID, asset: index, frame: frame, image: image,
        decorations: cell.decorationSnapshot())
    }
    let sourceByID = Dictionary(source.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let old = grid.snapshotView(afterScreenUpdates: false)
    // Toward All the outgoing level expands past the viewer; toward Years it
    // recedes. The incoming level settles from the opposite side (Photos).
    let deeper = next.rawValue > level.rawValue
    periodFocusAssetID = assets[asset].id
    level = next
    if next == .all { columns = 5; leadingSlots = 0 }
    dock.selectedSegmentIndex = next.rawValue
    layout.level = next
    layout.geometry = geometry()
    layout.invalidateLayout()
    grid.contentSize = layout.collectionViewContentSize
    // The navigation bar and subtitle fade with the motion instead of popping.
    let bar = navigationController?.navigationBar
    let hidesBar = next != .all && !selecting
    let barWasHidden = navigationController?.isNavigationBarHidden ?? true
    if !hidesBar, barWasHidden {
      navigationController?.setNavigationBarHidden(false, animated: false)
      bar?.alpha = 0; subtitleLabel.alpha = 0
    }
    grid.reloadData()
    view.layoutIfNeeded()
    grid.layoutIfNeeded()
    locateAsset(asset)
    var pairs: [(Pose, IndexPath)] = []
    for path in grid.indexPathsForVisibleItems {
      let tile = layout.geometry.tiles[path.item]
      let index = coverIndices[tile.id] ?? tile.asset
      if let pose = sourceByID[assets[index].id] { pairs.append((pose, path)) }
    }
    // Different posters inside one period can still explain year/month hierarchy.
    // Crossfade their actual pixels inside one moving cover, never pretend IDs match.
    if pairs.isEmpty,
      let path = grid.indexPathsForVisibleItems.first(where: {
        layout.geometry.tiles[$0.item].members.contains(asset)
      }), let pose = source.min(by: { abs($0.asset - asset) < abs($1.asset - asset) })
    {
      pairs.append((pose, path))
    }
    pairs = Array(pairs.prefix(12))
    changing = true
    warmZoomViewport()
    motionSourceIDs = Set(pairs.map { $0.0.id })
    motionDestinationIDs = Set(
      pairs.map { pair in
        let tile = layout.geometry.tiles[pair.1.item]
        return assets[coverIndices[tile.id] ?? tile.asset].id
      })
    // Mask matched photos out of the bounded source snapshot to avoid duplicate ghosts.
    let matchedOld = old
    let overlay = UIView(frame: view.bounds)
    overlay.isUserInteractionEnabled = false
    if let matchedOld {
      matchedOld.frame = grid.frame
      overlay.addSubview(matchedOld)
      let mask = CAShapeLayer()
      let path = UIBezierPath(rect: matchedOld.bounds)
      for (pose, _) in pairs {
        path.append(
          UIBezierPath(rect: pose.frame.offsetBy(dx: -grid.frame.minX, dy: -grid.frame.minY)))
      }
      mask.path = path.cgPath
      mask.fillRule = .evenOdd
      matchedOld.layer.mask = mask
    }
    view.insertSubview(overlay, aboveSubview: grid)
    transitionOverlay = overlay
    var flights: [(UIView, CGRect, CGFloat)] = []
    var flightPixels: [(UIImageView,String,CGFloat)] = []
    var decorationFades: [(UIView, CGFloat)] = []
    var flightDecorations: [UIView] = []
    for (pose, path) in pairs {
      let target = grid.cellForItem(at: path) as? CalendarGridCell
      let frame = grid.convert(layout.frame(path.item), to: view)
      let flight = UIView(frame: pose.frame)
      flight.clipsToBounds = true
      flight.layer.cornerRadius = next == .all ? 12 : 0
      let image = UIImageView(image: pose.image)
      image.contentMode = .scaleAspectFill
      image.frame = flight.bounds
      image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      flight.addSubview(image)
      // The flight carries both cells' decorations (labels, top shadow, badges)
      // at their native sizes: the source's fade out while the destination's
      // fade in, so the final frame already matches the revealed cell.
      if let decorations = pose.decorations {
        let outgoing = UIImageView(image: decorations)
        outgoing.contentMode = .topLeft
        outgoing.frame = CGRect(origin: .zero, size: decorations.size)
        outgoing.tag = 802
        decorationFades.append((outgoing, 0))
        flightDecorations.append(outgoing)
      }
      if let target, let decorations = target.decorationSnapshot() {
        let incoming = UIImageView(image: decorations)
        incoming.contentMode = .topLeft
        incoming.frame = CGRect(origin: .zero, size: decorations.size)
        incoming.alpha = 0
        decorationFades.append((incoming, 1))
        flightDecorations.append(incoming)
      }
      if let target, target.assetID == pose.id {
        flightPixels.append((image,pose.id,min(1024,frame.width*traitCollection.displayScale)))
      }
      if let nextImage = target?.image.image, target?.assetID != pose.id {
        let replacement = UIImageView(image: nextImage)
        replacement.contentMode = .scaleAspectFill
        replacement.frame = flight.bounds
        replacement.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        replacement.alpha = 0
        replacement.tag = 803
        flight.addSubview(replacement)
        if let target { flightPixels.append((replacement,target.assetID,min(1024,frame.width*traitCollection.displayScale))) }
      }
      target?.isHidden = true
      // Decorations sit above any image replacement; they never stretch.
      for decoration in flightDecorations { flight.addSubview(decoration) }
      flightDecorations = []
      overlay.addSubview(flight)
      flights.append((flight, frame, next == .all ? 0 : 12))
    }
    // Glass ignores an ancestor's fading alpha and would appear in one frame.
    // Period headings materialize their own effect and text with the motion.
    let headings = grid.visibleSupplementaryViews(ofKind: CalendarGridLayout.headingKind)
      .compactMap { $0 as? CalendarGlassHeading }
    if !UIAccessibility.isReduceMotionEnabled {
      UIView.performWithoutAnimation { headings.forEach { $0.reveal(false) } }
    }
    grid.alpha = 0
    let still = UIAccessibility.isReduceMotionEnabled
    if !still { grid.transform = CGAffineTransform(scaleX: deeper ? 0.94 : 1.06, y: deeper ? 0.94 : 1.06) }
    // Unmatched scenes fade in place. Only real matched covers travel.
    let cleanup: () -> Void = { [weak self] in
      guard let self else { return }
      overlay.removeFromSuperview()
      self.motionSourceIDs = []
      self.motionDestinationIDs = []
      if hidesBar, !barWasHidden || self.navigationController?.isNavigationBarHidden == false {
        self.navigationController?.setNavigationBarHidden(true, animated: false)
      }
      bar?.alpha = 1; self.subtitleLabel.alpha = 1
      for cell in self.grid.visibleCells { cell.isHidden = false }
      for case let heading as CalendarGlassHeading in
        self.grid.visibleSupplementaryViews(ofKind: CalendarGridLayout.headingKind) { heading.reveal(true) }
      self.transitionOverlay = nil
      self.grid.alpha = 1
      self.grid.transform = .identity
      self.changing = false
      self.spring = nil
      self.motionPreparation?.cancel(); self.motionPreparation = nil
      self.zoomPixelRequests.forEach { $0() }; self.zoomPixelRequests = []
      self.updateChrome()
      self.refreshCoverPlayback()
      self.adjacentWarmKey = nil; self.warmAdjacentScenes()
      self.applyPendingAssets()
    }
    if UIAccessibility.isReduceMotionEnabled {
      cleanup()
      return
    }
    // Photos starts at full speed and decays like a critically damped spring
    // (omega about 20, roughly 90% in 0.3 s) in recordings of all four switches.
    let animation = UIViewPropertyAnimator(duration: 0,
      timingParameters: UISpringTimingParameters(mass: 1, stiffness: 400, damping: 40,
        initialVelocity: .zero))
    animation.addAnimations {
      matchedOld?.alpha = 0
      matchedOld?.transform = CGAffineTransform(scaleX: deeper ? 1.12 : 0.9, y: deeper ? 1.12 : 0.9)
      self.grid.alpha = 1
      self.grid.transform = .identity
      for (flight, frame, radius) in flights {
        flight.frame = frame
        flight.layer.cornerRadius = radius
        // A different poster in the same period crossfades its actual pixels.
        flight.viewWithTag(803)?.alpha = 1
      }
      for (view, alpha) in decorationFades { view.alpha = alpha }
      headings.forEach { $0.reveal(true) }
      bar?.alpha = hidesBar ? 0 : 1
      self.subtitleLabel.alpha = hidesBar ? 0 : 1
    }
    animation.addCompletion { _ in cleanup() }
    spring = animation
    // Start immediately, as Photos does; flights sharpen in place as the
    // destination tier arrives (same photo, so only detail changes).
    func sharpen() {
      guard self.spring === animation else { return }
      for (view,id,_) in flightPixels {
        if let sharp = self.transitionImages.object(forKey:id as NSString) {
          view.image = calendarPreferredImage(view.image, sharp)
        }
      }
    }
    sharpen()
    animation.startAnimation()
    for delay in [0.06, 0.15] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { sharpen() }
    }
    updateChrome()
  }

  func stopMotion() {
    adoptionCover?.stop(); adoptionCover?.removeFromSuperview(); adoptionCover = nil
    adoptingTiles = [:]
    motionPreparation?.cancel(); motionPreparation = nil
    // Cancellation never runs a transition's commit cleanup. Completing through
    // self.spring lets the completion release its own animator during UIKit's
    // _runCompletions call, and can adopt obsolete geometry after replacement.
    let cancelled = spring
    spring = nil
    cancelled?.stopAnimation(true)
    withExtendedLifetime(cancelled) {}
    transitionOverlay?.removeFromSuperview(); transitionOverlay = nil
    motionSourceIDs = []; motionDestinationIDs = []
    grid.visibleCells.forEach { $0.isHidden = false }
    changing = false
    zoomPixelRequests.forEach { $0() }; zoomPixelRequests = []
    if let stage {
      // A committed release finishes at its density instead of snapping back.
      if pinchTrack.target != nil { completeStage() } else {
        stage.stop(); stage.removeFromSuperview(); self.stage = nil
        view.setNeedsLayout()
      }
    }
    grid.alpha = 1; grid.transform = .identity; subtitleLabel.alpha = 1
    if cancelled != nil, let navigation = navigationController {
      // An interrupted level change leaves the bar at its resting visibility.
      navigation.navigationBar.alpha = 1
      navigation.setNavigationBarHidden(level != .all && !selecting, animated: false)
    }
    grid.accessibilityElementsHidden = false
    grid.panGestureRecognizer.isEnabled = true
    announceDensity()
    if pendingAssets != nil { applyPendingAssets() }
  }
  /// Like Photos, zoom actions keep the menu open and can be repeated. They step
  /// from the density being settled toward, so quick repeats chain smoothly.
  /// Density state is not baked into the items: rebuilding a presented menu
  /// would dismiss it.
  func stepDensity(by delta: Int) {
    guard level == .all else { return }
    let current = stage.flatMap { _ in pinchTrack.target } ?? columnStops.firstIndex(of: columns) ?? 1
    let next = min(columnStops.count - 1, max(0, current + delta))
    guard next != current else { return }
    density(columns: columnStops[next], at: nil)
  }
  func displayMenu() -> UIMenu {
    let zoomIn = UIAction(
      title: NSLocalizedString("calendar_zoom_in", comment: ""),
      image: UIImage(systemName: "plus.magnifyingglass"), attributes: .keepsMenuPresented
    ) { [weak self] _ in self?.stepDensity(by: -1) }
    let zoomOut = UIAction(
      title: NSLocalizedString("calendar_zoom_out", comment: ""),
      image: UIImage(systemName: "minus.magnifyingglass"), attributes: .keepsMenuPresented
    ) { [weak self] _ in self?.stepDensity(by: 1) }
    return UIMenu(
      children: (menu?() ?? []) + [
        UIMenu(
          title: NSLocalizedString("calendar_display_options", comment: ""),
          children: [zoomIn, zoomOut])
      ])
  }
  /// Render the explicit chronological viewport, without asking a hidden scroll
  /// view to flush pending reloads or adopt a different content offset.
  func sceneImage(viewport: CGRect? = nil, geometry: CalendarGridGeometry? = nil, retaining previous: UIImage? = nil, excluding painted: Set<String> = []) -> UIImage {
    let viewport = viewport ?? grid.bounds
    let geometry = geometry ?? layout.geometry
    let format = UIGraphicsImageRendererFormat()
    format.scale = min(2, traitCollection.displayScale)
    return UIGraphicsImageRenderer(size: viewport.size, format: format).image { context in
      UIColor.systemBackground.setFill()
      context.fill(CGRect(origin: .zero,size: viewport.size))
      previous?.draw(in:CGRect(origin:.zero,size:viewport.size))
      for i in geometry.visible(in: viewport) {
        let tile = geometry.tiles[i]
        let id = assets[coverIndices[tile.id] ?? tile.asset].id
        if painted.contains(id) { continue }
        let frame = tile.frame.offsetBy(dx: -viewport.minX,dy: -viewport.minY)
        guard frame.intersects(CGRect(origin: .zero,size: viewport.size)) else { continue }
        let cell = grid.cellForItem(at: IndexPath(item: i,section: 0))
        let normal = (cell as? CalendarGridCell)?.assetID == id ? cell as? CalendarGridCell : nil
        let image = transitionImages.object(forKey:id as NSString) ?? normal?.image.image
          ?? transitionSmallImages.object(forKey:id as NSString)
        context.cgContext.saveGState()
        UIBezierPath(roundedRect:frame,cornerRadius:geometry.level == .all ? 0 : 12).addClip()
        DuckRole.mediaPlaceholderUIColor.setFill(); context.fill(frame)
        if let image {
          // UIImageView layer contents can still be empty in a hidden reloaded
          // collection. Draw the resolved UIImage, never a pending display layer.
          let fit = originalAspect && geometry.level == .all
          let sx = frame.width/max(1,image.size.width), sy = frame.height/max(1,image.size.height)
          let factor = fit ? min(sx,sy) : max(sx,sy)
          context.cgContext.setAlpha(normal?.image.alpha ?? 1)
          image.draw(in:CGRect(x:frame.midX-image.size.width*factor/2,
            y:frame.midY-image.size.height*factor/2,width:image.size.width*factor,height:image.size.height*factor))
          context.cgContext.setAlpha(1)
        }
        if let normal {
          normal.layoutIfNeeded()
          for label in [normal.label,normal.duration] where !label.isHidden {
            let rect = label.frame.offsetBy(dx:frame.minX,dy:frame.minY)
            if let background = label.backgroundColor {
              background.setFill(); UIBezierPath(roundedRect:rect,cornerRadius:label.layer.cornerRadius).fill()
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = label.textAlignment
            let text = label.attributedText ?? NSAttributedString(string:label.text ?? "",attributes:[
              .font:label.font as Any,.foregroundColor:label.textColor as Any,.paragraphStyle:paragraph])
            text.draw(in:CGRect(x:rect.minX,y:rect.midY-label.font.lineHeight/2,width:rect.width,height:label.font.lineHeight))
          }
          for badge in [normal.check,normal.liveMark,normal.stateMark] where !badge.isHidden {
            badge.image?.draw(in:badge.frame.offsetBy(dx:frame.minX,dy:frame.minY))
          }
        }
        context.cgContext.restoreGState()
      }
    }
  }
  func warmAdjacentScenes() {
    guard !changing,!scrollingToLatest,!assets.isEmpty,grid.bounds.width > 0 else { return }
    let point = CGPoint(x:grid.bounds.midX,y:grid.bounds.midY)
    let focus = item(at: point) ?? visibleItems().last
    guard let focus,layout.geometry.tiles.indices.contains(focus) else { return }
    let asset = layout.geometry.tiles[focus].asset
    let key = "\(level.rawValue)|\(columns)|\(asset/30)"
    guard adjacentWarmKey != key else { return }; adjacentWarmKey = key
    adjacentRequests.forEach { $0() }; adjacentRequests = []
    let index = columnStops.firstIndex(of:columns) ?? 1
    // Neighbouring densities, plus the dense overviews whose small pixel tier
    // is cheap and which a fast pinch reaches before requests could finish.
    let neighbours = Set([max(0,index-1),min(columnStops.count-1,index+1),columnStops.count-2,columnStops.count-1])
    let targets: [(CalendarGridLevel,Int)] = level == .all
      ? neighbours.sorted().filter { $0 != index }.map { (.all,columnStops[$0]) } + [(.months,columns),(.years,columns)]
      : (level == .months ? [(.years,columns),(.all,5)] : [(.months,columns)])
    for (level,count) in targets {
      let geometryKey = geometryKey(level,width:width,columns:count,aspect:originalAspect)
      let g = geometryCache[geometryKey] ?? CalendarGridGeometry(assets:assets,level:level,width:width,columns:count,originalAspect:originalAspect)
      geometryCache[geometryKey] = g
      guard let focal = g.tiles.firstIndex(where:{ $0.members.contains(asset) }) else { continue }
      let y = max(0,g.tiles[focal].frame.midY-grid.bounds.height/2)
      let viewport = CGRect(x:0,y:y,width:width,height:grid.bounds.height)
      for i in g.visible(in:viewport).prefix(2400) where g.tiles[i].frame.intersects(viewport) {
        let tile = g.tiles[i],photo = assets[coverIndices[tile.id] ?? tile.asset]
        adjacentRequests.append((prefetchImage ?? requestImage)(photo,tile.frame.width*traitCollection.displayScale) { [weak self] image,_ in
          if let image { self?.rememberImage(image,for:photo.id) }
        })
      }
    }
  }
  func warmZoomViewport(viewport: CGRect? = nil, geometry: CalendarGridGeometry? = nil) {
    // Earlier brackets are still visible while their pixels arrive. Keep their
    // requests alive through the gesture, with a hard bound for repeated reversals.
    if zoomPixelRequests.count > 2048 {
      zoomPixelRequests.prefix(zoomPixelRequests.count-2048).forEach { $0() }
      zoomPixelRequests.removeFirst(zoomPixelRequests.count-2048)
    }
    let viewport = viewport ?? grid.bounds, geometry = geometry ?? layout.geometry
    // Only the predicted destination window is requested, at that cell's pixel tier.
    for i in geometry.visible(in: viewport) where geometry.tiles[i].frame.intersects(viewport) {
      let tile = geometry.tiles[i], asset = assets[coverIndices[tile.id] ?? tile.asset]
      let request = geometry.columns == 1 ? requestUncroppedImage ?? requestImage : requestImage
      let cancel = request(asset,max(40,tile.frame.width*traitCollection.displayScale)) { [weak self] image,_ in
        if let image { self?.rememberImage(image,for: asset.id) }
      }
      zoomPixelRequests.append(cancel)
    }
  }
  // MARK: Live All-grid pinch

  /// Gesture state for the live stage. Photos ignores roughly the first 20-30
  /// points of finger travel, then tracks finger distance linearly from the
  /// distance at which the pinch became visible.
  struct PinchTrack {
    var startDistance: CGFloat = 0
    var recognizedDistance: CGFloat?
    var startPitch: CGFloat = 1
    var startIndex = 1
    var intent: CGFloat = 0
    var asset = 0
    var fraction = CGPoint(x: 0.5, y: 0.5)
    var samples: [(CFTimeInterval, CGFloat)] = []
    /// Direction in density-stop order and the extreme of the current leg.
    var direction = 0
    var extremePitch: CGFloat = 1
    var startOffset: CGFloat = 0
    var startFocus = CGPoint.zero
    var boundaryDistance: CGFloat = 0
    /// Focal distance to the content's top edge, in pitch units.
    var topDistance: CGFloat = 0
    var headerColumns = 3
    var faceLeadingSlots: [Int: Int] = [:]
    /// Stop index chosen at the last release, while its settle is running.
    var target: Int?
    var finalOffset: CGFloat = 0
  }
  /// Fitted to Photos: about 13% of the touch-down finger distance, at least 20 pt.
  func pinchDeadZone(_ distance: CGFloat) -> CGFloat { max(20, distance * 0.13) }
  /// A new adjacent stop needs deliberate travel; an established pair reverses
  /// after a small movement from its last extreme, regardless of absolute size.
  static let previewHysteresis: CGFloat = 0.12
  static let reversalTravel: CGFloat = 0.015
  func stopPitch(_ columns: Int) -> CGFloat {
    CalendarGridGeometry.pitch(width: width, columns: columns)
  }
  /// Continuous position in stop-index space, interpolated in log size.
  func stopPosition(_ pitch: CGFloat) -> CGFloat {
    let q = columnStops.map(stopPitch)
    guard q.count > 1 else { return 0 }
    if pitch >= q[0] { return -log(pitch / q[0]) / log(q[0] / q[1]) }
    for i in 0..<(q.count - 1) where pitch >= q[i + 1] {
      return CGFloat(i) + log(q[i] / pitch) / log(q[i] / q[i + 1])
    }
    let n = q.count - 1
    return CGFloat(n) + log(q[n] / pitch) / log(q[n - 1] / q[n])
  }
  /// Beyond the outermost stops the size resists instead of tracking freely.
  func rubberPitch(_ raw: CGFloat) -> CGFloat {
    let high = stopPitch(columnStops[0]), low = stopPitch(columnStops[columnStops.count - 1])
    func band(_ excess: CGFloat, _ limit: CGFloat) -> CGFloat { limit * (1 - exp(-excess / limit)) }
    // The terminal year overview barely yields, as in Photos; a deep band there
    // exposed canvas around the mosaic.
    if raw > high { return high * exp(band(log(raw / high), 0.2)) }
    if raw < low { return low * exp(-band(log(low / raw), 0.05)) }
    return raw
  }
  func allGeometry(_ count: Int, leading: Int = 0) -> CalendarGridGeometry {
    let key = geometryKey(.all, width: width, columns: count, aspect: originalAspect, leading: leading)
    if let cached = geometryCache[key] { return cached }
    let g = CalendarGridGeometry(
      assets: assets, level: .all, width: width, columns: count, originalAspect: originalAspect,
      leadingSlots: leading)
    if geometryCache.count > 9 { geometryCache = geometryCache.filter { !$0.key.hasPrefix("2|") } }
    geometryCache[key] = g
    return g
  }
  /// The focal photo's point in a density, at the same in-tile fraction as in
  /// every other face, which keeps all lattices aligned.
  func stageFocus(_ g: CalendarGridGeometry, asset: Int, fraction: CGPoint) -> CGPoint {
    guard let tile = g.tiles.first(where: { $0.members.contains(asset) }) ?? g.tiles.last else {
      return .zero
    }
    return CGPoint(
      x: tile.frame.minX + tile.frame.width * fraction.x,
      y: tile.frame.minY + tile.frame.height * fraction.y)
  }
  @discardableResult func ensureFace(_ count: Int) -> CalendarZoomStage.Face? {
    guard let stage else { return nil }
    if let face = stage.faces[count] { return face }
    let leading: Int
    if let existing = pinchTrack.faceLeadingSlots[count] { leading = existing } else {
      let side = CalendarGridGeometry.side(width: width, columns: count)
      let column = min(count - 1, max(0,
        Int(round((stage.focus.x - side * pinchTrack.fraction.x) / stopPitch(count)))))
      leading = (column - pinchTrack.asset % count + count) % count
      pinchTrack.faceLeadingSlots[count] = leading
    }
    let g = allGeometry(count, leading: leading)
    let focus = stageFocus(g, asset: pinchTrack.asset, fraction: pinchTrack.fraction)
    let scale = stage.pitch / stopPitch(count)
    let area = CGRect(x: focus.x - stage.focus.x / scale - stage.bounds.width / scale,
      y: focus.y - stage.focus.y / scale, width: stage.bounds.width * 3 / scale,
      height: stage.bounds.height / scale)
    prefetchAssets(g.visible(in: area).prefix(5000).map { assets[g.tiles[$0].asset].id })
    return stage.addFace(
      columns: count, geometry: g, focus: stageFocus(g, asset: pinchTrack.asset, fraction: pinchTrack.fraction),
      pitch: stopPitch(count), opacity: 0)
  }
  func beginStage(point: CGPoint?, item: Int?, distance: CGFloat?) {
    if let stage, stage.settling {
      // Interrupt the settle in place: re-anchor on the new fingers without
      // moving pixels, starting from the density adopted at the last release.
      stage.freeze()
      let screen = point.map { CGPoint(x: $0.x, y: $0.y - grid.contentOffset.y) } ?? stage.focus
      stage.reanchor(screen)
      if let face = stage.faces[stage.shownColumns] {
        let g = face.geometry
        pinchTrack.boundaryDistance = (g.height - face.focus.y) / face.pitch
        pinchTrack.topDistance = face.focus.y / face.pitch
        let probe = CGRect(x: face.focus.x - 1, y: face.focus.y - 1, width: 2, height: 2)
        let nearest = g.visible(in: probe.insetBy(dx: -g.maximumTileHeight, dy: -g.maximumTileHeight))
          .min { a, b in
            hypot(g.tiles[a].frame.midX - face.focus.x, g.tiles[a].frame.midY - face.focus.y)
              < hypot(g.tiles[b].frame.midX - face.focus.x, g.tiles[b].frame.midY - face.focus.y)
          }
        if let i = nearest {
          let f = g.tiles[i].frame
          pinchTrack.asset = g.tiles[i].asset
          pinchTrack.fraction = CGPoint(
            x: min(1, max(0, (face.focus.x - f.minX) / max(1, f.width))),
            y: min(1, max(0, (face.focus.y - f.minY) / max(1, f.height))))
        }
      }
      stage.updateFocalFraction(pinchTrack.fraction)
      pinchTrack.startOffset = pinchTrack.finalOffset
      pinchTrack.startIndex = pinchTrack.target ?? columnStops.firstIndex(of: columns) ?? 1
      pinchTrack.target = nil
      pinchTrack.startPitch = stage.pitch
      pinchTrack.extremePitch = stage.pitch
      pinchTrack.startFocus = stage.focus
      pinchTrack.direction = 0
      pinchTrack.headerColumns = stage.shownColumns
      pinchTrack.startDistance = distance ?? 0
      pinchTrack.recognizedDistance = nil
      pinchTrack.intent = 0
      pinchTrack.samples = []
      return
    }
    let retained = adoptionCover?.presentations(columns) ?? [:]
    stopMotion()
    stopCoverPlayback()
    captureAnchor(item: item, point: point)
    guard let anchor, layout.geometry.tiles.indices.contains(anchor) else { return }
    let tile = layout.geometry.tiles[anchor]
    let count = columns
    pinchTrack = PinchTrack(
      startDistance: distance ?? 0, recognizedDistance: nil, startPitch: stopPitch(count),
      startIndex: columnStops.firstIndex(of: count) ?? 1, intent: 0, asset: tile.asset,
      fraction: anchorFraction, samples: [], extremePitch: stopPitch(count),
      startOffset: grid.contentOffset.y, startFocus: anchorPoint,
      boundaryDistance: (layout.geometry.height - anchorPoint.y - grid.contentOffset.y) / stopPitch(count),
      topDistance: (anchorPoint.y + grid.contentOffset.y) / stopPitch(count),
      headerColumns: count, faceLeadingSlots: [count: leadingSlots])
    let created = CalendarZoomStage(
      frame: grid.frame, columns: count, pitch: stopPitch(count), focus: anchorPoint,
      displayScale: traitCollection.displayScale)
    created.seedTiles = retained
    for cell in grid.visibleCells {
      if let cell = cell as? CalendarGridCell {
        created.seedTiles[cell.assetID] = CalendarTilePresentation(image: cell.image.image,
          cloud: cell.thumbnailCloud, badges: cell.decorations.state)
      }
    }
    if layout.geometry.dense {
      // Dense overviews have no cells; seed from the pixels the canvas draws.
      for index in visibleItems() {
        let asset = assets[layout.geometry.tiles[index].asset]
        if created.seedTiles[asset.id] == nil,
          let image = denseCanvas.displayedImage(layout.geometry.tiles[index].asset)
            ?? denseCanvas.cachedImage(layout.geometry.tiles[index].asset) {
          created.seedTiles[asset.id] = CalendarTilePresentation(image: image, cloud: false, badges: nil)
        }
      }
    }
    created.focalFraction = pinchTrack.fraction
    created.backgroundColor = view.backgroundColor
    created.configureTile = { [weak self] tileLayer, asset, pixels in
      self?.stageTile(tileLayer, asset: asset, pixels: pixels)
    }
    created.configureDecorations = { [weak self] badges, index in
      guard let self, self.assets.indices.contains(index) else { return }
      let asset = self.assets[index]
      badges.duration.text = asset.videoDuration
      badges.liveMark.image = asset.live ? CalendarTileDecorations.Style.symbol("livephoto") : nil
      badges.selection(self.selected.contains(asset.id), enabled: self.selecting)
      badges.backupState(self.photoStates[asset.id], visible: !self.selecting)
    }
    created.pillImage = { [weak self] title, yearly in self?.pillImage(title, yearly: yearly) }
    stage = created
    view.insertSubview(created, aboveSubview: grid)
    // The live face starts exactly where the collection is.
    created.addFace(
      columns: count, geometry: layout.geometry,
      focus: CGPoint(x: anchorPoint.x, y: anchorPoint.y + grid.contentOffset.y), pitch: stopPitch(count),
      opacity: 1)
    created.start()
    grid.panGestureRecognizer.isEnabled = false
    grid.accessibilityElementsHidden = true
    grid.alpha = 0
    changing = true
    grid.accessibilityValue = NSLocalizedString("calendar_zoom_changing", comment: "")
  }
  func updateStage(distance: CGFloat?) {
    guard let stage else { return }
    let d = distance ?? pinchTrack.startDistance
    pinchTrack.intent = d - pinchTrack.startDistance
    let zone = pinchDeadZone(pinchTrack.startDistance)
    if pinchTrack.recognizedDistance == nil, abs(pinchTrack.intent) >= zone {
      // Scale is measured from the dead-zone edge, so it starts continuously
      // even when UIKit recognizes the pinch after a larger movement.
      pinchTrack.recognizedDistance = pinchTrack.startDistance + (pinchTrack.intent < 0 ? -zone : zone)
    }
    let raw = pinchTrack.recognizedDistance.map { pinchTrack.startPitch * d / max(1, $0) } ?? pinchTrack.startPitch
    let pitch = rubberPitch(raw)
    let now = CACurrentMediaTime()
    pinchTrack.samples.append((now, pitch))
    pinchTrack.samples.removeAll { now - $0.0 > 0.08 }
    stage.pitch = pitch
    updateStageDirection(pitch: pitch)
    // Apply the content boundary on every held pose. The focal point stays put
    // in history; shrinking into the newest edge changes the effective pivot
    // to that edge before a gap can open below the content.
    let bottom = stage.bounds.height - gridInsets(showsInterval: true).bottom
    let renderedBottom = pinchTrack.startFocus.y + pinchTrack.boundaryDistance * pitch
    // Content shorter than the viewport stays pinned under the top inset
    // instead of sinking to the bottom edge and jumping back on release.
    let top = gridInsets(showsInterval: true).top
    let renderedTop = pinchTrack.startFocus.y - pinchTrack.topDistance * pitch
    var shift = max(0, bottom - renderedBottom)
    if renderedTop + shift > top { shift = top - renderedTop }
    stage.focus.y = pinchTrack.startFocus.y + shift
    updateStageHeader()
    stage.layoutAll()
  }
  func updateStageDirection(pitch: CGFloat) {
    guard let stage else { return }
    let z = stopPosition(pitch)
    var current = columnStops.firstIndex(of: stage.shownColumns) ?? pinchTrack.startIndex
    var direction = pinchTrack.direction
    if direction == 0 {
      let travel = z - stopPosition(pinchTrack.startPitch)
      guard abs(travel) >= Self.previewHysteresis else { return }
      direction = travel > 0 ? 1 : -1
      current += direction
      pinchTrack.extremePitch = pitch
    } else {
      let travel = log(pinchTrack.extremePitch / pitch) * CGFloat(direction)
      if travel >= 0 { pinchTrack.extremePitch = pitch }
      else if -travel >= Self.reversalTravel {
        direction = -direction
        current += direction
        pinchTrack.extremePitch = pitch
      }
    }
    pinchTrack.direction = direction
    // Continuing beyond a natural stop can reach another pair in the same
    // gesture. Reversing within a pair never needs to cross that stop again.
    let next = direction > 0
      ? Int(ceil(z - Self.previewHysteresis)) : Int(floor(z + Self.previewHysteresis))
    current = direction > 0 ? max(current, next) : min(current, next)
    current = min(columnStops.count - 1, max(0, current))
    let count = columnStops[current]
    if count != stage.shownColumns {
      ensureFace(count)
      stage.show(count, animated: !UIAccessibility.isReduceMotionEnabled)
    }
  }
  /// Text follows geometric density, independently of the photo mixture. The
  /// arithmetic midpoint of the 5/3 pitches is about 1.34 times the five pitch.
  func updateStageHeader(forcing count: Int? = nil) {
    guard let stage else { return }
    let count = count ?? columnStops.min { abs(stopPitch($0) - stage.pitch) < abs(stopPitch($1) - stage.pitch) } ?? columns
    guard count != pinchTrack.headerColumns else { return }
    pinchTrack.headerColumns = count
    stageHeaderChanged(count)
  }
  /// Release preserves the preview intent, even while its size is much nearer
  /// the source stop. A short, unrecognized deliberate pinch still steps once.
  func finishStage(cancelled: Bool, forcing forced: Int? = nil) {
    guard let stage else { return }
    let start = pinchTrack.startIndex
    var target = columnStops.firstIndex(of: stage.shownColumns) ?? start
    if pinchTrack.recognizedDistance == nil, abs(pinchTrack.intent) > 6 {
      target = start + (pinchTrack.intent < 0 ? 1 : -1)
    }
    if cancelled { target = start }
    if let forced { target = forced }
    target = min(columnStops.count - 1, max(0, target))
    let count = columnStops[target]
    ensureFace(count)
    stage.show(count, animated: !UIAccessibility.isReduceMotionEnabled)
    updateStageHeader(forcing: count)
    guard let face = stage.faces[count] else { completeStage(); return }
    // The collection is adopted only when the settle ends, beneath the stage;
    // its final offset is derived from the target geometry and header insets.
    let insets = gridInsets(showsInterval: count <= 5)
    let height = face.geometry.height
    let offset = min(
      max(-insets.top, cancelled ? pinchTrack.startOffset : face.focus.y - stage.focus.y),
      max(-insets.top, height - grid.bounds.height + insets.bottom))
    pinchTrack.target = target
    pinchTrack.finalOffset = offset
    let targetFocus = CGPoint(x: face.focus.x, y: face.focus.y - offset)
    let velocity: CGFloat
    if let first = pinchTrack.samples.first, let last = pinchTrack.samples.last, last.0 - first.0 > 0.01 {
      velocity = (last.1 - first.1) / CGFloat(last.0 - first.0)
    } else {
      velocity = 0
    }
    if UIAccessibility.isReduceMotionEnabled {
      stage.pitch = stopPitch(count)
      stage.focus = targetFocus
      completeStage()
      return
    }
    stage.hurryBlend(within: 0.35)
    stage.setSettle(pitch: stopPitch(count), focus: targetFocus, velocity: velocity) { [weak self] in
      self?.completeStage()
    }
  }
  func completeStage() {
    guard let stage else { return }
    stage.pause()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if let target = pinchTrack.target, let face = stage.faces[columnStops[target]] {
      level = .all
      columns = columnStops[target]
      stage.show(columns, animated: false)
      stage.pitch = face.pitch
      stage.focus = CGPoint(x: face.focus.x, y: face.focus.y - pinchTrack.finalOffset)
      stage.layoutAll()
      adoptingTiles = stage.presentations(columns)
      leadingSlots = face.geometry.leadingSlots
      layout.level = .all
      layout.geometry = face.geometry
      UIView.performWithoutAnimation {
        layout.invalidateLayout()
        grid.reloadData()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        grid.contentSize = layout.collectionViewContentSize
        place(clampedOffset(pinchTrack.finalOffset))
        // The adopted canvas renders off-thread beneath the retained stage.
        if layout.geometry.dense { denseCanvasKey = "" }
        syncDenseCanvas()
      }
    }
    adoptingTiles = [:]
    pinchTrack.target = nil
    self.stage = nil
    adoptionCover = stage
    grid.alpha = 1
    grid.accessibilityElementsHidden = false
    grid.panGestureRecognizer.isEnabled = true
    changing = false
    subtitleLabel.alpha = 1
    subtitleRange = nil
    view.setNeedsLayout()
    announceDensity()
    updateChrome()
    refreshNativePeriodControls()
    // The visible native cells now strongly own the exact presented images.
    // Keep the last stage over them until their layout/display transaction commits.
    CATransaction.setCompletionBlock { [weak self, weak stage] in
      DispatchQueue.main.async {
        guard let self, let stage, self.adoptionCover === stage else { return }
        if self.layout.geometry.dense { self.finishDenseAdoption() }
        else {
          stage.stop(); stage.removeFromSuperview(); self.adoptionCover = nil
          self.applyPendingAssets()
        }
      }
    }
    CATransaction.commit()
    adjacentWarmKey = nil
    warmAdjacentScenes()
    onVisibleChange()
  }
  func density(columns target: Int, at item: Int?) {
    guard level == .all, !assets.isEmpty, target != columns || stage != nil,
      let index = columnStops.firstIndex(of: target)
    else { return }
    beginStage(point: nil, item: item, distance: nil)
    finishStage(cancelled: false, forcing: index)
  }
  /// A geometric density change updates the date range without retargeting the
  /// independently running photo fade or mutating the native collection.
  func stageHeaderChanged(_ count: Int) {
    if count <= 5, !indexing, subtitleAtRecentEdge != true, let stage,
      let face = ensureFace(count)
    {
      let scale = stage.pitch / face.pitch
      let viewport = CGRect(x: face.focus.x - stage.focus.x / scale,
        y: face.focus.y + (view.safeAreaInsets.top - stage.focus.y) / scale,
        width: stage.bounds.width / scale,
        height: (stage.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 50) / scale)
      let visible = face.geometry.visible(in: viewport).filter {
        face.geometry.tiles[$0].frame.intersects(viewport)
      }.map { face.geometry.tiles[$0].asset }
      if let first = visible.min(), let last = visible.max(),
        let a = assets[first].date, let b = assets[last].date {
        subtitleLabel.text = Calendar.current.isDate(a, inSameDayAs: b)
          ? a.formatted(date: .abbreviated, time: .omitted) : intervalFormatter.string(from: a, to: b)
      }
    }
    let changes = { self.view.setNeedsLayout(); self.view.layoutIfNeeded() }
    if UIAccessibility.isReduceMotionEnabled { changes() } else {
      UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState], animations: changes)
    }
  }
  func stageTile(_ tileLayer: CALayer, asset index: Int, pixels: CGFloat) -> (() -> Void)? {
    guard assets.indices.contains(index) else { return nil }
    let asset = assets[index]
    let uncropped = (tileLayer.superlayer as? CalendarZoomStage.Tile)?.columns == 1
    (tileLayer.superlayer as? CalendarZoomStage.Tile)?.assetAspect = uncropped ? asset.aspect : nil
    tileLayer.name = asset.id
    func display(_ image: UIImage?, cloud: Bool = false) {
      if let tile = tileLayer.superlayer as? CalendarZoomStage.Tile { tile.display(image, cloud: cloud) }
      else if let image { tileLayer.contents = image.cgImage }
    }
    let dense = pixels <= 128
    if let seed = stage?.seedTiles[asset.id] {
      if let tile = tileLayer.superlayer as? CalendarZoomStage.Tile,
        tile.decorations?.layer.superlayer === tile, let badges = seed.badges {
        tile.decorations?.apply(badges)
        tile.photo.opacity = badges.imageOpacity
      }
      display(seed.image, cloud: seed.cloud)
      if dense,let image = seed.image,max(image.size.width,image.size.height)*image.scale >= pixels-1 { return nil }
    }
    let cached = dense ? transitionSmallImages.object(forKey: asset.id as NSString) ?? storedImage(asset, pixels)
      : transitionImages.object(forKey: asset.id as NSString)
    if let cached {
      display(cached)
      if cached.size.width * cached.scale >= pixels - 1,
        !uncropped || abs(log((cached.size.width / max(1,cached.size.height)) / max(0.01,asset.aspect))) < 0.05 { return nil }
    }
    let request = uncropped ? requestUncroppedImage ?? requestImage : requestImage
    return request(asset, pixels) { [weak self, weak tileLayer] image, cloud in
      guard let tileLayer, tileLayer.name == asset.id else { return }
      if let image { self?.rememberImage(image, for: asset.id, aspect: uncropped ? asset.aspect : nil) }
      let best = dense ? self?.transitionSmallImages.object(forKey: asset.id as NSString) ?? image
        : self?.transitionImages.object(forKey: asset.id as NSString) ?? image
      CATransaction.begin(); CATransaction.setDisableActions(true)
      if let tile = tileLayer.superlayer as? CalendarZoomStage.Tile { tile.display(best, cloud: cloud) }
      else if let best { tileLayer.contents = best.cgImage }
      CATransaction.commit()
    }
  }
  /// Light period pill matching the dense collection headings: quiet year,
  /// bright month, or the year alone in the yearly overview.
  func pillImage(_ title: String, yearly: Bool) -> CGImage? {
    let key = "\(yearly)|\(title)" as NSString
    if let cached = pillImages.object(forKey: key) { return cached.cgImage }
    let label = CalendarGlassHeading.pillText(title, yearly: yearly)
    let size = label.size()
    let pill = CGSize(width: ceil(size.width) + 20, height: 30)
    let format = UIGraphicsImageRendererFormat()
    format.scale = traitCollection.displayScale
    let image = UIGraphicsImageRenderer(size: pill, format: format).image { _ in
      DuckMedia.labelPlateUIColor.setFill()
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: pill), cornerRadius: 12).fill()
      label.draw(at: CGPoint(x: 10, y: (pill.height - size.height) / 2))
    }
    pillImages.setObject(image, forKey: key)
    return image.cgImage
  }
  func captureAnchor(item: Int? = nil, point: CGPoint? = nil) {
    let p: CGPoint
    if let point {
      p = point
    } else if let item, layout.geometry.tiles.indices.contains(item) {
      let f = layout.frame(item)
      p = CGPoint(x: f.midX, y: f.midY)
    } else if let last = layout.geometry.tiles.indices.last,
      clampedOffset(.greatestFiniteMagnitude) - grid.contentOffset.y < 24
    {
      let f = layout.frame(last)
      p = CGPoint(x: f.midX, y: f.maxY)
    } else {
      p = CGPoint(x: grid.bounds.midX, y: grid.bounds.midY)
    }
    let nearest = visibleItems().min { a,b in
      let x = layout.frame(a),y = layout.frame(b)
      return hypot(x.midX-p.x,x.midY-p.y) < hypot(y.midX-p.x,y.midY-p.y)
    }
    let i = item ?? self.item(at: p) ?? nearest
    anchor = i
    guard let i else { return }
    let f = layout.frame(i)
    anchorFraction = CGPoint(
      x: min(1, max(0, (p.x - f.minX) / max(1, f.width))),
      y: min(1, max(0, (p.y - f.minY) / max(1, f.height))))
    anchorPoint = CGPoint(x: p.x, y: p.y - grid.contentOffset.y)
  }
  func placeAnchor() {
    guard let anchor else { return }
    let f = layout.frame(anchor)
    // UICollectionView can still expose the previous contentSize during reload.
    // Clamp to the adopted geometry, not the outgoing layout's height.
    grid.contentSize = layout.collectionViewContentSize
    place(clampedOffset(f.minY + f.height * anchorFraction.y - anchorPoint.y))
  }
  func announceDensity() {
    grid.accessibilityValue = String(
      format: NSLocalizedString("calendar_grid_columns", comment: ""), columns)
  }
  @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
    guard !assets.isEmpty else { return }
    let live = gesture as? CalendarPinchGesture
    if level == .all {
      switch gesture.state {
      case .began:
        beginStage(point: live?.focus(in: grid) ?? gesture.location(in: grid), item: nil,
          distance: live?.downDistance ?? live?.distance())
        updateStage(distance: live?.distance())
      case .changed:
        guard let distance = live?.distance() else { return }
        updateStage(distance: distance)
      case .ended: finishStage(cancelled: false)
      case .cancelled, .failed: finishStage(cancelled: true)
      default: break
      }
      return
    }
    // Years and Months do not follow the fingers in Photos: a pinch past a
    // small threshold triggers the ordinary level change once, anchored on the
    // card under the fingers.
    switch gesture.state {
    case .began:
      coverPinchTriggered = false
      triggerCoverPinch(gesture)
    case .changed:
      triggerCoverPinch(gesture)
    default:
      coverPinchTriggered = false
    }
  }
  func triggerCoverPinch(_ gesture: UIPinchGestureRecognizer) {
    guard !coverPinchTriggered, level != .all, !changing else { return }
    let next: CalendarGridLevel
    if gesture.scale > 1.08 { next = level == .years ? .months : .all }
    else if gesture.scale < 0.92, level == .months { next = .years }
    else { return }
    coverPinchTriggered = true
    let point = (gesture as? CalendarPinchGesture)?.focus(in: grid) ?? gesture.location(in: grid)
    let index = item(at: point) ?? visibleItems().min {
      hypot(layout.frame($0).midX - point.x, layout.frame($0).midY - point.y)
        < hypot(layout.frame($1).midX - point.x, layout.frame($1).midY - point.y)
    }
    guard let index else { return }
    let tile = layout.geometry.tiles[index]
    let asset = (grid.cellForItem(at: IndexPath(item: index, section: 0)) as? CalendarGridCell)?.coverAsset
      ?? coverIndices[tile.id] ?? tile.asset
    changeLevel(next, asset: asset, from: IndexPath(item: index, section: 0))
  }
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    syncDenseCanvas()
    if !changing {
      updateChrome()
      onVisibleChange()
    }
  }
  func updateChrome() {
    guard isViewLoaded, filterItem != nil, !chromeUpdating else { return }
    chromeUpdating = true
    updateMediaHeader()
    defer { chromeUpdating = false }
    let bottomY = max(
      -grid.contentInset.top,
      grid.contentSize.height - grid.bounds.height + grid.contentInset.bottom)
    let recent = bottomY - grid.contentOffset.y < 24
    let visible = (level == .all && columns <= 5 ? grid.indexPathsForVisibleItems : []).compactMap {
      path -> Int? in
      guard layout.geometry.tiles.indices.contains(path.item) else { return nil }
      let f = layout.frame(path.item)
      return f.maxY > grid.contentOffset.y + view.safeAreaInsets.top + 12
        && f.minY < grid.contentOffset.y + view.bounds.height - view.safeAreaInsets.bottom - 50
        ? layout.geometry.tiles[path.item].asset : nil
    }
    let range = visible.min().flatMap { first in visible.max().map { first...$0 } }
    let total = displayedTotal ?? assets.count
    let needsSubtitle =
      subtitleRange != range || subtitleAtRecentEdge != recent
      || subtitleIndexing != (indexing && assets.isEmpty) || subtitleTotal != total || subtitleViewTitle != viewTitle
    subtitleViewTitle = viewTitle
    subtitleIndexing = indexing && assets.isEmpty
    subtitleTotal = total
    subtitleRange = range
    subtitleAtRecentEdge = recent
    if needsSubtitle, level == .all, columns <= 5 {
      // Background rebuilds during iCloud sync keep the visible subtitle.
      if indexing && assets.isEmpty {
        subtitleLabel.text = NSLocalizedString("library_loading", comment: "")
      } else if recent {
        let count = String(
          format: NSLocalizedString("library_count_compact", comment: ""),
          (displayedTotal ?? assets.count).formatted())
        subtitleLabel.text = viewTitle.map { "\($0) · \(count)" } ?? count
      } else if let range, let a = assets[range.lowerBound].date,
        let b = assets[range.upperBound].date
      {
        subtitleLabel.text =
          Calendar.current.isDate(a, inSameDayAs: b)
          ? a.formatted(date: .abbreviated, time: .omitted)
          : intervalFormatter.string(from: a, to: b)
      } else {
        subtitleLabel.text = ""
      }
    }
    selectedButton.setTitle(
      selected.isEmpty ? NSLocalizedString("calendar_select_items", comment: "") : String(format: NSLocalizedString("calendar_show_selected", comment: ""), selected.count),
      for: .normal)
    selectedButton.isEnabled = !selected.isEmpty
    let backupTitle = backupFeedback.isEmpty
      ? String(format: NSLocalizedString("selection_backup_count", comment: ""), selected.count) : backupFeedback
    if backupItem.title != backupTitle { backupItem.title = backupTitle; backupItem.accessibilityLabel = backupTitle }
    let backupEnabled = canBackup && !selected.isEmpty && !backupAdded
    if backupItem.isEnabled != backupEnabled {
      backupItem.isEnabled = backupEnabled
      refreshMenu()
    }
    selectionControls.setNeedsLayout()
    updateHeader(animated: true)
    let next: Chrome =
      selecting
      ? .selection : ((!recent || level != .all) && !expandedNavigation ? .browsing : .navigation)
    adoptChrome(next)
    if #available(iOS 26.0, *), usesNativeMinimization, recent, level == .all, nativeBarCompact {
      restoreNativeNavigation()
    }
  }
  /// Native `onScrollUp` minimization does not restore at the newest edge,
  /// where Photos restores. Briefly disabling minimization restores the bar
  /// through the system animation; the behavior is re-enabled next turn.
  @available(iOS 26.0, *) func restoreNativeNavigation() {
    guard let tabs = tabBarController, !restoringNativeNavigation,
      tabs.tabBarMinimizeBehavior == .onScrollUp else { return }
    restoringNativeNavigation = true
    // Fade the period controls first, then let the bar grow back.
    setNativePeriod(false)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak tabs] in
      guard let self, let tabs, self.active else { self?.restoringNativeNavigation = false; return }
      UIView.animate(springDuration: 0.35, bounce: 0) {
        tabs.tabBarMinimizeBehavior = .never
        tabs.tabBar.layoutIfNeeded()
      }
      DispatchQueue.main.async {
        self.restoringNativeNavigation = false
        if tabs.tabBarMinimizeBehavior == .never { tabs.tabBarMinimizeBehavior = .onScrollUp }
      }
    }
  }
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    periodFocusAssetID = nil
    expandedNavigation = false
    stopCoverPlayback()
  }
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if !decelerate { warmAdjacentScenes() }
  }
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { warmAdjacentScenes() }
  /// Native minimization uses public layout observation on supported systems.
  var usesNativeMinimization: Bool {
    if #available(iOS 26.0, *) { return nativeBarObserver?.available == true }
    return false
  }
  /// Time the bar last left its minimized state, so a compact-button tap
  /// delivered after the layout change still counts as an expansion.
  var nativeBarExpandedAt: CFTimeInterval = 0
  var nativeBarRecentlyCompact: Bool {
    nativeBarCompact || CACurrentMediaTime() - nativeBarExpandedAt < 0.35
  }
  var periodShown = false, periodEntry = 0
  func nativeBarMorphed(minimized: Bool) {
    let expanded = nativeBarCompact && !minimized
    if expanded { nativeBarExpandedAt = CACurrentMediaTime() }
    nativeBarCompact = minimized
    refreshNativePeriodControls()

  }
  var userScrolling: Bool { grid.isTracking || grid.isDragging || grid.isDecelerating }
  func refreshNativePeriodControls() {
    guard #available(iOS 26.0, *), usesNativeMinimization, let tabs = tabBarController else { return }
    setNativePeriod(nativeBarCompact && active && !selecting && !tabs.isTabBarHidden)
  }
  /// Preserve the existing 130 ms entry delay after compact geometry appears,
  /// then materialize the glass and rise 14 pt on a 300 ms
  /// spring without bounce. Exit dematerializes in place within 80 ms, before the
  /// expanding platter reaches the surface. A visual-effect change ignores
  /// animation delays, so entry waits explicitly and never begins from the
  /// current state, which would capture a stale presentation value.
  func setNativePeriod(_ visible: Bool, animated: Bool = true) {
    guard #available(iOS 26.0, *), let tabs = tabBarController ?? tabOwner else { return }
    guard visible != periodShown else {
      if visible { layoutNativePeriod(tabs) }
      return
    }
    periodShown = visible
    periodEntry += 1
    let entry = periodEntry
    periodSurface.layer.removeAllAnimations()
    dock.layer.removeAllAnimations()
    periodSurface.isUserInteractionEnabled = visible
    periodSurface.accessibilityElementsHidden = !visible
    let material: UIVisualEffect =
      UIAccessibility.isReduceTransparencyEnabled
      ? UIBlurEffect(style: .systemChromeMaterial) : UIGlassEffect(style: .regular)
    let still = UIAccessibility.isReduceMotionEnabled
    if visible {
      attachPeriodSurface(tabs)
      UIView.performWithoutAnimation {
        periodSurface.isHidden = false
        periodSurface.alpha = 1
        periodSurface.effect = nil
        dock.alpha = 0
        periodSurface.transform = still ? .identity : CGAffineTransform(translationX: 0, y: 14)
        layoutNativePeriod(tabs)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.13 : 0)) { [weak self] in
        guard let self, self.periodShown, entry == self.periodEntry else { return }
        UIView.performWithoutAnimation { self.layoutNativePeriod(tabs) }
        let changes = {
          self.periodSurface.effect = material
          self.dock.alpha = 1
          self.periodSurface.transform = .identity
        }
        if animated {
          UIView.animate(
            springDuration: still ? 0.2 : 0.3, bounce: 0, initialSpringVelocity: 0, delay: 0,
            options: [.allowUserInteraction], animations: changes)
        } else {
          changes()
        }
      }
    } else {
      let settle = { [weak self] in
        guard let self, !self.periodShown, entry == self.periodEntry else { return }
        self.periodSurface.isHidden = true
        self.periodSurface.transform = .identity
      }
      guard animated else {
        periodSurface.effect = nil
        dock.alpha = 0
        settle()
        return
      }
      UIView.animate(withDuration: 0.08, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
        self.periodSurface.effect = nil
        self.dock.alpha = 0
      } completion: { _ in settle() }
    }
  }
  /// The surface centers between the compact native button and its mirror
  /// position, using the same public laid-out geometry as the observer.
  func layoutNativePeriod(_ tabs: UITabBarController) {
    let bar = tabs.tabBar
    let frame = bar.convert(bar.bounds, to: tabs.view)
    let icon = CalendarNativeBarObserver.compactFrame(in: bar, relativeTo: tabs.view) ?? CGRect(x: 28, y: frame.minY + 7, width: 48, height: 48)
    let width = tabs.view.bounds.width
    let reserve = min(icon.maxX, width - icon.minX) + 12
    periodSurface.bounds = CGRect(x: 0, y: 0, width: max(180, width - 2 * reserve), height: 48)
    periodSurface.center = CGPoint(x: tabs.view.bounds.midX, y: icon.midY)
    dock.bounds = periodSurface.bounds.insetBy(dx: 4, dy: 4)
    dock.center = CGPoint(x: periodSurface.bounds.midX, y: periodSurface.bounds.midY)
  }
  /// Host the period surface in the tab controller's view, outside the tab
  /// bar's own container: inside it, the native press effect blanks the glass
  /// for a frame.
  func attachPeriodSurface(_ tabs: UITabBarController) {
    if periodSurface.superview !== tabs.view { tabs.view.addSubview(periodSurface) }
  }

  func adoptChrome(_ next: Chrome) {
    guard active else { return }
    if #available(iOS 26.0, *), usesNativeMinimization, let tabs = tabBarController {
      if !restoringNativeNavigation, tabs.tabBarMinimizeBehavior != .onScrollUp {
        tabs.tabBarMinimizeBehavior = .onScrollUp
      }
      if next == .selection {
        setNativePeriod(false)
        if selectionControls.superview !== view { view.addSubview(selectionControls) }
      }
      if tabs.isTabBarHidden != (next == .selection) {
        tabs.setTabBarHidden(next == .selection, animated: !UIAccessibility.isReduceMotionEnabled)
      }
      browsingControls.isHidden = true
      selectionControls.isHidden = next != .selection
      selectionControls.alpha = 1
      selectionControls.transform = .identity
      chrome = next
      refreshNativePeriodControls()
      return
    }
    if selectionControls.superview !== view { view.addSubview(selectionControls) }
    if dock.superview !== periodSurface.contentView { periodSurface.contentView.addSubview(dock) }
    let hide = next != .navigation
    if #available(iOS 18.0, *), let tabs = tabBarController, tabs.isTabBarHidden != hide {
      tabs.setTabBarHidden(hide, animated: !UIAccessibility.isReduceMotionEnabled)
    } else if #unavailable(iOS 18.0) {
      tabBarController?.tabBar.isHidden = hide
    }
    guard next != chrome else { return }
    let previousChrome = chromeMotion
    chromeMotion = nil
    previousChrome?.stopAnimation(true)
    let from = chrome
    chrome = next
    browsingControls.isHidden = false
    selectionControls.isHidden = false
    if from != .browsing {
      browsingControls.alpha = 0
      browsingControls.transform = CGAffineTransform(translationX: 0, y: 16)
    }
    if from != .selection {
      selectionControls.alpha = 0
      selectionControls.transform = CGAffineTransform(translationX: 0, y: 16)
    }
    let settle: () -> Void = { [weak self] in
      guard let self else { return }
      self.browsingControls.isHidden = self.chrome != .browsing
      self.selectionControls.isHidden = self.chrome != .selection
      self.chromeMotion = nil
    }
    let changes: () -> Void = { [weak self] in
      self?.browsingControls.alpha = next == .browsing ? 1 : 0
      self?.selectionControls.alpha = next == .selection ? 1 : 0
      self?.browsingControls.transform =
        next == .browsing ? .identity : CGAffineTransform(translationX: 0, y: 16)
      self?.selectionControls.transform =
        next == .selection ? .identity : CGAffineTransform(translationX: 0, y: 16)
    }
    if UIAccessibility.isReduceMotionEnabled {
      changes()
      settle()
      return
    }
    let motion = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1)
    motion.addAnimations(changes)
    motion.addCompletion { _ in settle() }
    chromeMotion = motion
    motion.startAnimation()
  }
  @objc func toggleSelection() {
    expandedNavigation = false
    selecting.toggle()
    navigationController?.setNavigationBarHidden(level != .all && !selecting,animated: false)
    if !selecting {
      selected = []
      onSelection(selected)
    }
    refreshSelection()
    updateChrome()
  }
  func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
    if gesture is UITapGestureRecognizer { return layout.geometry.dense && !changing }
    if gesture is UILongPressGestureRecognizer {
      return selecting && gesture.numberOfTouches == 1 && level == .all && columns <= 5 && !changing
    }
    if gesture is UIPinchGestureRecognizer {
      if selectionStart != nil { stopRange(revert: true) }
      return !changing || stage != nil
    }
    return true
  }
  func toggleAsset(_ i: Int) {
    let id = assets[i].id
    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    onSelection(selected)
    refreshSelection()
  }
  func refreshSelection() {
    for path in grid.indexPathsForVisibleItems {
      guard layout.geometry.tiles.indices.contains(path.item) else { continue }
      let asset = assets[layout.geometry.tiles[path.item].asset]
      let cell = grid.cellForItem(at: path) as? CalendarGridCell
      cell?.selection(selected.contains(asset.id), enabled: selecting && level == .all && columns <= 5)
      cell?.accessibilityCustomActions = level == .all ? photoActions(asset) : nil
    }
    if layout.geometry.dense { updateDenseAccessibility() }
    updateChrome()
  }
  @objc func rangeSelect(_ gesture: UILongPressGestureRecognizer) {
    guard level == .all, columns <= 5 else { return }
    rangePoint = gesture.location(in: view)
    switch gesture.state {
    case .began:
      guard let path = grid.indexPathForItem(at: gesture.location(in: grid)) else { return }
      if columns > 5 { density(columns: 5, at: path.item) }
      selectionModeBeforeRange = selecting
      selecting = true
      selectionStart = path.item
      selectionBaseline = selected
      selectionAdding = !selected.contains(assets[path.item].id)
      rangeTime = 0
      rangeLink = CADisplayLink(target: self, selector: #selector(rangeFrame(_:)))
      rangeLink?.add(to: .main, forMode: .common)
      applyRange()
    case .changed: applyRange()
    case .cancelled, .failed: stopRange(revert: true)
    case .ended: stopRange(revert: false)
    default: break
    }
  }
  func applyRange() {
    guard let start = selectionStart else { return }
    let point = grid.convert(rangePoint, from: view)
    let top = grid.bounds.minY + grid.contentInset.top + 1
    let bottom = grid.bounds.maxY - grid.contentInset.bottom - 1
    let safe = CGPoint(
      x: min(grid.bounds.width - 1, max(1, point.x)), y: min(bottom, max(top, point.y)))
    guard let path = grid.indexPathForItem(at: safe), assets.indices.contains(path.item),
      assets.indices.contains(start)
    else { return }
    let ids = Set((min(start, path.item)...max(start, path.item)).map { assets[$0].id })
    let next = selectionAdding ? selectionBaseline.union(ids) : selectionBaseline.subtracting(ids)
    if next != selected {
      selected = next
      onSelection(selected)
      refreshSelection()
    }
  }
  @objc func rangeFrame(_ link: CADisplayLink) {
    guard view.window != nil, selectionStart != nil,
      UIApplication.shared.applicationState == .active
    else {
      stopRange(revert: true)
      return
    }
    let top = view.safeAreaInsets.top + 44
    let bottom = view.bounds.height - view.safeAreaInsets.bottom - 72
    let velocity: CGFloat =
      rangePoint.y < top
      ? -min(1, (top - rangePoint.y) / 44) * 480
      : rangePoint.y > bottom ? min(1, (rangePoint.y - bottom) / 44) * 480 : 0
    let dt = rangeTime == 0 ? 0 : min(0.05, link.timestamp - rangeTime)
    rangeTime = link.timestamp
    if velocity != 0 {
      grid.contentOffset.y = clampedOffset(grid.contentOffset.y + CGFloat(dt) * velocity)
      applyRange()
    }
  }
  func stopRange(revert: Bool) {
    defer { if selectionStart == nil, pendingAssets != nil { applyPendingAssets() } }
    rangeLink?.invalidate()
    rangeLink = nil
    rangeTime = 0
    if revert, selectionStart != nil {
      selected = selectionBaseline
      selecting = selectionModeBeforeRange
      onSelection(selected)
      refreshSelection()
    }
    selectionStart = nil
  }
  var configureReview: (CalendarSelectedController) -> Void = { _ in }
  weak var selectionReview: CalendarSelectedController?
  func reviewSelection() {
    let controller = CalendarSelectedController()
    controller.assets = assets.filter { selected.contains($0.id) }
    controller.selected = selected
    selectionReview = controller
    controller.columns = columns
    controller.originalAspect = originalAspect
    controller.requestImage = columns == 1 || originalAspect ? requestUncroppedImage ?? requestImage : requestImage
    controller.cachedImage = { [weak self] asset in
      self?.transitionImages.object(forKey: asset.id as NSString) ?? self?.placeholderImage(asset)
    }
    controller.photoPreview = photoPreview
    controller.onBackup = { [weak self] in self?.backUpSelected() }
    controller.setBackupFeedback(title: backupFeedback, enabled: canBackup, added: backupAdded)
    configureReview(controller)
    controller.onSelection = { [weak self] ids in
      self?.selected = ids
      self?.onSelection(ids)
      self?.refreshSelection()
    }
    let nav = UINavigationController(rootViewController: controller)
    if let sheet = nav.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
    }
    present(nav, animated: true)
  }
}
/// Review actions keep compact default metrics while fitting accessibility text.
@MainActor func calendarReviewActionSize(_ button: UIButton, availableWidth: CGFloat) -> CGSize {
  // Native glass configurations rescale their internal title. Use one explicit
  // Dynamic Type label so the measured and rendered font have the same owner.
  let label: UILabel
  if let existing = button.viewWithTag(801) as? UILabel { label = existing }
  else {
    label = UILabel(); label.tag = 801; label.text = button.currentTitle
    label.numberOfLines = 0; label.textAlignment = .center
    label.isUserInteractionEnabled = false; label.isAccessibilityElement = false
    button.accessibilityLabel = label.text
    button.setTitle(nil,for: .normal)
    if var configuration = button.configuration {
      configuration.title = nil; configuration.attributedTitle = nil
      configuration.titleTextAttributesTransformer = nil; button.configuration = configuration
    }
    button.addSubview(label)
  }
  let font = UIFont.preferredFont(forTextStyle: .body)
  label.font = font; label.textColor = .label
  label.alpha = button.isEnabled ? 1 : 0.4
  let width = max(44,availableWidth)
  let measured = (label.text ?? "").boundingRect(with: CGSize(width: max(1,width-32),height: .greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin,.usesFontLeading],attributes: [.font: font],context: nil)
  let size = CGSize(width: min(width,max(160,ceil(measured.width)+32)),height: max(44,ceil(measured.height)+20))
  label.frame = CGRect(origin: .zero,size: size).insetBy(dx: 16,dy: 10)
  return size
}

/// A frozen membership snapshot with live selection and the library's media pipeline.
final class CalendarSelectedController: UIViewController, UICollectionViewDataSource,
  UICollectionViewDelegateFlowLayout
{
  var assets: [CalendarGridAsset] = [], selected = Set<String>()
  var columns = 3, originalAspect = false
  var requestImage: CalendarGridController.ImageRequest!
  var cachedImage: (CalendarGridAsset) -> UIImage? = { _ in nil }
  var onSelection: (Set<String>) -> Void = { _ in }
  var onBackup: () -> Void = {}
  var onPreview: (CalendarSelectedController) -> Void = { _ in }
  var photoMenu: ((CalendarGridAsset) -> UIMenu?)?
  var photoPreview: ((CalendarGridAsset, UIImage?) -> UIViewController?)?
  var photoAccessibilityActions: ((CalendarGridAsset) -> [UIAccessibilityCustomAction])?
  let flow = UICollectionViewFlowLayout()
  lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: flow)
  private var geometry: CalendarGridGeometry?
  var focusedID: String?
  private var feedback = "", canBackup = true, backupAdded = false
  lazy var browseItem = UIBarButtonItem(image: UIImage(systemName: "rectangle.grid.1x2"),
    style: .plain, target: self, action: #selector(browseSelection))
  lazy var clearItem = UIBarButtonItem(title: NSLocalizedString("library_deselect_all", comment: ""),
    style: .plain, target: self, action: #selector(clearSelection))
  lazy var backupItem = UIBarButtonItem(title: nil, style: .done, target: self, action: #selector(backUp))

  func setSelection(_ ids: Set<String>, notify: Bool = true) {
    selected = ids
    if notify { onSelection(ids) }
    guard isViewLoaded else { return }
    for case let cell as CalendarGridCell in grid.visibleCells { updateSelection(cell) }
    updateActions()
  }
  func setBackupFeedback(title: String, enabled: Bool, added: Bool) {
    feedback = title; canBackup = enabled; backupAdded = added
    guard isViewLoaded else { return }
    grid.isUserInteractionEnabled = enabled
    updateActions()
  }
  private func updateActions() {
    navigationItem.title = String(format: NSLocalizedString("library_review_selection_title", comment: ""), selected.count)
    browseItem.isEnabled = !assets.isEmpty
    clearItem.isEnabled = canBackup && !selected.isEmpty
    backupItem.title = feedback.isEmpty
      ? String(format: NSLocalizedString("library_review_backup_count", comment: ""), selected.count) : feedback
    backupItem.isEnabled = canBackup && !selected.isEmpty && !backupAdded
  }
  private func updateSelection(_ cell: CalendarGridCell) {
    let included = selected.contains(cell.assetID)
    cell.selection(included, enabled: true)
    cell.accessibilityValue = NSLocalizedString(included ? "library_review_selected" : "library_review_not_selected", comment: "")
  }
  private func toggle(_ id: String) {
    guard canBackup else { return }
    var ids = selected
    if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    focusedID = id
    setSelection(ids)
  }
  private var hiddenPreviewID: String?
  func setPreviewHidden(_ id: String?) {
    hiddenPreviewID = id
    UIView.performWithoutAnimation {
      for case let cell as CalendarGridCell in grid.visibleCells {
        cell.contentView.isHidden = id != nil && cell.assetID == id
      }
    }
  }
  func previewFrame(_ id: String) -> CGRect? {
    guard let index = assets.firstIndex(where: { $0.id == id }) else { return nil }
    focusedID = id
    let path = IndexPath(item: index,section: 0)
    let visible = grid.bounds.inset(by: grid.adjustedContentInset)
    let frame = grid.layoutAttributesForItem(at: path)?.frame ?? .zero
    if grid.cellForItem(at: path) == nil || !visible.contains(frame) {
      grid.scrollToItem(at: path,at: .centeredVertically,animated: false); grid.layoutIfNeeded()
    }
    guard let cell = grid.cellForItem(at: path) as? CalendarGridCell else { return nil }
    return cell.image.convert(cell.image.bounds,to: nil)
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    flow.minimumLineSpacing = CalendarGridGeometry.gap(columns: columns)
    flow.minimumInteritemSpacing = flow.minimumLineSpacing
    grid.dataSource = self; grid.delegate = self
    grid.backgroundColor = .clear
    grid.register(CalendarGridCell.self, forCellWithReuseIdentifier: "selected")
    grid.accessibilityIdentifier = "calendar.selected_grid"
    view.addSubview(grid)
    browseItem.accessibilityIdentifier = "calendar.selected_browse"
    browseItem.accessibilityLabel = NSLocalizedString("library_browse_selected", comment: "")
    navigationItem.leftBarButtonItem = browseItem
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .done, target: self, action: #selector(done))
    navigationItem.rightBarButtonItem?.accessibilityIdentifier = "calendar.selected_done"
    if #available(iOS 26.0, *) { backupItem.style = .prominent }
    clearItem.accessibilityIdentifier = "calendar.selected_deselect_all"
    if #available(iOS 26.0, *) { clearItem.hidesSharedBackground = true }
    backupItem.accessibilityIdentifier = "calendar.selected_backup"
    toolbarItems = [clearItem, UIBarButtonItem(systemItem: .flexibleSpace), backupItem]
    navigationController?.setToolbarHidden(false, animated: false)
    grid.isUserInteractionEnabled = canBackup
    updateActions()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if geometry == nil || grid.bounds.width != view.bounds.width {
      geometry = CalendarGridGeometry(assets: assets, level: .all, width: view.bounds.width,
        columns: columns, originalAspect: originalAspect)
      flow.invalidateLayout()
    }
    grid.frame = view.bounds
  }
  func collectionView(_ v: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt p: IndexPath) -> CGSize {
    geometry?.tiles[p.item].frame.size
      ?? CGSize(width: CalendarGridGeometry.side(width: v.bounds.width, columns: columns),
        height: CalendarGridGeometry.side(width: v.bounds.width, columns: columns))
  }
  func collectionView(_ v: UICollectionView, numberOfItemsInSection s: Int) -> Int { assets.count }
  func collectionView(_ v: UICollectionView, cellForItemAt p: IndexPath) -> UICollectionViewCell {
    let cell = v.dequeueReusableCell(withReuseIdentifier: "selected", for: p) as! CalendarGridCell
    let asset = assets[p.item]
    cell.assetID = asset.id
    cell.assetAspect = columns == 1 || originalAspect ? asset.aspect : nil
    cell.contentView.isHidden = hiddenPreviewID == asset.id
    cell.label.isHidden = true; cell.scrim.isHidden = true
    cell.backupState(nil, visible: false)
    updateSelection(cell)
    cell.duration.text = asset.videoDuration
    cell.duration.isHidden = asset.videoDuration == nil
    cell.liveMark.isHidden = !asset.live
    cell.accessibilityIdentifier = "calendar.selected." + asset.id
    cell.accessibilityLabel = asset.date?.formatted(date: .abbreviated,time: .shortened)
    cell.accessibilityCustomActions = photoAccessibilityActions?(asset)
    cell.accessibilityToggle = { [weak self] in
      guard let self, self.canBackup else { return false }
      self.toggle(asset.id); return true
    }
    cell.thumbnail(cachedImage(asset), cloud: false)
    cell.resumeThumbnail = { [weak self, weak cell] in
      guard let self, let cell, cell.assetID == asset.id else { return }
      let size = self.geometry?.tiles[p.item].frame.size ?? cell.bounds.size
      let side = max(size.width, size.height)
      cell.cancel = self.requestImage(asset, max(40, side * self.traitCollection.displayScale)) { [weak cell] image, cloud in
        guard cell?.assetID == asset.id else { return }
        cell?.thumbnail(image, cloud: cloud)
      }
    }
    cell.resumeThumbnail?()
    return cell
  }
  func collectionView(_ v: UICollectionView, didSelectItemAt p: IndexPath) { toggle(assets[p.item].id) }
  func collectionView(_ v: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt p: IndexPath) {
    guard let cell = cell as? CalendarGridCell, cell.cancel == nil else { return }
    cell.resumeThumbnail?()
  }
  func collectionView(_ v: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt p: IndexPath) {
    (cell as? CalendarGridCell)?.cancel?()
    (cell as? CalendarGridCell)?.cancel = nil
  }
  func collectionView(_ v: UICollectionView, contextMenuConfigurationForItemAt p: IndexPath,
    point: CGPoint) -> UIContextMenuConfiguration? {
    let asset = assets[p.item]
    let poster = (v.cellForItem(at: p) as? CalendarGridCell)?.image.image ?? cachedImage(asset)
    return UIContextMenuConfiguration(identifier: asset.id as NSString, previewProvider: { [weak self] in
      self?.photoPreview?(asset, poster)
    }) { [weak self] _ in self?.photoMenu?(asset) }
  }
  func collectionView(_ v: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionCommitAnimating) {
    guard let id = configuration.identifier as? String else { return }
    animator.preferredCommitStyle = .dismiss
    animator.addCompletion { [weak self] in
      guard let self else { return }
      self.focusedID = id; self.onPreview(self)
    }
  }
  @objc private func clearSelection() { setSelection([]) }
  @objc private func browseSelection() {
    focusedID = focusedID ?? assets.first?.id
    onPreview(self)
  }
  @objc private func backUp() { if backupItem.isEnabled { onBackup() } }
  @objc func done() { navigationController?.dismiss(animated: true) }
}

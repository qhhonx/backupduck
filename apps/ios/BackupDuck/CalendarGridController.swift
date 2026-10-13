import AVFoundation
import UIKit

struct CalendarGridAsset: Equatable {
  let id: String
  let date: Date?
  let aspect: CGFloat
  var videoDuration: String? = nil
  var live = false
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
  init(
    assets: [CalendarGridAsset], level: CalendarGridLevel, width: CGFloat, columns: Int,
    originalAspect: Bool, leadingSlots: Int = 0
  ) {
    guard width > 0 else { return }
    self.leadingSlots = leadingSlots
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
      let gap: CGFloat = columns >= 10 ? 1 : 2
      let side = (width - CGFloat(columns - 1) * gap) / CGFloat(columns)
      var row: [(Int, CGFloat)] = []
      var rowY: CGFloat = 0
      func appendRow() {
        guard !row.isEmpty else { return }
        let height =
          originalAspect
          ? min(side * 1.8, max(side * 0.55, row.map { side / max(0.2, $0.1) }.max() ?? side))
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
      let unit = (width - 52) / 3
      for (month, range) in buckets(.month, range: assets.indices) {
        let title =
          month.map { $0.formatted(.dateTime.year().month(.wide)) }
          ?? NSLocalizedString("design_capture_unknown", comment: "")
        headings.append((title, CGRect(x: 20, y: y, width: width - 40, height: 40)))
        y += 48
        let days = buckets(.day, range: range)
        var cursor = 0
        var block = 0
        while cursor < days.count {
          let remaining = days.count - cursor
          var count = min(6, remaining)
          if remaining > 6 {
            count = block % 2 == 0 ? 5 : 6
            if remaining - count < 4 { count = remaining - 4 }
          }
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
          cursor += count
          block += 1
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
    height = y + 16
    maximumTileHeight = tiles.map { $0.frame.height }.max() ?? 1
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
    let indices = geometry.visible(in: rect)
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
    label.textColor = UIColor(DuckColors.text)
    label.accessibilityIdentifier = "calendar.date_badge"
  }
  func title(_ text: String, dense: Bool, yearly: Bool) {
    glass.overrideUserInterfaceStyle = dense ? .dark : .unspecified
    label.font = .systemFont(ofSize: dense ? 15 : 20, weight: .semibold)
    label.accessibilityIdentifier = "calendar.period_heading"
    if dense {
      let title = NSMutableAttributedString(
        string: text, attributes: [.foregroundColor: UIColor.white])
      if !yearly, let year = text.range(of: "[0-9]{4}年?", options: .regularExpression) {
        title.addAttribute(
          .foregroundColor, value: UIColor.white.withAlphaComponent(0.55),
          range: NSRange(year, in: text))
      }
      label.attributedText = title
    } else {
      label.attributedText = nil
      label.textColor = UIColor(DuckColors.text)
      label.text = text
    }
    setNeedsLayout()
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    glass.frame = CGRect(
      x: 0, y: 0, width: min(bounds.width, label.intrinsicContentSize.width + 20),
      height: bounds.height)
    label.frame = glass.bounds.insetBy(dx: 10, dy: 3)
  }
}
final class CalendarGridCell: UICollectionViewCell {
  let image = UIImageView(), placeholder = UIImageView(), label = UILabel(), check = UIImageView(),
    duration = UILabel(), scrim = CAGradientLayer()
  let stateMark = UIImageView(), liveMark = UIImageView()
  var cancel: (() -> Void)?, assetID = "", coverAsset: Int?
  let videoLayer = AVPlayerLayer()
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
    videoLayer.player?.pause()
    videoLayer.player = nil
    videoLayer.removeFromSuperlayer()
    if let videoLoop { NotificationCenter.default.removeObserver(videoLoop) }
    videoLoop = nil
  }
  override init(frame: CGRect) {
    super.init(frame: frame)
    image.contentMode = .scaleAspectFill
    image.clipsToBounds = true
    contentView.addSubview(image)
    contentView.backgroundColor = UIColor(DuckColors.subtle)
    placeholder.image = UIImage(systemName: "photo")
    placeholder.tintColor = UIColor(DuckColors.textSecondary)
    placeholder.contentMode = .scaleAspectFit
    contentView.addSubview(placeholder)
    scrim.colors = [UIColor.black.withAlphaComponent(0.32).cgColor, UIColor.clear.cgColor]
    contentView.layer.addSublayer(scrim)
    label.font = .systemFont(ofSize: 23, weight: .semibold)
    label.textColor = .white
    contentView.addSubview(label)
    DuckMediaSelection.configure(check)
    contentView.addSubview(check)
    duration.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    duration.textColor = .white
    duration.backgroundColor = UIColor.black.withAlphaComponent(0.25)
    duration.layer.cornerRadius = 5
    duration.clipsToBounds = true
    duration.textAlignment = .center
    contentView.addSubview(duration)
    stateMark.contentMode = .scaleAspectFit
    stateMark.backgroundColor = UIColor.black.withAlphaComponent(0.3)
    stateMark.layer.cornerRadius = 10
    stateMark.clipsToBounds = true
    contentView.addSubview(stateMark)
    liveMark.tintColor = .white
    liveMark.backgroundColor = UIColor.black.withAlphaComponent(0.3)
    liveMark.layer.cornerRadius = 5
    liveMark.clipsToBounds = true
    liveMark.contentMode = .scaleAspectFit
    contentView.addSubview(liveMark)
    isAccessibilityElement = true
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    image.frame = contentView.bounds
    videoLayer.frame = image.bounds
    placeholder.frame = CGRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32)
    scrim.frame = CGRect(x: 0, y: 0, width: bounds.width, height: min(110, bounds.height))
    label.frame = CGRect(x: 16, y: 12, width: max(1, bounds.width - 32), height: 32)
    check.frame = DuckMediaSelection.frame(in: bounds)
    duration.frame = CGRect(x: bounds.width - 55, y: bounds.height - 24, width: 49, height: 18)
    duration.isHidden = duration.text == nil || bounds.width < 80
    stateMark.frame = CGRect(x: bounds.width - 26, y: 6, width: 20, height: 20)
    stateMark.isHidden = stateMark.image == nil || bounds.width < 80
    liveMark.frame = CGRect(x: 6, y: 6, width: 20, height: 20)
    liveMark.isHidden = liveMark.image == nil || bounds.width < 80
  }
  func thumbnail(_ value: UIImage?, cloud: Bool) {
    if let value { image.image = value }
    placeholder.isHidden = image.image != nil
    placeholder.image = UIImage(systemName: cloud ? "icloud" : "photo")
  }
  func selection(_ selected: Bool, enabled: Bool) {
    DuckMediaSelection.apply(selected, enabled: enabled, badge: check, image: image)
    accessibilityTraits = selected ? [.button, .selected] : [.button]
  }
  func backupState(_ state: String?, visible: Bool) {
    let symbol: String?
    switch state {
    case "received", "received_previous": symbol = "checkmark.circle.fill"
    case "failed": symbol = "exclamationmark.circle.fill"
    case "preparing", "running", "queued", "waiting", "paused", "scheduled":
      symbol = "ellipsis.circle"
    case "partial": symbol = "circle.lefthalf.filled"
    default: symbol = nil
    }
    stateMark.image = visible ? symbol.flatMap { UIImage(systemName: $0) } : nil
    stateMark.tintColor =
      state == "failed"
      ? UIColor(DuckColors.failure)
      : state == "received" || state == "received_previous" ? UIColor(DuckColors.saved) : .white
    setNeedsLayout()
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    cancel?()
    cancel = nil
    stopCover()
    coverAsset = nil
    assetID = ""
    image.image = nil
    placeholder.isHidden = false
    isHidden = false
  }
}

/// Dense mosaics only need a cancellable image view, not hidden labels and
/// badges for every miniature tile. Accessibility still resolves stable IDs.
final class CalendarDenseCell: UICollectionViewCell {
  let photo = UIImageView()
  var assetID = "", cancel: (() -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    photo.contentMode = .scaleAspectFill
    photo.clipsToBounds = true
    contentView.addSubview(photo)
    isAccessibilityElement = true
    accessibilityTraits = .button
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() {
    super.layoutSubviews()
    photo.frame = contentView.bounds
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    cancel?()
    cancel = nil
    assetID = ""
    photo.image = nil
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
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    liveTouches.formUnion(touches)
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
@available(iOS 26.0, *)
final class CalendarAccessoryContent: UIView {
  private(set) var content: UIView
  var onEnvironment: (() -> Void)?
  init(_ content: UIView) {
    self.content = content
    super.init(frame: .zero)
    addSubview(content)
    registerForTraitChanges([UITraitTabAccessoryEnvironment.self]) {
      (view: CalendarAccessoryContent, _: UITraitCollection) in view.onEnvironment?()
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 48) }
  override func layoutSubviews() {
    super.layoutSubviews()
    content.frame = bounds.insetBy(dx: 6, dy: 4)
  }
}

final class CalendarZoomScene: UIView {
  let source = UIImageView(), destination = UIImageView()
  var ratio: CGFloat = 1, progress: CGFloat = 0
  init(frame: CGRect, image: UIImage, focus: CGPoint) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = UIColor(DuckColors.canvas)
    clipsToBounds = true
    for imageView in [destination, source] {
      imageView.bounds = bounds
      imageView.layer.anchorPoint = CGPoint(
        x: focus.x / max(1, bounds.width), y: focus.y / max(1, bounds.height))
      imageView.layer.position = focus
      imageView.contentMode = .scaleToFill
      addSubview(imageView)
    }
    source.image = image
    destination.alpha = 0
  }
  required init?(coder: NSCoder) { fatalError() }
  func faces(
    source image: UIImage, destination next: UIImage, sourcePoint: CGPoint,
    destinationPoint: CGPoint, focus: CGPoint
  ) {
    source.image = image
    destination.image = next
    for (view, point) in [(source, sourcePoint), (destination, destinationPoint)] {
      view.transform = .identity
      view.layer.anchorPoint = CGPoint(
        x: point.x / max(1, bounds.width), y: point.y / max(1, bounds.height))
      view.layer.position = focus
    }
  }
  func apply(_ value: CGFloat) {
    progress = min(1, max(0, value))
    let scale = 1 + (ratio - 1) * progress
    source.transform = CGAffineTransform(scaleX: scale, y: scale)
    destination.transform = CGAffineTransform(
      scaleX: scale / max(0.01, ratio), y: scale / max(0.01, ratio))
    let fade = progress * progress * (3 - 2 * progress)
    source.alpha = 1 - fade
    destination.alpha = fade
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
    let compact: Bool
    if #available(iOS 26.0, *), let accessory = owner?.nativeAccessory as? UITabAccessory {
      compact = accessory.contentView.traitCollection.tabAccessoryEnvironment == .inline
    } else {
      compact = owner?.chrome == .browsing
    }
    beganCompact = compact
    let allowed =
      previous?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
    return allowed
  }
  func tabBarController(
    _ tabBarController: UITabBarController, didSelect viewController: UIViewController
  ) {
    if lastSelected === viewController, !beganCompact { owner?.returnToLatest() }
    lastSelected = viewController
    beganCompact = false
    previous?.tabBarController?(tabBarController, didSelect: viewController)
  }
  @available(iOS 18.0, *)
  func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool
  {
    if #available(iOS 26.0, *), let accessory = owner?.nativeAccessory as? UITabAccessory {
      beganCompact = accessory.contentView.traitCollection.tabAccessoryEnvironment == .inline
    } else {
      beganCompact = owner?.chrome == .browsing
    }
    return previous?.tabBarController?(tabBarController, shouldSelectTab: tab)
      ?? tab.viewController.flatMap {
        previous?.tabBarController?(tabBarController, shouldSelect: $0)
      } ?? true
  }
  @available(iOS 18.0, *)
  func tabBarController(
    _ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?
  ) {
    if selectedTab === previousTab, !beganCompact { owner?.returnToLatest() }
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
  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || (previous?.responds(to: selector) ?? false)
  }
  override func forwardingTarget(for selector: Selector!) -> Any? { previous }
  func restore() { if tabs?.delegate === self { tabs?.delegate = previous } }
}

final class CalendarGridController: UIViewController, UICollectionViewDataSource,
  UICollectionViewDelegate, UIGestureRecognizerDelegate
{
  typealias ImageRequest = (CalendarGridAsset, CGFloat, @escaping (UIImage?, Bool) -> Void) -> (
    () -> Void
  )
  var assets: [CalendarGridAsset] = []
  var requestImage: ImageRequest = { _, _, done in
    done(nil, false)
    return {}
  }
  var onPreview: (CalendarGridAsset, CGRect) -> Void = { _, _ in }
  var onSelection: (Set<String>) -> Void = { _ in }
  var onBackup: () -> Void = {}
  var menu: (() -> [UIMenuElement])?
  var requestVideo: (CalendarGridAsset, @escaping (AVPlayerItem?) -> Void) -> (() -> Void) = {
    _, done in
    done(nil)
    return {}
  }
  var zoomScene: CalendarZoomScene?, zoomRefresh: DispatchWorkItem?
  var zoomStartLevel = CalendarGridLevel.all, zoomTargetLevel = CalendarGridLevel.all
  var zoomStartOffset = CGPoint.zero, zoomStartAsset = 0, zoomSourceWidth: CGFloat = 1
  struct ZoomFrame {
    var image: UIImage
    let point: CGPoint
    let width: CGFloat
  }
  var zoomFrames: [Int: ZoomFrame] = [:]
  var zoomSourceColumns = 3, zoomDestinationColumns = 5
  var zoomInitialWidth: CGFloat = 1
  var zoomProgress: CGFloat = 0
  var coverTimer: Timer?, coverCancel: (() -> Void)?, coverPlaybackID: String?
  weak var playingCoverCell: CalendarGridCell?
  var focusedCoverPeriod: String?
  var coverIndices: [String: Int] = [:]
  var lastCoverChange: CFTimeInterval = 0
  var tabReselection: CalendarTabReselection?
  var motionSourceIDs = Set<String>(), motionDestinationIDs = Set<String>()
  var canBackup = false
  var indexing = false
  var displayedTotal: Int?
  var onVisibleChange: () -> Void = {}
  var photoStates: [String: String] = [:]
  var selected = Set<String>()
  var level = CalendarGridLevel.all, columns = 3, originalAspect = false, selecting = false
  let layout = CalendarGridLayout(), titleLabel = UILabel(), subtitleLabel = UILabel()
  lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
  let headerBackdrop = UIView(), headerFade = CAGradientLayer()
  let titleView = UIView(),
    dock = UISegmentedControl(items: [
      NSLocalizedString("calendar_years", comment: ""),
      NSLocalizedString("calendar_months", comment: ""),
      NSLocalizedString("calendar_all", comment: ""),
    ]), bottom = UIView()
  let libraryButton = UIButton(type: .system)
  let browsingControls = UIView(), selectionControls = CalendarSelectionControls(),
    periodSurface = UIVisualEffectView()
  var selectedButton: UIButton { selectionControls.countButton }
  var accessoryCheck: DispatchWorkItem?
  let transitionImages = NSCache<NSString, UIImage>()
  var subtitleRange: ClosedRange<Int>?
  var subtitleAtRecentEdge: Bool?
  var subtitleIndexing: Bool?, subtitleTotal: Int?
  var denseDateLabels: [Date: String] = [:]
  enum Chrome { case navigation, browsing, selection }
  var nativeAccessory: AnyObject?, installingAccessory = false
  var chrome: Chrome = .navigation, chromeMotion: UIViewPropertyAnimator?,
    expandedNavigation = false
  var filterItem: UIBarButtonItem!, selectItem: UIBarButtonItem!, closeItem: UIBarButtonItem!,
    backupItem: UIBarButtonItem!
  var headerSelecting: Bool?
  weak var tabOwner: UITabBarController?
  weak var contentOwner: UIViewController?
  var spring: UIViewPropertyAnimator?, transitionOverlay: UIView?
  var anchor: Int?, anchorFraction = CGPoint(x: 0.5, y: 0.5), anchorPoint = CGPoint.zero
  var leadingSlots = 0, startLeadingSlots = 0
  var startColumns = 3
  var width: CGFloat = 0, hasPosition = false, changing = false, accessoryVisible = false
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
  let columnStops = [1, 3, 5, 10, 20]
  override func viewDidLoad() {
    super.viewDidLoad()
    transitionImages.totalCostLimit = 24 * 1024 * 1024
    transitionImages.countLimit = 8192
    view.backgroundColor = UIColor(DuckColors.canvas)
    grid.backgroundColor = .clear
    grid.dataSource = self
    grid.delegate = self
    grid.contentInsetAdjustmentBehavior = .never
    grid.accessibilityIdentifier = "library.grid"
    announceDensity()
    grid.register(CalendarGridCell.self, forCellWithReuseIdentifier: "calendar.asset")
    grid.register(CalendarDenseCell.self, forCellWithReuseIdentifier: "calendar.dense")
    grid.register(
      CalendarGlassHeading.self, forSupplementaryViewOfKind: CalendarGridLayout.headingKind,
      withReuseIdentifier: "calendar.heading")
    view.addSubview(grid)
    grid.showsVerticalScrollIndicator = false
    setContentScrollView(grid, for: .all)
    if #available(iOS 26.0, *) {
      grid.topEdgeEffect.style = .soft
      grid.bottomEdgeEffect.style = .soft
    }
    grid.panGestureRecognizer.maximumNumberOfTouches = 1
    let pinch = CalendarPinchGesture(target: self, action: #selector(pinch(_:)))
    pinch.delegate = self
    grid.addGestureRecognizer(pinch)
    let long = CalendarRangeGesture(target: self, action: #selector(rangeSelect(_:)))
    long.minimumPressDuration = 0.4
    long.delegate = self
    grid.addGestureRecognizer(long)
    titleLabel.text = NSLocalizedString("nav_library", comment: "")
    titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
    titleLabel.textColor = UIColor(DuckColors.text)
    subtitleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
      for: .systemFont(ofSize: 14, weight: .semibold), maximumPointSize: 20)
    subtitleLabel.adjustsFontSizeToFitWidth = true
    subtitleLabel.minimumScaleFactor = 0.8
    subtitleLabel.textColor = UIColor(DuckColors.text)
    subtitleLabel.accessibilityIdentifier = "library.count"
    titleView.addSubview(titleLabel)
    // The subtitle belongs below the native navigation bar, not in an oversized
    // 72-point bar item. A semantic edge fade keeps it legible over light media.
    headerBackdrop.isUserInteractionEnabled = false
    headerBackdrop.layer.addSublayer(headerFade)
    view.addSubview(headerBackdrop)
    view.addSubview(subtitleLabel)
    titleView.frame = CGRect(
      x: 0, y: 0, width: max(105, min(160, view.bounds.width - 238)), height: 44)
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
    refreshMenu()
    updateHeader(animated: false)
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    navigationController?.navigationBar.standardAppearance = appearance
    navigationController?.navigationBar.scrollEdgeAppearance = appearance
    dock.selectedSegmentIndex = 2
    dock.accessibilityIdentifier = "library.view_mode"
    dock.addTarget(self, action: #selector(levelChosen), for: .valueChanged)
    if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
      periodSurface.effect = UIGlassEffect(style: .regular)
    } else {
      periodSurface.effect = UIBlurEffect(style: .systemChromeMaterial)
    }
    periodSurface.layer.cornerRadius = 25
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
    backupItem = UIBarButtonItem(
      image: UIImage(systemName: "arrow.up.doc"), style: .plain, target: self,
      action: #selector(backUpSelected))
    backupItem.accessibilityLabel = NSLocalizedString("calendar_backup_action", comment: "")
    backupItem.accessibilityIdentifier = "calendar.backup_selected"
    view.addSubview(selectionControls)
    var normal: UIButton.Configuration
    if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
      normal = .prominentGlass()
    } else {
      normal = .bordered()
    }
    normal.baseBackgroundColor = UIColor(DuckColors.surface)
    normal.cornerStyle = .capsule
    normal.baseForegroundColor = UIColor(DuckColors.text)
    normal.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { original in
      var result = original
      result.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
        for: .systemFont(ofSize: 17, weight: .semibold), maximumPointSize: 22)
      return result
    }
    selectedButton.configuration = normal
    libraryButton.configuration = normal
    browsingControls.isHidden = true
    selectionControls.isHidden = true
  }
  @objc func backUpSelected() {
    guard canBackup, !selected.isEmpty else { return }
    onBackup()
  }
  func refreshMenu() {
    filterItem?.menu = displayMenu()
  }
  func updateHeader(animated: Bool) {
    guard headerSelecting != selecting else { return }
    headerSelecting = selecting
    navigationItem.setRightBarButtonItems(
      selecting ? [closeItem, backupItem, filterItem] : [selectItem, filterItem],
      animated: animated && !UIAccessibility.isReduceMotionEnabled)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    active = true
    startCoverClock()
    installTabReselection()
    tabOwner = tabBarController
    contentOwner = tabBarController?.selectedViewController
    if #available(iOS 26.0, *), let tabs = tabBarController {
      tabs.tabBarMinimizeBehavior = .onScrollUp
      contentOwner?.setContentScrollView(grid, for: .all)
    }
    rebuildIfNeeded()
    updateChrome()
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    active = false
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
    accessoryCheck?.cancel()
    if #available(iOS 26.0, *) {
      tabOwner?.setBottomAccessory(nil, animated: false)
      tabOwner?.tabBarMinimizeBehavior = .never
      nativeAccessory = nil
      contentOwner?.setContentScrollView(nil, for: .bottom)
    }
    if #available(iOS 18.0, *) { tabOwner?.setTabBarHidden(false, animated: false) }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    grid.frame = view.bounds
    let titleWidth = max(105, min(160, view.bounds.width - 238))
    titleView.frame.size.width = titleWidth
    titleLabel.frame.size.width = titleWidth
    let subtitleHeight = subtitleLabel.font.lineHeight + 4
    subtitleLabel.frame = CGRect(
      x: 16, y: view.safeAreaInsets.top - 10,
      width: view.bounds.width - 32, height: subtitleHeight)
    let headerLevel = zoomScene == nil ? level : zoomStartLevel
    let headerColumns = zoomScene == nil ? columns : startColumns
    let showsInterval = headerLevel == .all && headerColumns <= 5
    headerBackdrop.frame = CGRect(
      x: 0, y: 0, width: view.bounds.width,
      height: showsInterval ? subtitleLabel.frame.maxY + 16 : view.safeAreaInsets.top + 16)
    headerFade.frame = headerBackdrop.bounds
    headerBackdrop.isHidden = headerLevel != .all
    subtitleLabel.isHidden = !showsInterval
    updateHeaderFade()
    titleLabel.adjustsFontSizeToFitWidth = true
    titleLabel.minimumScaleFactor = 0.75
    let home = view.window?.safeAreaInsets.bottom ?? 34
    grid.contentInset = UIEdgeInsets(
      top: view.safeAreaInsets.top + (showsInterval ? subtitleHeight - 4 : 4), left: 0,
      bottom: home + 72, right: 0)
    let frame = CGRect(
      x: 0, y: view.bounds.height - home - 60, width: view.bounds.width, height: 44)
    browsingControls.frame = frame
    if selectionControls.superview === view {
      selectionControls.frame = frame
    }
    libraryButton.frame = CGRect(x: 16, y: 0, width: 50, height: 50)
    periodSurface.frame = CGRect(x: 78, y: 0, width: view.bounds.width - 94, height: 50)
    if dock.superview === periodSurface.contentView {
      dock.frame = periodSurface.bounds.insetBy(dx: 4, dy: 4)
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
  }
  func updateHeaderFade() {
    let canvas = UIColor(DuckColors.canvas)
    headerFade.colors = [
      canvas.withAlphaComponent(0.98).cgColor,
      canvas.withAlphaComponent(0.96).cgColor, canvas.withAlphaComponent(0).cgColor,
    ]
    headerFade.locations = [0, 0.8, 1]
  }
  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      updateHeaderFade()
    }
  }
  func replaceAssets(_ values: [CalendarGridAsset]) {
    let remembered = focusedAsset()
    stopRange(revert: false)
    stopMotion()
    geometryWork?.cancel()
    geometryVersion = UUID()
    geometryCache = [:]
    assets = values
    coverIndices = [:]
    transitionImages.removeAllObjects()
    denseDateLabels = [:]
    subtitleRange = nil
    subtitleAtRecentEdge = nil
    width = 0
    hasPosition = false
    if isViewLoaded {
      rebuildIfNeeded()
      if let remembered, let index = assets.firstIndex(where: { $0.id == remembered }) {
        locateAsset(index)
        hasPosition = true
      }
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
    if level == .all, columns >= 10, !selecting, layout.geometry.tiles.indices.contains(path.item) {
      let cell =
        view.dequeueReusableCell(withReuseIdentifier: "calendar.dense", for: path)
        as! CalendarDenseCell
      let asset = assets[layout.geometry.tiles[path.item].asset]
      cell.assetID = asset.id
      cell.photo.contentMode = originalAspect ? .scaleAspectFit : .scaleAspectFill
      cell.accessibilityIdentifier = "library.asset." + asset.id
      cell.accessibilityLabel = nil
      if let date = asset.date {
        let day = Calendar.current.startOfDay(for: date)
        if denseDateLabels[day] == nil {
          if denseDateLabels.count > 512 { denseDateLabels.removeAll(keepingCapacity: true) }
          denseDateLabels[day] = day.formatted(date: .abbreviated, time: .omitted)
        }
        cell.accessibilityLabel = denseDateLabels[day]
      }
      cell.photo.image = transitionImages.object(forKey: asset.id as NSString)
      cell.cancel = requestImage(
        asset, max(40, layout.frame(path.item).width * view.traitCollection.displayScale)
      ) { [weak self, weak cell] image, _ in
        guard cell?.assetID == asset.id else { return }
        if let image {
          self?.rememberImage(image, for: asset.id)
          cell?.photo.image = image
        }
      }
      return cell
    }
    let cell =
      view.dequeueReusableCell(withReuseIdentifier: "calendar.asset", for: path)
      as! CalendarGridCell
    guard layout.geometry.tiles.indices.contains(path.item) else { return cell }
    let tile = layout.geometry.tiles[path.item]
    let displayed = coverIndices[tile.id] ?? tile.asset
    let asset = assets[displayed]
    cell.coverAsset = displayed
    cell.liveMark.image = asset.live ? UIImage(systemName: "livephoto") : nil
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
    cell.thumbnail(transitionImages.object(forKey: asset.id as NSString), cloud: false)
    cell.cancel = requestImage(
      asset, max(40, layout.frame(path.item).width * view.traitCollection.displayScale)
    ) { [weak self, weak cell] image, cloud in
      guard cell?.assetID == asset.id else { return }
      if let image { self?.rememberImage(image, for: asset.id) }
      cell?.thumbnail(image, cloud: cloud)
    }
    return cell
  }
  func rememberImage(_ image: UIImage, for id: String) {
    let cost =
      image.cgImage.map { $0.bytesPerRow * $0.height }
      ?? Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    transitionImages.setObject(image, forKey: id as NSString, cost: cost)
  }
  func collectionView(
    _ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
    forItemAt path: IndexPath
  ) {
    (cell as? CalendarGridCell)?.cancel?()
    (cell as? CalendarGridCell)?.stopCover()
    (cell as? CalendarDenseCell)?.cancel?()
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
    guard layout.geometry.tiles.indices.contains(path.item) else { return }
    let tile = layout.geometry.tiles[path.item]
    if level != .all {
      changeLevel(
        level == .years ? .months : .all,
        asset: (grid.cellForItem(at: path) as? CalendarGridCell)?.coverAsset ?? tile.asset,
        from: path)
      return
    }
    if selecting {
      toggleAsset(tile.asset)
      return
    }
    if columns > 5 {
      density(columns: 5, at: tile.asset)
      return
    }
    onPreview(assets[tile.asset], grid.convert(layout.frame(path.item), to: nil))
  }
  func focusedAsset() -> String? {
    guard let path = grid.indexPathForItem(at: CGPoint(x: grid.bounds.midX, y: grid.bounds.midY)),
      layout.geometry.tiles.indices.contains(path.item)
    else { return layout.geometry.tiles.last.map { assets[$0.asset].id } }
    return assets[layout.geometry.tiles[path.item].asset].id
  }
  func locateAsset(_ asset: Int) {
    guard let tile = layout.geometry.tiles.firstIndex(where: { $0.members.contains(asset) }) else {
      return
    }
    grid.contentOffset.y = clampedOffset(layout.frame(tile).midY - grid.bounds.height * 0.5)
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
    stopMotion()
    stopCoverPlayback()
    grid.setContentOffset(
      CGPoint(x: 0, y: clampedOffset(.greatestFiniteMagnitude)),
      animated: !UIAccessibility.isReduceMotionEnabled)
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
    }
    let source = grid.indexPathsForVisibleItems.compactMap { path -> Pose? in
      guard let cell = grid.cellForItem(at: path) as? CalendarGridCell,
        let image = cell.image.image, let index = cell.coverAsset
      else { return nil }
      let frame = grid.convert(layout.frame(path.item), to: view)
      guard frame.intersects(view.bounds) else { return nil }
      return Pose(id: cell.assetID, asset: index, frame: frame, image: image)
    }
    let sourceByID = Dictionary(source.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let old = grid.snapshotView(afterScreenUpdates: false)
    level = next
    dock.selectedSegmentIndex = next.rawValue
    layout.level = next
    layout.geometry = geometry()
    navigationController?.setNavigationBarHidden(next != .all, animated: false)
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
      if let nextImage = target?.image.image, target?.assetID != pose.id {
        let replacement = UIImageView(image: nextImage)
        replacement.contentMode = .scaleAspectFill
        replacement.frame = flight.bounds
        replacement.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        replacement.alpha = 0
        flight.addSubview(replacement)
      }
      target?.isHidden = true
      overlay.addSubview(flight)
      flights.append((flight, frame, next == .all ? 0 : 12))
    }
    grid.alpha = 0
    // Unmatched scenes fade in place. Only real matched covers travel.
    let cleanup: () -> Void = { [weak self] in
      guard let self else { return }
      overlay.removeFromSuperview()
      self.motionSourceIDs = []
      self.motionDestinationIDs = []
      for cell in self.grid.visibleCells { cell.isHidden = false }
      self.transitionOverlay = nil
      self.grid.alpha = 1
      self.changing = false
      self.spring = nil
      self.updateChrome()
      self.refreshCoverPlayback()
    }
    if UIAccessibility.isReduceMotionEnabled {
      cleanup()
      return
    }
    let animation = UIViewPropertyAnimator(duration: 0.42, curve: .easeInOut)
    animation.addAnimations {
      matchedOld?.alpha = 0
      self.grid.alpha = 1
      for (flight, frame, radius) in flights {
        flight.frame = frame
        flight.layer.cornerRadius = radius
        if flight.subviews.count > 1 { flight.subviews.last?.alpha = 1 }
      }
    }
    animation.addCompletion { _ in cleanup() }
    spring = animation
    animation.startAnimation()
    updateChrome()
  }

  func stopMotion() {
    spring?.stopAnimation(false)
    spring?.finishAnimation(at: .current)
    spring = nil
    transitionOverlay?.removeFromSuperview()
    transitionOverlay = nil
    changing = false
    zoomRefresh?.cancel()
    zoomRefresh = nil
    if zoomScene != nil {
      zoomScene?.removeFromSuperview()
      zoomScene = nil
      grid.alpha = 1
      subtitleLabel.alpha = 1
      grid.accessibilityElementsHidden = false
      announceDensity()
    }
    grid.panGestureRecognizer.isEnabled = true
  }
  func displayMenu() -> UIMenu {
    let zoomIn = UIAction(
      title: NSLocalizedString("calendar_zoom_in", comment: ""),
      image: UIImage(systemName: "plus.magnifyingglass"), attributes: columns == 1 ? .disabled : []
    ) { [weak self] _ in
      guard let self else { return }
      let i = self.columnStops.firstIndex(of: self.columns) ?? 1
      self.density(columns: self.columnStops[max(0, i - 1)], at: nil)
    }
    let zoomOut = UIAction(
      title: NSLocalizedString("calendar_zoom_out", comment: ""),
      image: UIImage(systemName: "minus.magnifyingglass"),
      attributes: columns == 20 ? .disabled : []
    ) { [weak self] _ in
      guard let self else { return }
      let i = self.columnStops.firstIndex(of: self.columns) ?? 1
      self.density(columns: self.columnStops[min(self.columnStops.count - 1, i + 1)], at: nil)
    }
    let aspect = UIAction(
      title: NSLocalizedString("calendar_original_aspect", comment: ""),
      image: UIImage(systemName: "rectangle"), state: originalAspect ? .on : .off
    ) { [weak self] _ in
      guard let self else { return }
      self.originalAspect.toggle()
      self.density(columns: self.columns, at: nil)
    }
    return UIMenu(
      children: (menu?() ?? []) + [
        UIMenu(
          title: NSLocalizedString("calendar_display_options", comment: ""),
          children: [zoomIn, zoomOut, aspect])
      ])
  }
  func sceneImage() -> UIImage {
    let previousAlpha = grid.alpha
    grid.alpha = 1
    let format = UIGraphicsImageRendererFormat()
    format.scale = min(2, traitCollection.displayScale)
    let image = UIGraphicsImageRenderer(size: grid.bounds.size, format: format).image { _ in
      grid.drawHierarchy(
        in: CGRect(origin: .zero, size: grid.bounds.size), afterScreenUpdates: true)
    }
    grid.alpha = previousAlpha
    return image
  }
  func beginSceneZoom(point: CGPoint? = nil, item: Int? = nil) {
    stopMotion()
    stopCoverPlayback()
    captureAnchor(item: item, point: point)
    zoomStartLevel = level
    zoomTargetLevel = level
    startColumns = columns
    startLeadingSlots = leadingSlots
    zoomStartOffset = grid.contentOffset
    if let anchor, layout.geometry.tiles.indices.contains(anchor) {
      let tile = layout.geometry.tiles[anchor]
      zoomStartAsset = coverIndices[tile.id] ?? tile.asset
      zoomSourceWidth = layout.frame(anchor).width
    }
    let scene = CalendarZoomScene(frame: grid.frame, image: sceneImage(), focus: anchorPoint)
    zoomScene = scene
    zoomInitialWidth = zoomSourceWidth
    zoomFrames = [
      columns: ZoomFrame(image: scene.source.image!, point: anchorPoint, width: zoomSourceWidth)
    ]
    view.insertSubview(scene, aboveSubview: grid)
    grid.panGestureRecognizer.isEnabled = false
    grid.accessibilityElementsHidden = true
    grid.alpha = 0
    changing = true
    grid.accessibilityValue = NSLocalizedString("calendar_zoom_changing", comment: "")
  }
  func prepareZoomDestination(_ next: CalendarGridLevel, columns target: Int) {
    guard let scene = zoomScene else { return }
    zoomRefresh?.cancel()
    zoomTargetLevel = next
    level = next
    columns = target
    if next == .all { anchor = zoomStartAsset }
    leadingSlots = next == .all ? alignedLeadingSlots(columns: target) : 0
    layout.level = next
    layout.geometry = geometry()
    layout.invalidateLayout()
    grid.reloadData()
    grid.layoutIfNeeded()
    anchor = layout.geometry.tiles.firstIndex { $0.members.contains(zoomStartAsset) }
    placeAnchor()
    if next != zoomStartLevel {
      scene.ratio = next.rawValue > zoomStartLevel.rawValue ? 1.6 : 0.65
    } else if let anchor {
      scene.ratio = max(0.1, layout.frame(anchor).width / max(1, zoomSourceWidth))
    }
    scene.destination.image = sceneImage()
    // One early refresh admits already-requested visible posters. There is no
    // per-frame image or layout reconstruction while the fingers are held.
    let refresh = DispatchWorkItem { [weak self, weak scene] in
      guard let self, self.zoomScene === scene, let scene else { return }
      let image = self.sceneImage()
      scene.destination.image = image
      if var cached = self.zoomFrames[self.columns] {
        cached.image = image
        self.zoomFrames[self.columns] = cached
      }
    }
    zoomRefresh = refresh
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: refresh)
  }
  func continuousZoom(scale: CGFloat) {
    guard let scene = zoomScene else { return }
    let desired = zoomInitialWidth * scale
    func side(_ count: Int) -> CGFloat {
      (width - CGFloat(count - 1) * (count >= 10 ? 1 : 2)) / CGFloat(count)
    }
    let sourceIndex = columnStops.lastIndex(where: { side($0) >= desired }) ?? 0
    let destinationIndex = min(columnStops.count - 1, sourceIndex + 1)
    let a = columnStops[sourceIndex]
    let b = columnStops[destinationIndex]
    func frame(_ count: Int) -> ZoomFrame {
      if let cached = zoomFrames[count] { return cached }
      prepareZoomDestination(.all, columns: count)
      let rect = anchor.map { layout.frame($0) } ?? .zero
      let point = CGPoint(
        x: rect.minX + rect.width * anchorFraction.x,
        y: rect.minY + rect.height * anchorFraction.y - grid.contentOffset.y)
      let frame = ZoomFrame(
        image: scene.destination.image ?? scene.source.image!, point: point, width: side(count))
      zoomFrames[count] = frame
      return frame
    }
    if zoomSourceColumns != a || zoomDestinationColumns != b || scene.destination.image == nil {
      let source = frame(a)
      let destination = frame(b)
      zoomSourceColumns = a
      zoomDestinationColumns = b
      scene.faces(
        source: source.image, destination: destination.image,
        sourcePoint: source.point, destinationPoint: destination.point, focus: anchorPoint)
      scene.ratio = destination.width / source.width
      zoomFrames = zoomFrames.filter { $0.key == startColumns || $0.key == a || $0.key == b }
    }
    zoomProgress = a == b ? 1 : min(1, max(0, (desired - side(a)) / (side(b) - side(a))))
    scene.apply(zoomProgress)
    if startColumns <= 5 {
      subtitleLabel.alpha = a >= 10 ? 0 : b > 5 ? 1 - zoomProgress : 1
    }
  }
  func finishSceneZoom(commit: Bool) {
    guard let scene = zoomScene else { return }
    zoomRefresh?.cancel()
    zoomRefresh = nil
    let end: CGFloat
    if commit, zoomStartLevel == .all {
      let target = zoomProgress >= 0.5 ? zoomDestinationColumns : zoomSourceColumns
      end = target == zoomDestinationColumns ? 1 : 0
      // The real collection adopts only the final chosen scene beneath the snapshots.
      let needsCollection = level != .all || columns != target
      level = .all
      columns = target
      anchor = zoomStartAsset
      leadingSlots = alignedLeadingSlots(columns: target)
      layout.level = .all
      layout.geometry = geometry()
      layout.invalidateLayout()
      if needsCollection { grid.reloadData() }
      grid.layoutIfNeeded()
      placeAnchor()
    } else if !commit, let original = zoomFrames[startColumns] {
      let format = UIGraphicsImageRendererFormat()
      format.scale = min(2, traitCollection.displayScale)
      let held = UIGraphicsImageRenderer(size: scene.bounds.size, format: format).image { _ in
        scene.drawHierarchy(in: scene.bounds, afterScreenUpdates: false)
      }
      scene.faces(
        source: held, destination: original.image,
        sourcePoint: anchorPoint, destinationPoint: original.point, focus: anchorPoint)
      scene.ratio = 1
      scene.apply(0)
      end = 1
    } else {
      end = commit ? 1 : 0
    }
    let cleanup: () -> Void = { [weak self] in
      guard let self else { return }
      if !commit {
        self.level = self.zoomStartLevel
        self.columns = self.startColumns
        self.leadingSlots = self.startLeadingSlots
        self.layout.level = self.level
        self.layout.geometry = self.geometry()
        self.layout.invalidateLayout()
        self.grid.reloadData()
        self.grid.layoutIfNeeded()
        self.grid.setContentOffset(self.zoomStartOffset, animated: false)
      }
      self.zoomScene = nil
      self.subtitleLabel.alpha = 1
      self.navigationController?.setNavigationBarHidden(self.level != .all, animated: false)
      self.dock.selectedSegmentIndex = self.level.rawValue
      self.view.layoutIfNeeded()
      if commit { self.placeAnchor() }
      self.grid.alpha = 1
      self.grid.accessibilityElementsHidden = false
      self.grid.panGestureRecognizer.isEnabled = true
      scene.removeFromSuperview()
      self.zoomScene = nil
      self.zoomFrames = [:]
      self.changing = false
      self.spring = nil
      self.announceDensity()
      self.refreshMenu()
      self.updateChrome()
      self.attachNativeAccessory()
      self.refreshCoverPlayback()
    }
    if UIAccessibility.isReduceMotionEnabled {
      scene.apply(end)
      cleanup()
      return
    }
    let settle = UIViewPropertyAnimator(
      duration: 0.28,
      timingParameters:
        UICubicTimingParameters(
          controlPoint1: CGPoint(x: 0.2, y: 0.8), controlPoint2: CGPoint(x: 0.2, y: 1)))
    let settledPoint: CGPoint
    if commit, let anchor {
      let rect = layout.frame(anchor)
      settledPoint = CGPoint(
        x: rect.minX + rect.width * anchorFraction.x,
        y: rect.minY + rect.height * anchorFraction.y - grid.contentOffset.y)
    } else {
      settledPoint = anchorPoint
    }
    settle.addAnimations {
      scene.apply(end)
      scene.source.center = settledPoint
      scene.destination.center = settledPoint
    }
    settle.addCompletion { _ in cleanup() }
    spring = settle
    settle.startAnimation()
  }
  func density(columns target: Int, at item: Int?) {
    guard level == .all, !selecting, !assets.isEmpty else { return }
    beginSceneZoom(item: item)
    prepareZoomDestination(.all, columns: target)
    zoomSourceColumns = startColumns
    zoomDestinationColumns = target
    zoomScene?.apply(0)
    zoomProgress = 1
    finishSceneZoom(commit: true)
  }
  /// Keep the anchor near its screen column instead of translating the entire
  /// destination grid offscreen when its item remainder changes with density.
  /// Only the first row may start partway across; no placeholder assets are added.
  func alignedLeadingSlots(columns: Int) -> Int {
    guard let anchor else { return 0 }
    let gap: CGFloat = columns >= 10 ? 1 : 2
    let side = (width - CGFloat(columns - 1) * gap) / CGFloat(columns)
    let column = min(
      columns - 1, max(0, Int(round((anchorPoint.x - side * anchorFraction.x) / (side + gap)))))
    return (column - anchor % columns + columns) % columns
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
    let i = item ?? grid.indexPathForItem(at: p)?.item ?? grid.indexPathsForVisibleItems.first?.item
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
    grid.contentOffset.y = clampedOffset(f.minY + f.height * anchorFraction.y - anchorPoint.y)
    grid.layoutIfNeeded()
  }
  func announceDensity() {
    grid.accessibilityValue = String(
      format: NSLocalizedString("calendar_grid_columns", comment: ""), columns)
  }
  @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
    guard !selecting, !assets.isEmpty else { return }
    switch gesture.state {
    case .began:
      if gesture.scale < 1 && ((level == .all && columns == columnStops.last) || level == .years) {
        return
      }
      beginSceneZoom(
        point: (gesture as? CalendarPinchGesture)?.focus(in: grid) ?? gesture.location(in: grid))
      zoomProgress = 0
    case .changed:
      guard (gesture as? CalendarPinchGesture)?.focus(in: grid) != nil, let scene = zoomScene else {
        return
      }
      if zoomStartLevel == .all {
        continuousZoom(scale: gesture.scale)
        return
      }
      var next = zoomStartLevel
      var target = startColumns
      let outward = gesture.scale > 1
      if zoomStartLevel == .years {
        if outward { next = .months }
      } else if zoomStartLevel == .months {
        next = outward ? .all : .years
        target = 5
      } else {
        let i = columnStops.firstIndex(of: startColumns) ?? 1
        target = columnStops[min(columnStops.count - 1, max(0, i + (outward ? -1 : 1)))]
      }
      if next != zoomTargetLevel || target != columns || scene.destination.image == nil {
        prepareZoomDestination(next, columns: target)
      }
      if next == zoomStartLevel && target == startColumns {
        zoomProgress = 0
      } else {
        let ratio = scene.ratio
        // A hierarchy change may use a differently shaped cover. Keep its gesture
        // threshold practical without losing the direct scale response.
        let endScale = ratio
        zoomProgress = min(1, max(0, (gesture.scale - 1) / (endScale - 1)))
      }
      scene.apply(zoomProgress)
      if zoomStartLevel == .all && startColumns <= 5 && columns > 5 {
        subtitleLabel.alpha = 1 - zoomProgress
      }
    case .ended, .cancelled, .failed:
      // UIKit's terminal scale can arrive after one touch has ended. The focus
      // remains fixed, so consume scale without consulting a one-finger center.
      if gesture.state == .ended, zoomStartLevel == .all, zoomScene != nil {
        continuousZoom(scale: gesture.scale)
      }
      finishSceneZoom(
        commit: gesture.state == .ended && (zoomStartLevel == .all || zoomProgress > 0.45))
    default: break
    }
  }
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    if !changing {
      updateChrome()
      onVisibleChange()
    }
  }
  func updateChrome() {
    guard isViewLoaded, filterItem != nil, !chromeUpdating else { return }
    chromeUpdating = true
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
      || subtitleIndexing != indexing || subtitleTotal != total
    subtitleIndexing = indexing
    subtitleTotal = total
    subtitleRange = range
    subtitleAtRecentEdge = recent
    if needsSubtitle, level == .all, columns <= 5 {
      if indexing {
        subtitleLabel.text = NSLocalizedString("library_loading", comment: "")
      } else if recent {
        subtitleLabel.text = String(
          format: NSLocalizedString("library_count_compact", comment: ""),
          (displayedTotal ?? assets.count).formatted())
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
    backupItem.isEnabled = canBackup && !selected.isEmpty
    selectionControls.setNeedsLayout()
    updateHeader(animated: true)
    let next: Chrome =
      selecting
      ? .selection : ((!recent || level != .all) && !expandedNavigation ? .browsing : .navigation)
    adoptChrome(next)
  }
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    expandedNavigation = false
    stopCoverPlayback()
  }
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    // Attach while inertia has begun, instead of waiting for deceleration to finish.
    attachNativeAccessory()
  }
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { attachNativeAccessory() }
  func attachNativeAccessory() {
    guard active, !selecting, chrome == .browsing, !installingAccessory else { return }
    if #available(iOS 26.0, *), let tabs = tabBarController {
      if let current = tabs.bottomAccessory {
        if let content = current.contentView as? CalendarAccessoryContent {
          checkAccessoryAfterTransition(content)
        }
        return
      }
      let content = CalendarAccessoryContent(dock)
      let accessory = UITabAccessory(contentView: content)
      content.onEnvironment = { [weak self, weak content] in
        guard let self, let content else { return }
        self.checkAccessoryAfterTransition(content)
      }
      installingAccessory = true
      nativeAccessory = accessory
      dock.alpha = 0
      dock.transform = CGAffineTransform(translationX: 0, y: 16)
      tabs.setBottomAccessory(accessory, animated: !UIAccessibility.isReduceMotionEnabled)
      installingAccessory = false
      UIView.animate(
        withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.28,
        delay: 0, options: [.beginFromCurrentState, .curveEaseOut]
      ) {
        self.dock.alpha = 1
        self.dock.transform = .identity
      }
      checkAccessoryAfterTransition(content)
    }
  }
  @available(iOS 26.0, *)
  func checkAccessoryAfterTransition(_ content: CalendarAccessoryContent) {
    accessoryCheck?.cancel()
    // Installation and native minimization briefly report a regular environment.
    // Do not tear down the very control UIKit is still moving into its inline slot.
    let check = DispatchWorkItem { [weak self, weak content] in
      guard let self, self.active, !self.selecting, let content,
        let tabs = self.tabBarController,
        tabs.bottomAccessory === self.nativeAccessory as? UITabAccessory,
        content.traitCollection.tabAccessoryEnvironment == .regular,
        !self.grid.isDragging, !self.grid.isDecelerating
      else { return }
      tabs.setBottomAccessory(nil, animated: !UIAccessibility.isReduceMotionEnabled)
      self.nativeAccessory = nil
    }
    accessoryCheck = check
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: check)
  }

  func adoptChrome(_ next: Chrome) {
    guard active else { return }
    if #available(iOS 26.0, *), let tabs = tabBarController {
      if tabs.tabBarMinimizeBehavior != .onScrollUp { tabs.tabBarMinimizeBehavior = .onScrollUp }
      if next == .selection {
        accessoryCheck?.cancel()
        if tabs.bottomAccessory != nil { tabs.setBottomAccessory(nil, animated: false) }
        nativeAccessory = nil
        if selectionControls.superview !== view { view.addSubview(selectionControls) }
      } else if chrome == .selection {
        tabs.setBottomAccessory(nil, animated: false)
        nativeAccessory = nil
      }
      if tabs.isTabBarHidden != (next == .selection) {
        tabs.setTabBarHidden(next == .selection, animated: !UIAccessibility.isReduceMotionEnabled)
      }
      browsingControls.isHidden = true
      selectionControls.isHidden = next != .selection
      selectionControls.alpha = 1
      selectionControls.transform = .identity
      chrome = next
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
    chromeMotion?.stopAnimation(false)
    chromeMotion?.finishAnimation(at: .current)
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
    if !selecting && columns > 5 { density(columns: 5, at: nil) }
    if !selecting, level != .all {
      let asset =
        focusedAsset().flatMap { id in assets.firstIndex(where: { $0.id == id }) }
        ?? max(0, assets.count - 1)
      changeLevel(.all, asset: asset, from: nil)
    }
    expandedNavigation = false
    selecting.toggle()
    if !selecting {
      selected = []
      onSelection(selected)
    }
    grid.reloadData()
    updateChrome()
  }
  func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
    if gesture is UILongPressGestureRecognizer {
      return gesture.numberOfTouches == 1 && level == .all && !changing
    }
    if gesture is UIPinchGestureRecognizer {
      if selectionStart != nil { stopRange(revert: true) }
      return !selecting
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
      (grid.cellForItem(at: path) as? CalendarGridCell)?.selection(
        selected.contains(assets[layout.geometry.tiles[path.item].asset].id), enabled: selecting)
    }
    updateChrome()
  }
  @objc func rangeSelect(_ gesture: UILongPressGestureRecognizer) {
    guard level == .all else { return }
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
  func reviewSelection() {
    let controller = CalendarSelectedController()
    controller.assets = assets.filter { selected.contains($0.id) }
    controller.selected = selected
    controller.requestImage = requestImage
    controller.onSelection = { [weak self] ids in
      self?.selected = ids
      self?.onSelection(ids)
      self?.refreshSelection()
    }
    let nav = UINavigationController(rootViewController: controller)
    if let sheet = nav.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = false
      sheet.preferredCornerRadius = 24
    }
    present(nav, animated: true)
  }
}
final class CalendarSelectedController: UIViewController, UICollectionViewDataSource,
  UICollectionViewDelegate
{
  var assets: [CalendarGridAsset] = [], selected = Set<String>(),
    requestImage: CalendarGridController.ImageRequest!,
    onSelection: (Set<String>) -> Void = { _ in }
  let flow = UICollectionViewFlowLayout()
  lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: flow)
  let clear = UIButton(type: .system)
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(DuckColors.canvas)
    flow.minimumLineSpacing = 2
    flow.minimumInteritemSpacing = 2
    grid.dataSource = self
    grid.delegate = self
    grid.backgroundColor = .clear
    grid.register(CalendarGridCell.self, forCellWithReuseIdentifier: "selected")
    grid.accessibilityIdentifier = "calendar.selected_grid"
    view.addSubview(grid)
    navigationItem.title = String(
      format: NSLocalizedString("library_selection_title", comment: ""), selected.count)
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "checkmark"), style: .done, target: self, action: #selector(done))
    clear.setTitle(NSLocalizedString("library_deselect_all", comment: ""), for: .normal)
    if #available(iOS 26.0, *) {
      clear.configuration = .glass()
    } else {
      clear.configuration = .bordered()
    }
    clear.addAction(
      UIAction { [weak self] _ in
        self?.selected = []
        self?.onSelection([])
        self?.grid.reloadData()
        self?.navigationItem.title = String(
          format: NSLocalizedString("library_selection_title", comment: ""), 0)
      }, for: .touchUpInside)
    view.addSubview(clear)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let side = (view.bounds.width - 8) / 5
    flow.itemSize = CGSize(width: side, height: side)
    grid.frame = view.bounds
    grid.contentInset.bottom = 90
    clear.frame = CGRect(
      x: view.bounds.midX - 80, y: view.bounds.height - view.safeAreaInsets.bottom - 65, width: 160,
      height: 48)
  }
  func collectionView(_ v: UICollectionView, numberOfItemsInSection s: Int) -> Int { assets.count }
  func collectionView(_ v: UICollectionView, cellForItemAt p: IndexPath) -> UICollectionViewCell {
    let c = v.dequeueReusableCell(withReuseIdentifier: "selected", for: p) as! CalendarGridCell
    let a = assets[p.item]
    c.assetID = a.id
    c.label.isHidden = true
    c.scrim.isHidden = true
    c.selection(selected.contains(a.id), enabled: true)
    c.cancel = requestImage(a, 250) { [weak c] image, cloud in
      if c?.assetID == a.id { c?.thumbnail(image, cloud: cloud) }
    }
    return c
  }
  func collectionView(_ v: UICollectionView, didSelectItemAt p: IndexPath) {
    let id = assets[p.item].id
    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    onSelection(selected)
    v.reloadItems(at: [p])
    navigationItem.title = String(
      format: NSLocalizedString("library_selection_title", comment: ""), selected.count)
  }
  @objc func done() { dismiss(animated: true) }
}

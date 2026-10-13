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
        while cursor < days.count {
          let remaining = days.count - cursor
          let count = remaining >= 3 ? 3 : remaining
          for slot in 0..<count {
            let day = days[cursor + slot]
            let cover = day.1.upperBound - 1
            let label = day.0.map { $0.formatted(.dateTime.day()) } ?? "—"
            let rect: CGRect
            if count == 3 {
              rect =
                slot == 0
                ? CGRect(x: 20, y: y, width: unit * 2 + 6, height: unit * 2 + 6)
                : CGRect(
                  x: 32 + unit * 2, y: y + CGFloat(slot - 1) * (unit + 6), width: unit, height: unit
                )
            } else {
              rect = CGRect(
                x: 20 + CGFloat(slot)
                  * ((width - 40 - CGFloat(count - 1) * 6) / CGFloat(count) + 6), y: y,
                width: (width - 40 - CGFloat(count - 1) * 6) / CGFloat(count),
                height: count == 1 ? (width - 40) * 0.65 : unit * 1.6)
            }
            tiles.append(
              CalendarGridTile(
                id: "day:\(cover)", asset: cover, members: day.1, label: label, frame: rect))
          }
          y += count == 3 ? unit * 2 + 22 : (count == 1 ? (width - 40) * 0.65 : unit * 1.6) + 16
          cursor += count
        }
        y += 16
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
  var source: CalendarGridGeometry?
  var progress: CGFloat = 1
  var translationX: CGFloat = 0
  var level = CalendarGridLevel.all
  func frame(_ i: Int) -> CGRect {
    guard geometry.tiles.indices.contains(i) else { return .zero }
    let b = geometry.tiles[i].frame
    guard let source, source.tiles.indices.contains(i) else {
      return b.offsetBy(dx: translationX, dy: 0)
    }
    let a = source.tiles[i].frame
    let t = progress
    return CGRect(
      x: a.minX + (b.minX - a.minX) * t + translationX, y: a.minY + (b.minY - a.minY) * t,
      width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
  }
  func freeze() -> CalendarGridGeometry {
    var copy = geometry
    for i in copy.tiles.indices {
      let old = copy.tiles[i]
      copy.tiles[i] = CalendarGridTile(
        id: old.id, asset: old.asset, members: old.members, label: old.label,
        frame: frame(i).offsetBy(dx: -translationX, dy: 0))
    }
    copy.height = collectionViewContentSize.height
    copy.maximumTileHeight = copy.tiles.map { $0.frame.height }.max() ?? 1
    return copy
  }
  override var collectionViewContentSize: CGSize {
    CGSize(
      width: collectionView?.bounds.width ?? 1,
      height: source.map { $0.height + (geometry.height - $0.height) * progress } ?? geometry.height
    )
  }
  override func layoutAttributesForItem(at path: IndexPath) -> UICollectionViewLayoutAttributes? {
    guard geometry.tiles.indices.contains(path.item) else { return nil }
    let a = UICollectionViewLayoutAttributes(forCellWith: path)
    a.frame = frame(path.item)
    return a
  }
  override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]?
  {
    let indices: Range<Int>
    if source != nil {
      let maxHeight = max(geometry.maximumTileHeight, source?.maximumTileHeight ?? 1)
      var low = 0
      var high = geometry.tiles.count
      while low < high {
        let mid = (low + high) / 2
        if frame(mid).minY < rect.minY - maxHeight { low = mid + 1 } else { high = mid }
      }
      let first = low
      high = geometry.tiles.count
      while low < high {
        let mid = (low + high) / 2
        if frame(mid).minY < rect.maxY { low = mid + 1 } else { high = mid }
      }
      indices = first..<max(first, low)
    } else {
      indices = geometry.visible(in: rect)
    }
    var out = indices.compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    if source == nil {
      for i in geometry.headings.indices {
        if let a = heading(i), a.frame.intersects(rect) { out.append(a) }
      }
    }
    return out
  }
  func heading(_ i: Int) -> UICollectionViewLayoutAttributes? {
    guard geometry.headings.indices.contains(i) else { return nil }
    let a = UICollectionViewLayoutAttributes(
      forSupplementaryViewOfKind: Self.headingKind, with: IndexPath(item: i, section: 0))
    a.frame = geometry.headings[i].1
    if let view = collectionView {
      let next =
        i + 1 < geometry.headings.count
        ? geometry.headings[i + 1].1.minY : CGFloat.greatestFiniteMagnitude
      a.frame.origin.y = min(
        next - a.frame.height - 4,
        max(a.frame.minY, view.bounds.minY + view.adjustedContentInset.top + 4))
    }
    a.zIndex = 30
    return a
  }
  override func layoutAttributesForSupplementaryView(ofKind kind: String, at path: IndexPath)
    -> UICollectionViewLayoutAttributes?
  { heading(path.item) }
  override func shouldInvalidateLayout(forBoundsChange bounds: CGRect) -> Bool { true }
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
    label.textColor = .label
    label.accessibilityIdentifier = "calendar.date_badge"
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
  var cancel: (() -> Void)?, assetID = ""
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
    check.tintColor = UIColor(DuckColors.action)
    check.backgroundColor = .white
    check.layer.cornerRadius = 11
    check.clipsToBounds = true
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
    placeholder.frame = CGRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32)
    scrim.frame = CGRect(x: 0, y: 0, width: bounds.width, height: min(110, bounds.height))
    label.frame = CGRect(x: 16, y: 12, width: max(1, bounds.width - 32), height: 32)
    check.frame = CGRect(x: bounds.width - 29, y: bounds.height - 29, width: 23, height: 23)
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
    check.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
    check.isHidden = !enabled || !selected
    image.alpha = selected ? 0.72 : 1
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
  var thumbnailModeIsDense = false
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
  var spring: UIViewPropertyAnimator?, transitionOverlay: UIView?, displayLink: CADisplayLink?
  var morphStarted: CFTimeInterval = 0, morphDuration: CFTimeInterval = 0.35, releaseX: CGFloat = 0
  var anchor: Int?, anchorFraction = CGPoint(x: 0.5, y: 0.5), anchorPoint = CGPoint.zero
  var leadingSlots = 0, startLeadingSlots = 0
  var startColumns = 3, pinchSource: CalendarGridGeometry?, pinchDestination: CalendarGridGeometry?,
    pinchTarget = 3
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
  let columnStops = [1, 3, 5, 10, 20, 30]
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
      for: .systemFont(ofSize: 15, weight: .semibold), maximumPointSize: 20)
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
      title: NSLocalizedString("select", comment: ""), style: .plain, target: self,
      action: #selector(toggleSelection))
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
    stopRange(revert: true)
    chromeMotion?.stopAnimation(true)
    chromeMotion = nil
    if tabOwner?.selectedViewController !== contentOwner { restoreNavigation() }
  }
  func restoreNavigation() {
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
      x: 16, y: view.safeAreaInsets.top + 2,
      width: view.bounds.width - 32, height: subtitleHeight)
    headerBackdrop.frame = CGRect(
      x: 0, y: 0, width: view.bounds.width,
      height: subtitleLabel.frame.maxY + 16)
    headerFade.frame = headerBackdrop.bounds
    headerBackdrop.isHidden = level != .all
    subtitleLabel.isHidden = level != .all
    updateHeaderFade()
    titleLabel.adjustsFontSizeToFitWidth = true
    titleLabel.minimumScaleFactor = 0.75
    let home = view.window?.safeAreaInsets.bottom ?? 34
    grid.contentInset = UIEdgeInsets(
      top: view.safeAreaInsets.top + (level == .all ? subtitleHeight + 8 : 4), left: 0,
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
    layout.source = nil
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
    let asset = assets[tile.asset]
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
    (cell as? CalendarDenseCell)?.cancel?()
  }
  func collectionView(
    _ view: UICollectionView, viewForSupplementaryElementOfKind kind: String, at path: IndexPath
  ) -> UICollectionReusableView {
    let h =
      view.dequeueReusableSupplementaryView(
        ofKind: kind, withReuseIdentifier: "calendar.heading", for: path) as! CalendarGlassHeading
    if layout.geometry.headings.indices.contains(path.item) {
      h.label.text = layout.geometry.headings[path.item].0
      h.setNeedsLayout()
    }
    return h
  }
  func collectionView(_ view: UICollectionView, didSelectItemAt path: IndexPath) {
    guard layout.geometry.tiles.indices.contains(path.item) else { return }
    let tile = layout.geometry.tiles[path.item]
    if level != .all {
      changeLevel(level == .years ? .months : .all, asset: tile.asset, from: path)
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
    // An interruption begins from the visible pose; a cover drill removes the
    // source and destination images from the scenes while one image travels.
    let interrupted = changing
    var old = interrupted ? grid.snapshotView(afterScreenUpdates: false) : nil
    let oldFrame = from.map { grid.convert(layout.frame($0.item), to: view) }
    stopMotion()
    changing = true
    let oldCell = from.flatMap { grid.cellForItem(at: $0) as? CalendarGridCell }
    let poster = interrupted ? nil : oldCell?.image.image
    if old == nil {
      oldCell?.isHidden = poster != nil
      old = grid.snapshotView(afterScreenUpdates: true)
      oldCell?.isHidden = false
    }
    let oldPosition =
      oldFrame ?? CGRect(x: view.bounds.midX - 40, y: view.bounds.midY - 40, width: 80, height: 80)
    level = next
    dock.selectedSegmentIndex = next.rawValue
    layout.level = next
    layout.geometry = geometry()
    layout.source = nil
    layout.invalidateLayout()
    navigationController?.setNavigationBarHidden(next != .all, animated: false)
    grid.reloadData()
    view.layoutIfNeeded()
    grid.layoutIfNeeded()
    locateAsset(asset)
    let targetPath = layout.geometry.tiles.firstIndex(where: { $0.members.contains(asset) }).map {
      IndexPath(item: $0, section: 0)
    }
    let destination =
      targetPath.map { grid.convert(layout.frame($0.item), to: view) } ?? oldPosition
    let targetCell = targetPath.flatMap { grid.cellForItem(at: $0) as? CalendarGridCell }
    let targetID = targetCell?.assetID
    targetCell?.isHidden = poster != nil
    let flight = poster.map { UIImageView(image: $0) }
    flight?.contentMode = .scaleAspectFill
    flight?.clipsToBounds = true
    flight?.frame = oldPosition
    flight?.layer.cornerRadius = 12
    if let old {
      old.isUserInteractionEnabled = false
      old.frame = grid.frame
      view.insertSubview(old, aboveSubview: grid)
      transitionOverlay = old
    }
    if let flight { view.insertSubview(flight, aboveSubview: old ?? grid) }
    grid.alpha = 0
    grid.transform = CGAffineTransform(
      scaleX: next.rawValue > 0 ? 0.94 : 1.04, y: next.rawValue > 0 ? 0.94 : 1.04)
    let cleanup: () -> Void = { [weak self, weak targetCell] in
      old?.removeFromSuperview()
      flight?.removeFromSuperview()
      if targetCell?.assetID == targetID { targetCell?.isHidden = false }
      self?.transitionOverlay = nil
      self?.grid.transform = .identity
      self?.grid.alpha = 1
      self?.changing = false
      self?.spring = nil
      self?.updateChrome()
    }
    if UIAccessibility.isReduceMotionEnabled {
      cleanup()
      return
    }
    let animation = UIViewPropertyAnimator(duration: 0.46, dampingRatio: 0.92)
    animation.addAnimations {
      old?.alpha = 0
      self.grid.alpha = 1
      self.grid.transform = .identity
      flight?.frame = destination
      flight?.layer.cornerRadius = next == .all ? 0 : 12
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
    displayLink?.invalidate()
    displayLink = nil
    changing = false
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
      attributes: columns == 30 ? .disabled : []
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
  func density(columns target: Int, at item: Int?) {
    guard level == .all, !selecting, !assets.isEmpty else { return }
    stopMotion()
    thumbnailModeIsDense = columns >= 10
    captureAnchor(item: item)
    let frozen = layout.freeze()
    releaseX = layout.translationX
    columns = target
    leadingSlots = alignedLeadingSlots(columns: target)
    grid.accessibilityValue = NSLocalizedString("calendar_zoom_changing", comment: "")
    layout.geometry = geometry()
    layout.source = frozen
    layout.progress = 0
    startSettle()
    refreshMenu()
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
  func startSettle() {
    morphStarted = CACurrentMediaTime()
    morphDuration = 0.38
    if UIAccessibility.isReduceMotionEnabled {
      layout.progress = 1
      finishDensity()
      return
    }
    let link = CADisplayLink(target: self, selector: #selector(settleFrame))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }
  @objc func settleFrame() {
    let t = min(1, (CACurrentMediaTime() - morphStarted) / morphDuration)
    let k = 8.0
    let e = (1 - (1 + k * t) * exp(-k * t)) / (1 - (1 + k) * exp(-k))
    layout.progress = CGFloat(e)
    layout.translationX = releaseX * (1 - CGFloat(e))
    layout.invalidateLayout()
    placeAnchor()
    if t >= 1 { finishDensity() }
  }
  func finishDensity() {
    displayLink?.invalidate()
    displayLink = nil
    layout.source = nil
    layout.translationX = 0
    layout.progress = 1
    layout.invalidateLayout()
    // A density settle is a layout update, not new media. Only replace cells
    // when crossing the lightweight mosaic boundary; seed them with loaded pixels.
    if thumbnailModeIsDense != (columns >= 10) { grid.reloadData() }
    grid.panGestureRecognizer.isEnabled = true
    grid.layoutIfNeeded()
    // UICollectionView may adjust its offset when rebuilt cells adopt the final
    // row geometry. Reapply the same tracked anchor after that adjustment.
    placeAnchor()
    announceDensity()
    updateChrome()
    attachNativeAccessory()
  }
  func announceDensity() {
    grid.accessibilityValue = String(
      format: NSLocalizedString("calendar_grid_columns", comment: ""), columns)
  }
  @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
    guard level == .all, !selecting else { return }
    switch gesture.state {
    case .began:
      stopMotion()
      thumbnailModeIsDense = columns >= 10
      // Pinch owns scale only. Stop scroll/deceleration and retain its initial
      // focal point; moving two fingers together must not drag a canvas.
      grid.setContentOffset(grid.contentOffset, animated: false)
      grid.panGestureRecognizer.isEnabled = false
      captureAnchor(
        point: (gesture as? CalendarPinchGesture)?.focus(in: grid) ?? gesture.location(in: grid))
      startColumns = columns
      startLeadingSlots = leadingSlots
      grid.accessibilityValue = NSLocalizedString("calendar_zoom_changing", comment: "")
      pinchTarget = columns
      pinchDestination = nil
      pinchSource = layout.freeze()
    case .changed:
      guard (gesture as? CalendarPinchGesture)?.focus(in: grid) != nil,
        !UIAccessibility.isReduceMotionEnabled,
        let source = pinchSource
      else { return }
      let target =
        gesture.scale < 1
        ? columnStops[
          min(columnStops.count - 1, (columnStops.firstIndex(of: startColumns) ?? 1) + 1)]
        : columnStops[max(0, (columnStops.firstIndex(of: startColumns) ?? 1) - 1)]
      if pinchTarget != target || pinchDestination == nil {
        pinchTarget = target
        let old = columns
        let oldLeading = leadingSlots
        columns = target
        leadingSlots = alignedLeadingSlots(columns: target)
        pinchDestination = geometry()
        columns = old
        leadingSlots = oldLeading
      }
      guard let destination = pinchDestination else { return }
      layout.source = source
      layout.geometry = destination
      let a = source.tiles.first?.frame.width ?? 1
      let b = destination.tiles.first?.frame.width ?? 1
      let desired = a * gesture.scale
      layout.progress = a == b ? 0 : min(1, max(0, (desired - a) / (b - a)))
      layout.translationX = 0
      layout.invalidateLayout()
      placeAnchor()
    case .ended, .cancelled, .failed:
      let index = columnStops.firstIndex(of: startColumns) ?? 1
      let reducedTarget =
        gesture.scale < 0.85
        ? columnStops[min(columnStops.count - 1, index + 1)]
        : gesture.scale > 1.15 ? columnStops[max(0, index - 1)] : startColumns
      let target =
        gesture.state != .ended
        ? startColumns
        : UIAccessibility.isReduceMotionEnabled
          ? reducedTarget : layout.progress > 0.45 ? pinchTarget : startColumns
      let frozen = layout.freeze()
      releaseX = layout.translationX
      columns = target
      leadingSlots =
        target == startColumns
        ? startLeadingSlots
        : (pinchDestination?.leadingSlots ?? alignedLeadingSlots(columns: target))
      layout.geometry = geometry()
      layout.source = frozen
      layout.progress = 0
      pinchSource = nil
      pinchDestination = nil
      startSettle()
      refreshMenu()
    default: break
    }
  }
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    if !changing, pinchSource == nil, displayLink == nil {
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
    let visible = grid.indexPathsForVisibleItems.compactMap { path -> Int? in
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
    if needsSubtitle {
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
      selected.isEmpty
        ? NSLocalizedString("calendar_select_items", comment: "")
        : String(format: NSLocalizedString("calendar_show_selected", comment: ""), selected.count),
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
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { expandedNavigation = false }
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
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
      tabs.setBottomAccessory(accessory, animated: !UIAccessibility.isReduceMotionEnabled)
      installingAccessory = false
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
      return gesture.numberOfTouches == 1 && level == .all && displayLink == nil && !changing
    }
    if gesture is UIPinchGestureRecognizer {
      if selectionStart != nil { stopRange(revert: true) }
      return level == .all && !selecting
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

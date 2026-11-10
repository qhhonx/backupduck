import Foundation
import Photos
import SwiftUI

enum LibraryViewMode: String, CaseIterable, Identifiable {
  case all, days, months
  var id: String { rawValue }
  var title: String { "library_view_" + rawValue }
}
struct LibraryTimelineGeometry {
  struct Header { let firstItem: Int; let title: String; let frame: CGRect }
  static func cellSide(width: CGFloat, columns: Int, inset: CGFloat, gap: CGFloat,
    fillsWidth: Bool = false) -> CGFloat {
    let side = (width - inset * 2 - CGFloat(columns - 1) * gap) / CGFloat(columns)
    return max(1, fillsWidth ? side : floor(side))
  }
  var items: [CGRect] = []
  var headers: [Header] = []
  var height: CGFloat = 0
  #if os(macOS)
  var macCaptions = MacTimelineCaptions()
  #endif
  init(dates: [Date?], mode: LibraryViewMode, width: CGFloat, target: CGFloat,
    inset: CGFloat, gap: CGFloat, headerHeight: CGFloat, calendar: Calendar = .current, columns requestedColumns: Int? = nil,
    leadingSlots: Int = 0, sectionTitles: [Int: String]? = nil, sectionHeaderHeights: [Int: CGFloat] = [:],
    fillsWidth: Bool = false) {
    let columns = requestedColumns ?? max(mode == .months ? 7 : 3, Int((width - inset * 2 + gap) / (target + gap)))
    let side = Self.cellSide(width: width, columns: columns, inset: inset, gap: gap, fillsWidth: fillsWidth)
    // Empty slots before the first photo keep a focal photo in its column across
    // a density change, so no whole column slides on screen.
    var y: CGFloat = 4, column = mode == .all ? leadingSlots % max(1, columns) : 0, previous: Date?, hasGroup = false
    for (i, date) in dates.enumerated() {
      let group = date.flatMap { mode == .months ? calendar.dateInterval(of: .month, for: $0)?.start : calendar.startOfDay(for: $0) }
      if let title = sectionTitles?[i] {
        if column > 0 { y += side + gap; column = 0 }
        let height = sectionHeaderHeights[i] ?? headerHeight
        headers.append(Header(firstItem: i, title: title, frame: CGRect(x: inset, y: y, width: max(0, width - inset * 2), height: height)))
        y += height
      }
      if mode != .all, !hasGroup || group != previous {
        if column > 0 { y += side + gap; column = 0 }
        let title = group.map { mode == .months ? $0.formatted(.dateTime.year().month(.wide)) : $0.formatted(date: .long, time: .omitted) }
          ?? NSLocalizedString("design_capture_unknown", comment: "")
        headers.append(Header(firstItem: i, title: title, frame: CGRect(x: inset, y: y, width: max(0, width - inset * 2), height: headerHeight)))
        y += headerHeight; previous = group; hasGroup = true
      }
      items.append(CGRect(x: inset + CGFloat(column) * (side + gap), y: y, width: side, height: side))
      column += 1
      if column == columns { y += side + gap; column = 0 }
    }
    height = y + (column > 0 ? side : 0) + 16
  }
  /// Binary search by row position; the grid does not scan every asset per frame.
  func visibleItems(in rect: CGRect) -> Range<Int> {
    var lower = 0, upper = items.count
    while lower < upper { let middle = (lower + upper) / 2; if items[middle].maxY <= rect.minY { lower = middle + 1 } else { upper = middle } }
    let start = lower; upper = items.count
    while lower < upper { let middle = (lower + upper) / 2; if items[middle].minY < rect.maxY { lower = middle + 1 } else { upper = middle } }
    return start..<max(start, lower)
  }
  func visibleHeaders(in rect: CGRect) -> Range<Int> {
    var lower = 0, upper = headers.count
    while lower < upper { let middle = (lower + upper) / 2; if headers[middle].frame.maxY <= rect.minY { lower = middle + 1 } else { upper = middle } }
    let start = lower; upper = headers.count
    while lower < upper { let middle = (lower + upper) / 2; if headers[middle].frame.minY < rect.maxY { lower = middle + 1 } else { upper = middle } }
    return start..<max(start, lower)
  }

}

enum LibraryMotion {
  static func interpolate(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: a.minX+(b.minX-a.minX)*t, y: a.minY+(b.minY-a.minY)*t, width: a.width+(b.width-a.width)*t, height: a.height+(b.height-a.height)*t)
  }
  static func easeOut(_ progress: CGFloat) -> CGFloat {
    let x = min(1,max(0,progress))
    var low: CGFloat = 0, high: CGFloat = 1
    for _ in 0..<14 {
      let t = (low+high)/2, v = 3*(1-t)*(1-t)*t*0.2 + 3*(1-t)*t*t*0.2 + t*t*t
      if v < x { low = t } else { high = t }
    }
    let t = (low+high)/2
    return 3*(1-t)*(1-t)*t*0.8 + 3*(1-t)*t*t + t*t*t
  }
  /// Critically damped settling: gesture updates stay linear; released geometry
  /// accelerates/decelerates without the sharp early jump of the old cubic.
  static func settle(_ progress: CGFloat) -> CGFloat {
    let t = Double(min(1,max(0,progress))), frequency = 7.0
    let value = 1-(1+frequency*t)*exp(-frequency*t)
    let end = 1-(1+frequency)*exp(-frequency)
    return CGFloat(value/end)
  }
  static func visibleRange(count: Int, in rect: CGRect, frame: (Int) -> CGRect) -> Range<Int> {
    var low = 0, high = count
    while low < high { let middle = (low+high)/2; if frame(middle).maxY <= rect.minY { low = middle+1 } else { high = middle } }
    let first = low; high = count
    while low < high { let middle = (low+high)/2; if frame(middle).minY < rect.maxY { low = middle+1 } else { high = middle } }
    return first..<max(first,low)
  }
}
#if os(macOS)
import AppKit

/// A folder's identity occupies its existing summary row exactly once. The
/// overlay uses that same measured row while the rest of the summary scrolls.
struct MacTimelineFolder: Equatable {
  let id: String
  let title: String
  let identityHeight: CGFloat
}

struct MacTimelineCaption {
  enum Kind: String, CaseIterable {
    case date = "library.timeline.header"
    case summary = "library.timeline.summary"
    case folder = "library.timeline.folder"
    var zIndex: Int { self == .folder ? 30 : self == .date ? 20 : 10 }
  }
  struct ID: Hashable { let kind: Kind; let value: String }
  struct Address: Hashable { let kind: Kind; let firstItem: Int }
  let id: ID
  let firstItem: Int
  let title: String
  var frame: CGRect
  var parent: ID?
  var next: ID?
  var boundary: ID?
  var address: Address { Address(kind: id.kind, firstItem: firstItem) }
}

/// Both AppKit and the zoom reading plane use these natural rectangles and
/// identical pinning bounds. IDs distinguish repeated dates in different folders.
struct MacTimelineCaptions {
  private(set) var ordered: [MacTimelineCaption] = []
  private(set) var byID: [MacTimelineCaption.ID: MacTimelineCaption] = [:]
  private var addresses: [MacTimelineCaption.Address: MacTimelineCaption.ID] = [:]

  init() {}
  init(geometry: LibraryTimelineGeometry, folders: [Int: MacTimelineFolder], dateIDs: [Int: String], flowHeaders: Set<Int> = []) {
    let starts = folders.keys.sorted()
    var owner: Int?, folderIndex = 0
    var dates: [MacTimelineCaption] = []
    for header in geometry.headers {
      if flowHeaders.contains(header.firstItem) {
        ordered.append(MacTimelineCaption(id: .init(kind: .summary, value: "flow|\(header.firstItem)"),
          firstItem: header.firstItem, title: header.title, frame: header.frame))
        continue
      }
      while folderIndex < starts.count && starts[folderIndex] <= header.firstItem {
        owner = starts[folderIndex]; folderIndex += 1
      }
      let folder = owner.flatMap { folders[$0] }
      let parent = folder.map { MacTimelineCaption.ID(kind: .folder, value: $0.id) }
      let nextFolder = folderIndex < starts.count ? folders[starts[folderIndex]] : nil
      let boundary = nextFolder.map { MacTimelineCaption.ID(kind: .summary, value: $0.id) }
      var dateFrame = header.frame
      if let current = folders[header.firstItem] {
        let summaryHeight = max(0, header.frame.height - 44)
        let summaryFrame = CGRect(x: header.frame.minX, y: header.frame.minY,
          width: header.frame.width, height: summaryHeight)
        ordered.append(MacTimelineCaption(id: .init(kind: .summary, value: current.id),
          firstItem: header.firstItem, title: current.title, frame: summaryFrame))
        ordered.append(MacTimelineCaption(id: .init(kind: .folder, value: current.id),
          firstItem: header.firstItem, title: current.title,
          frame: CGRect(x: summaryFrame.minX, y: summaryFrame.minY,
            width: summaryFrame.width, height: current.identityHeight), boundary: boundary))
        dateFrame.origin.y += summaryHeight; dateFrame.size.height = 44
      }
      let identity = dateIDs[header.firstItem] ?? "\(folder?.id ?? "")|\(header.firstItem)"
      dates.append(MacTimelineCaption(id: .init(kind: .date, value: identity),
        firstItem: header.firstItem, title: header.title, frame: dateFrame, parent: parent, boundary: boundary))
    }
    for index in dates.indices where index + 1 < dates.count {
      // Only a sibling date can push this date; folder handoff uses its summary.
      if dates[index].parent == dates[index + 1].parent { dates[index].next = dates[index + 1].id }
    }
    ordered += dates
    ordered.sort {
      $0.firstItem == $1.firstItem ? $0.id.kind.zIndex < $1.id.kind.zIndex : $0.firstItem < $1.firstItem
    }
    byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
    addresses = Dictionary(uniqueKeysWithValues: ordered.map { ($0.address, $0.id) })
  }
  func caption(kind: MacTimelineCaption.Kind, at firstItem: Int) -> MacTimelineCaption? {
    addresses[.init(kind: kind, firstItem: firstItem)].flatMap { byID[$0] }
  }
  func frame(for caption: MacTimelineCaption, top: CGFloat, width: CGFloat,
    contentBottom: CGFloat, natural: (MacTimelineCaption.ID) -> CGRect?) -> CGRect {
    var frame = natural(caption.id) ?? caption.frame
    frame.origin.x = 0; frame.size.width = width
    guard caption.id.kind != .summary else { return frame }
    let end = caption.boundary.flatMap { natural($0)?.minY }
      ?? (caption.parent != nil || caption.id.kind == .folder ? contentBottom : .greatestFiniteMagnitude)
    if caption.id.kind == .folder {
      frame.origin.y = min(max(frame.minY, top), end - frame.height - 44)
    } else {
      var pin = top
      if let parentID = caption.parent, let parent = byID[parentID] {
        let parentFrame = self.frame(for: parent, top: top, width: width,
          contentBottom: contentBottom, natural: natural)
        pin = parentFrame.maxY
      }
      let sibling = caption.next.flatMap { natural($0)?.minY } ?? .greatestFiniteMagnitude
      frame.origin.y = min(max(frame.minY, pin), min(sibling, end) - frame.height)
    }
    return frame
  }
}

extension LibraryTimelineGeometry {
  mutating func configureMacCaptions(folders: [Int: MacTimelineFolder] = [:], dateIDs: [Int: String] = [:], flowHeaders: Set<Int> = []) {
    macCaptions = MacTimelineCaptions(geometry: self, folders: folders, dateIDs: dateIDs, flowHeaders: flowHeaders)
  }
}
@MainActor final class LibraryTimelineLayout: NSCollectionViewLayout {
  static let headerKind = MacTimelineCaption.Kind.date.rawValue
  static let headerKinds = MacTimelineCaption.Kind.allCases.map(\.rawValue)
  var revision = 0
  var groups: [Int: String] = [:]
  var flowHeaders: Set<Int> = []
  var headerHeights: [Int: CGFloat] = [:]
  var folders: [Int: MacTimelineFolder] = [:]
  var dateIDs: [Int: String] = [:]
  var mode: LibraryViewMode
  var columns: Int
  var target: CGFloat
  var anchorID: String?
  var anchorInset: CGFloat = 0
  private var key = ""
  private var densityPair = ""
  private var datesLoaded = false
  private var dates: [Date?] = []
  private var cached: [String: LibraryTimelineGeometry] = [:]
  private var from = LibraryTimelineGeometry(dates: [], mode: .all, width: 1, target: 135, inset: 2, gap: 2, headerHeight: 44)
  private var to: LibraryTimelineGeometry?
  private var fromHeaders: [Int: LibraryTimelineGeometry.Header] = [:]
  private var toHeaders: [Int: LibraryTimelineGeometry.Header] = [:]
  private var headerIDs: [Int] = []
  private var captionIDs: [MacTimelineCaption.Kind: [MacTimelineCaption.ID]] = [:]
  private(set) var progress: CGFloat = 0
  private(set) var density: CGFloat = 3
  init(mode: LibraryViewMode, target: CGFloat) {
    self.mode = mode; self.target = target; columns = mode == .months ? 7 : 3
    density = CGFloat(columns); super.init()
  }
  /// Photos keeps its column count when the window resizes; set by the host.
  var requestedColumns: Int?
  /// Room under the last row for the newest-edge footer.
  var footerHeight: CGFloat = 0
  /// At or above this many columns the grid is a gapless overview that the host
  /// draws itself; the layout keeps geometry and content size but no cells.
  var denseThreshold = Int.max
  /// Empty slots before the first photo (see `LibraryTimelineGeometry`).
  var leadingSlots = 0 { didSet { if leadingSlots != oldValue { cached.removeAll() } } }
  var isDense: Bool { mode == .all && to == nil && columns >= denseThreshold }
  func columns(for target: CGFloat, mode: LibraryViewMode) -> Int {
    if mode == .all, let requestedColumns { return max(1, requestedColumns) }
    return max(mode == .months ? 7 : 1, Int(((collectionView?.enclosingScrollView?.contentSize.width ?? 1)-4)/(target+2)))
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func prepare() {
    super.prepare(); guard let view = collectionView else { return }
    let count = view.numberOfSections > 0 ? view.numberOfItems(inSection: 0) : 0
    let next = "\(view.enclosingScrollView?.contentSize.width ?? view.bounds.width)|\(count)|\(revision)"
    if key != next {
      // Items are presented oldest first, so the newest edge is at the bottom.
      // All Photos has no date headers: only the count shapes its geometry.
      // Reading every creation date faulted every PHAsset on each reload and
      // held the main thread for a quarter second in a 50k library.
      key = next; densityPair = ""; dates = Array(repeating: nil, count: count); datesLoaded = false; cached.removeAll()
      columns = self.columns(for: target, mode: mode); density = CGFloat(columns)
      from = geometry(mode: mode, columns: columns); to = nil; progress = 0; rebuildHeaders()
    }
  }
  private func geometry(mode: LibraryViewMode, columns: Int) -> LibraryTimelineGeometry {
    let key = "\(mode.rawValue)|\(columns)|\(denseThreshold)|\(leadingSlots)"
    if let geometry = cached[key] { return geometry }
    if mode != .all, !datesLoaded {
      let count = dates.count
      dates = Array(repeating: nil, count: count); datesLoaded = true
    }
    let dense = mode == .all && columns >= denseThreshold
    var geometry = LibraryTimelineGeometry(dates: dates, mode: mode, width: collectionView?.enclosingScrollView?.contentSize.width ?? 1,
      target: 135, inset: dense ? 0 : 2, gap: dense ? 0 : 2, headerHeight: 44, columns: columns,
      leadingSlots: mode == .all && groups.isEmpty ? leadingSlots : 0, sectionTitles: groups.isEmpty ? nil : groups,
      sectionHeaderHeights: headerHeights, fillsWidth: dense)
    geometry.configureMacCaptions(folders: folders, dateIDs: dateIDs, flowHeaders: flowHeaders)
    cached[key] = geometry; return geometry
  }
  func beginMorph(mode: LibraryViewMode, columns: Int) {
    prepare(); densityPair = ""; from = snapshot(); to = geometry(mode: mode, columns: columns); progress = 0; rebuildHeaders()
  }
  func setProgress(_ value: CGFloat) { progress = min(1, max(0, value)); invalidateLayout() }
  func updateDensity(_ value: CGFloat, startMode: LibraryViewMode) {
    prepare(); density = min(40, max(1, value))
    let stops = Array(1...40)
    let low = stops.last { CGFloat($0) <= density } ?? 1
    let high = stops.first { CGFloat($0) >= density } ?? 40
    let lowMode: LibraryViewMode = startMode
    let highMode: LibraryViewMode = startMode
    let pair = "\(low)|\(high)|\(startMode.rawValue)"
    if pair != densityPair {
      densityPair = pair; from = geometry(mode: lowMode, columns: low); to = geometry(mode: highMode, columns: high); rebuildHeaders()
    }
    // Image scale, rather than column count, follows the fingers linearly.
    let a = from.items.first?.width ?? 1, b = to?.items.first?.width ?? 1
    let desired = max(1, ((collectionView?.enclosingScrollView?.contentSize.width ?? 1) - 4 - (density - 1)*2)/density)
    progress = a == b ? 0 : min(1, max(0, (a-desired)/(a-b)))
    invalidateLayout()
  }
  func adopt(mode: LibraryViewMode, columns: Int) {
    densityPair = ""; self.mode = mode; self.columns = columns; density = CGFloat(columns)
    from = geometry(mode: mode, columns: columns); to = nil; progress = 0; rebuildHeaders(); invalidateLayout()
  }
  private func rebuildHeaders() {
    fromHeaders = Dictionary(uniqueKeysWithValues: from.headers.map { ($0.firstItem, $0) })
    toHeaders = Dictionary(uniqueKeysWithValues: (to?.headers ?? from.headers).map { ($0.firstItem, $0) })
    headerIDs = Set(fromHeaders.keys).union(toHeaders.keys).sorted()
    let all = from.macCaptions.byID.merging(to?.macCaptions.byID ?? [:]) { a, _ in a }
    captionIDs = Dictionary(grouping: all.values, by: { $0.id.kind }).mapValues {
      $0.sorted { $0.firstItem < $1.firstItem }.map(\.id)
    }
  }
  private func snapshot() -> LibraryTimelineGeometry {
    guard to != nil else { return from }
    var geometry = from
    geometry.items = (0..<dates.count).map { frame(at: $0) }
    geometry.headers = headerIDs.compactMap { id in
      guard let attributes = header(at: id), attributes.alpha > 0.5 else { return nil }
      return LibraryTimelineGeometry.Header(firstItem: id, title: title(at: id), frame: attributes.frame)
    }
    geometry.height = collectionViewContentSize.height; return geometry
  }
  func frame(at index: Int) -> CGRect {
    guard from.items.indices.contains(index) else { return .zero }
    guard let to, to.items.indices.contains(index) else { return from.items[index] }
    return LibraryMotion.interpolate(from.items[index], to.items[index], progress)
  }
  override var collectionViewContentSize: CGSize {
    CGSize(width: collectionView?.enclosingScrollView?.contentSize.width ?? 0, height: from.height + ((to?.height ?? from.height)-from.height)*progress + footerHeight)
  }
  override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    guard from.items.indices.contains(indexPath.item) else { return nil }
    let result = NSCollectionViewLayoutAttributes(forItemWith: indexPath); result.frame = frame(at: indexPath.item); return result
  }
  func caption(kind: String, at firstItem: Int) -> MacTimelineCaption? {
    guard let role = MacTimelineCaption.Kind(rawValue: kind) else { return nil }
    let preferred = progress < 0.5 ? from.macCaptions : to?.macCaptions ?? from.macCaptions
    return preferred.caption(kind: role, at: firstItem)
      ?? from.macCaptions.caption(kind: role, at: firstItem)
      ?? to?.macCaptions.caption(kind: role, at: firstItem)
  }
  private func naturalCaptionFrame(_ id: MacTimelineCaption.ID) -> CGRect? {
    guard let a = from.macCaptions.byID[id]?.frame ?? to?.macCaptions.byID[id]?.frame else { return nil }
    return LibraryMotion.interpolate(a, to?.macCaptions.byID[id]?.frame ?? a, progress)
  }
  private func captionAttributes(_ id: MacTimelineCaption.ID) -> NSCollectionViewLayoutAttributes? {
    guard let caption = from.macCaptions.byID[id] ?? to?.macCaptions.byID[id], let view = collectionView else { return nil }
    let result = NSCollectionViewLayoutAttributes(forSupplementaryViewOfKind: id.kind.rawValue,
      with: IndexPath(item: caption.firstItem, section: 0))
    let width = max(0, view.enclosingScrollView?.contentSize.width ?? 0)
    if groups.isEmpty {
      result.frame = naturalCaptionFrame(id) ?? caption.frame
      result.frame.origin.x = 0; result.frame.size.width = width
    } else {
      let bottom = (from.items.last?.maxY ?? from.height)
        + ((to?.items.last?.maxY ?? from.items.last?.maxY ?? from.height) - (from.items.last?.maxY ?? from.height)) * progress
      result.frame = from.macCaptions.frame(for: caption,
        top: view.visibleRect.minY + (view.enclosingScrollView?.contentInsets.top ?? 0),
        width: width, contentBottom: bottom, natural: naturalCaptionFrame)
    }
    result.zIndex = id.kind.zIndex
    result.alpha = from.macCaptions.byID[id] == nil ? progress : to != nil && to?.macCaptions.byID[id] == nil ? 1 - progress : 1
    return result
  }
  private func header(at id: Int) -> NSCollectionViewLayoutAttributes? {
    caption(kind: Self.headerKind, at: id).flatMap { captionAttributes($0.id) }
  }
  override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    // AppKit also probes section-only paths while diffing supplementary views.
    guard indexPath.count == 2, let caption = caption(kind: kind, at: indexPath.item) else { return nil }
    return captionAttributes(caption.id)
  }
  override func layoutAttributesForElements(in rect: CGRect) -> [NSCollectionViewLayoutAttributes] {
    if isDense { return [] }
    let items = LibraryMotion.visibleRange(count: from.items.count, in: rect) { frame(at: $0) }
    var result = items.compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    for kind in MacTimelineCaption.Kind.allCases {
      let ids = captionIDs[kind] ?? []
      let visible = LibraryMotion.visibleRange(count: ids.count, in: rect) { captionAttributes(ids[$0])?.frame ?? .zero }
      result += visible.compactMap { captionAttributes(ids[$0]) }
    }
    return result
  }
  func title(at id: Int) -> String { (progress < 0.5 ? fromHeaders[id]?.title ?? toHeaders[id]?.title : toHeaders[id]?.title ?? fromHeaders[id]?.title) ?? "" }
  override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { !groups.isEmpty || newBounds.width != collectionView?.bounds.width }
}
/// The same native reading material carries calendar and source-grid dates.
@MainActor final class MacTimelineReadingSurface: NSVisualEffectView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    material = .headerView; blendingMode = .withinWindow; state = .active
    wantsLayer = true; layer?.masksToBounds = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layout() { super.layout(); layer?.cornerRadius = bounds.height / 2 }
}

@MainActor final class TimelineDateHeader: NSView, NSCollectionViewElement {
  private let label = NSTextField(labelWithString: "")
  private let material = MacTimelineReadingSurface(frame: .zero)
  var floating = false { didSet { material.isHidden = !floating; needsLayout = true } }
  var readingReady: Bool { !label.stringValue.isEmpty && (!floating || material.superview === self && !material.isHidden) }
  override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; label.font = .systemFont(ofSize: 16, weight: .semibold); label.textColor = DuckRole.primaryTextNSColor; addSubview(material); addSubview(label); material.isHidden = true }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layout() {
    super.layout()
    label.frame = bounds
    let inset = CGFloat(DuckSpacing.small)
    material.frame = CGRect(x: -inset, y: -CGFloat(DuckSpacing.xxSmall),
      width: min(bounds.width, ceil(label.intrinsicContentSize.width)) + inset * 2,
      height: bounds.height + CGFloat(DuckSpacing.xxSmall) * 2)
  }
  func setTitle(_ title: String) { label.stringValue = title }
}
#endif

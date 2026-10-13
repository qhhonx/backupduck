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
  var items: [CGRect] = []
  var headers: [Header] = []
  var height: CGFloat = 0
  init(dates: [Date?], mode: LibraryViewMode, width: CGFloat, target: CGFloat,
    inset: CGFloat, gap: CGFloat, headerHeight: CGFloat, calendar: Calendar = .current, columns requestedColumns: Int? = nil) {
    let columns = requestedColumns ?? max(mode == .months ? 7 : 3, Int((width - inset * 2 + gap) / (target + gap)))
    let side = max(1, floor((width - inset * 2 - CGFloat(columns - 1) * gap) / CGFloat(columns)))
    var y: CGFloat = 4, column = 0, previous: Date?, hasGroup = false
    for (i, date) in dates.enumerated() {
      let group = date.flatMap { mode == .months ? calendar.dateInterval(of: .month, for: $0)?.start : calendar.startOfDay(for: $0) }
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
  static func visibleRange(count: Int, in rect: CGRect, frame: (Int) -> CGRect) -> Range<Int> {
    var low = 0, high = count
    while low < high { let middle = (low+high)/2; if frame(middle).maxY <= rect.minY { low = middle+1 } else { high = middle } }
    let first = low; high = count
    while low < high { let middle = (low+high)/2; if frame(middle).minY < rect.maxY { low = middle+1 } else { high = middle } }
    return first..<max(first,low)
  }
}
#if os(iOS)
import UIKit
@MainActor final class LibraryTimelineLayout: UICollectionViewLayout {
  static let headerKind = "library.timeline.header"
  let library: PhotoLibraryModel
  var mode: LibraryViewMode
  var columns: Int
  var anchorID: String?
  var anchorInset: CGFloat = 0
  private var key = ""
  private var densityPair = ""
  private var dates: [Date?] = []
  private var cached: [String: LibraryTimelineGeometry] = [:]
  private var from = LibraryTimelineGeometry(dates: [], mode: .all, width: 1, target: 135, inset: 0, gap: 2, headerHeight: 44)
  private var to: LibraryTimelineGeometry?
  private var fromHeaders: [Int: LibraryTimelineGeometry.Header] = [:]
  private var toHeaders: [Int: LibraryTimelineGeometry.Header] = [:]
  private var headerIDs: [Int] = []
  private(set) var progress: CGFloat = 0
  private(set) var density: CGFloat = 3
  init(library: PhotoLibraryModel, mode: LibraryViewMode) {
    self.library = library; self.mode = mode; columns = mode == .months ? 7 : library.phoneColumns
    density = CGFloat(columns); super.init()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func prepare() {
    super.prepare(); guard let view = collectionView else { return }
    let count = view.numberOfSections > 0 ? view.numberOfItems(inSection: 0) : 0
    let next = "\(view.bounds.width)|\(count)|\(library.generation)|\(UIFont.preferredFont(forTextStyle: .headline).pointSize)"
    if key != next {
      key = next; densityPair = ""; dates = (0..<count).map { library.asset(at: $0)?.creationDate }; cached.removeAll()
      from = geometry(mode: mode, columns: columns); to = nil; progress = 0; rebuildHeaders()
    }
  }
  private func geometry(mode: LibraryViewMode, columns: Int) -> LibraryTimelineGeometry {
    let key = "\(mode.rawValue)|\(columns)"
    if let geometry = cached[key] { return geometry }
    let geometry = LibraryTimelineGeometry(dates: dates, mode: mode, width: collectionView?.bounds.width ?? 1,
      target: 135, inset: 0, gap: 2, headerHeight: max(42, UIFont.preferredFont(forTextStyle: .headline).lineHeight + 20), columns: columns)
    cached[key] = geometry; return geometry
  }
  func beginMorph(mode: LibraryViewMode, columns: Int) {
    prepare(); densityPair = ""; from = snapshot(); to = geometry(mode: mode, columns: columns); progress = 0; rebuildHeaders()
  }
  func setProgress(_ value: CGFloat) { progress = min(1, max(0, value)); invalidateLayout() }
  func updateDensity(_ value: CGFloat, startMode: LibraryViewMode) {
    prepare(); density = min(9, max(3, value))
    let stops = [3, 5, 7, 9]
    let low = stops.last { CGFloat($0) <= density } ?? 3
    let high = stops.first { CGFloat($0) >= density } ?? 9
    let lowMode: LibraryViewMode = low == 3 ? (startMode == .all ? .all : .days) : .months
    let highMode: LibraryViewMode = high == 3 ? lowMode : .months
    let pair = "\(low)|\(high)|\(startMode.rawValue)"
    if pair != densityPair {
      densityPair = pair; from = geometry(mode: lowMode, columns: low); to = geometry(mode: highMode, columns: high); rebuildHeaders()
    }
    // Image scale, rather than column count, follows the fingers linearly.
    let a = from.items.first?.width ?? 1, b = to?.items.first?.width ?? 1
    let desired = max(1, ((collectionView?.bounds.width ?? 1) - (density - 1)*2)/density)
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
    CGSize(width: collectionView?.bounds.width ?? 0, height: from.height + ((to?.height ?? from.height)-from.height)*progress)
  }
  override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    guard from.items.indices.contains(indexPath.item) else { return nil }
    let result = UICollectionViewLayoutAttributes(forCellWith: indexPath); result.frame = frame(at: indexPath.item); return result
  }
  private func header(at id: Int) -> UICollectionViewLayoutAttributes? {
    guard fromHeaders[id] != nil || toHeaders[id] != nil else { return nil }
    let a = fromHeaders[id]?.frame ?? CGRect(x: 16, y: from.items.indices.contains(id) ? from.items[id].minY : 0, width: max(0,(collectionView?.bounds.width ?? 0)-32), height: 0)
    let b = toHeaders[id]?.frame ?? CGRect(x: 16, y: to?.items.indices.contains(id) == true ? to!.items[id].minY : a.minY, width: a.width, height: 0)
    let result = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: Self.headerKind, with: IndexPath(item: id, section: 0))
    result.frame = LibraryMotion.interpolate(a,b,progress)
    result.frame.origin.x = 16; result.frame.size.width = max(0,(collectionView?.bounds.width ?? 0)-32)
    result.alpha = fromHeaders[id] == nil ? progress : toHeaders[id] == nil ? 1-progress
      : fromHeaders[id]?.title == toHeaders[id]?.title ? 1 : abs(1-2*progress)
    return result
  }
  override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    kind == Self.headerKind ? header(at: indexPath.item) : nil
  }
  override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    let items = LibraryMotion.visibleRange(count: from.items.count, in: rect) { frame(at: $0) }
    let headers = LibraryMotion.visibleRange(count: headerIDs.count, in: rect) { header(at: headerIDs[$0])?.frame ?? .zero }
    return items.compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) } + headers.compactMap { header(at: headerIDs[$0]) }
  }
  override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
    guard let index = library.index(of: anchorID), from.items.indices.contains(index), let view = collectionView else { return proposedContentOffset }
    let maximum = max(-view.adjustedContentInset.top, collectionViewContentSize.height-view.bounds.height+view.adjustedContentInset.bottom)
    return CGPoint(x: 0, y: min(maximum, max(-view.adjustedContentInset.top, frame(at: index).minY+anchorInset)))
  }
  func title(at id: Int) -> String { (progress < 0.5 ? fromHeaders[id]?.title ?? toHeaders[id]?.title : toHeaders[id]?.title ?? fromHeaders[id]?.title) ?? "" }
  override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { newBounds.width != collectionView?.bounds.width }
}
@MainActor final class TimelineDateHeader: UICollectionReusableView {
  private let label = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame); label.font = .preferredFont(forTextStyle: .headline)
    label.adjustsFontForContentSizeCategory = true; label.textColor = UIColor(DuckColors.text); addSubview(label)
    label.accessibilityIdentifier = "library.timeline.date"
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layoutSubviews() { super.layoutSubviews(); label.frame = bounds }
  func setTitle(_ title: String) { label.text = title }
}
#else
import AppKit
@MainActor final class LibraryTimelineLayout: NSCollectionViewLayout {
  static let headerKind = "library.timeline.header"
  let library: PhotoLibraryModel
  var mode: LibraryViewMode
  var columns: Int
  var target: CGFloat
  var anchorID: String?
  var anchorInset: CGFloat = 0
  private var key = ""
  private var densityPair = ""
  private var dates: [Date?] = []
  private var cached: [String: LibraryTimelineGeometry] = [:]
  private var from = LibraryTimelineGeometry(dates: [], mode: .all, width: 1, target: 135, inset: 28, gap: 8, headerHeight: 44)
  private var to: LibraryTimelineGeometry?
  private var fromHeaders: [Int: LibraryTimelineGeometry.Header] = [:]
  private var toHeaders: [Int: LibraryTimelineGeometry.Header] = [:]
  private var headerIDs: [Int] = []
  private(set) var progress: CGFloat = 0
  private(set) var density: CGFloat = 3
  init(library: PhotoLibraryModel, mode: LibraryViewMode, target: CGFloat) {
    self.library = library; self.mode = mode; self.target = target; columns = mode == .months ? 7 : 3
    density = CGFloat(columns); super.init()
  }
  func columns(for target: CGFloat, mode: LibraryViewMode) -> Int {
    max(mode == .months ? 7 : 3, Int(((collectionView?.enclosingScrollView?.contentSize.width ?? 1)-48)/(target+8)))
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func prepare() {
    super.prepare(); guard let view = collectionView else { return }
    let count = view.numberOfSections > 0 ? view.numberOfItems(inSection: 0) : 0
    let next = "\(view.enclosingScrollView?.contentSize.width ?? view.bounds.width)|\(count)|\(library.generation)"
    if key != next {
      key = next; densityPair = ""; dates = (0..<count).map { library.asset(at: $0)?.creationDate }; cached.removeAll()
      columns = self.columns(for: target, mode: mode); density = CGFloat(columns)
      from = geometry(mode: mode, columns: columns); to = nil; progress = 0; rebuildHeaders()
    }
  }
  private func geometry(mode: LibraryViewMode, columns: Int) -> LibraryTimelineGeometry {
    let key = "\(mode.rawValue)|\(columns)"
    if let geometry = cached[key] { return geometry }
    let geometry = LibraryTimelineGeometry(dates: dates, mode: mode, width: collectionView?.enclosingScrollView?.contentSize.width ?? 1,
      target: 135, inset: 28, gap: 8, headerHeight: 44, columns: columns)
    cached[key] = geometry; return geometry
  }
  func beginMorph(mode: LibraryViewMode, columns: Int) {
    prepare(); densityPair = ""; from = snapshot(); to = geometry(mode: mode, columns: columns); progress = 0; rebuildHeaders()
  }
  func setProgress(_ value: CGFloat) { progress = min(1, max(0, value)); invalidateLayout() }
  func updateDensity(_ value: CGFloat, startMode: LibraryViewMode) {
    prepare(); density = min(14, max(3, value))
    let stops = Array(3...14)
    let low = stops.last { CGFloat($0) <= density } ?? 3
    let high = stops.first { CGFloat($0) >= density } ?? 14
    let lowMode: LibraryViewMode = low < 7 ? (startMode == .all ? .all : .days) : .months
    let highMode: LibraryViewMode = high < 7 ? lowMode : .months
    let pair = "\(low)|\(high)|\(startMode.rawValue)"
    if pair != densityPair {
      densityPair = pair; from = geometry(mode: lowMode, columns: low); to = geometry(mode: highMode, columns: high); rebuildHeaders()
    }
    // Image scale, rather than column count, follows the fingers linearly.
    let a = from.items.first?.width ?? 1, b = to?.items.first?.width ?? 1
    let desired = max(1, ((collectionView?.enclosingScrollView?.contentSize.width ?? 1) - 56 - (density - 1)*8)/density)
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
    CGSize(width: collectionView?.enclosingScrollView?.contentSize.width ?? 0, height: from.height + ((to?.height ?? from.height)-from.height)*progress)
  }
  override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    guard from.items.indices.contains(indexPath.item) else { return nil }
    let result = NSCollectionViewLayoutAttributes(forItemWith: indexPath); result.frame = frame(at: indexPath.item); return result
  }
  private func header(at id: Int) -> NSCollectionViewLayoutAttributes? {
    guard fromHeaders[id] != nil || toHeaders[id] != nil else { return nil }
    let a = fromHeaders[id]?.frame ?? CGRect(x: 28, y: from.items.indices.contains(id) ? from.items[id].minY : 0, width: max(0,(collectionView?.enclosingScrollView?.contentSize.width ?? 0)-56), height: 0)
    let b = toHeaders[id]?.frame ?? CGRect(x: 28, y: to?.items.indices.contains(id) == true ? to!.items[id].minY : a.minY, width: a.width, height: 0)
    let result = NSCollectionViewLayoutAttributes(forSupplementaryViewOfKind: Self.headerKind, with: IndexPath(item: id, section: 0))
    result.frame = LibraryMotion.interpolate(a,b,progress)
    result.frame.origin.x = 28; result.frame.size.width = max(0,(collectionView?.enclosingScrollView?.contentSize.width ?? 0)-56)
    result.alpha = fromHeaders[id] == nil ? progress : toHeaders[id] == nil ? 1-progress
      : fromHeaders[id]?.title == toHeaders[id]?.title ? 1 : abs(1-2*progress)
    return result
  }
  override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    kind == Self.headerKind ? header(at: indexPath.item) : nil
  }
  override func layoutAttributesForElements(in rect: CGRect) -> [NSCollectionViewLayoutAttributes] {
    let items = LibraryMotion.visibleRange(count: from.items.count, in: rect) { frame(at: $0) }
    let headers = LibraryMotion.visibleRange(count: headerIDs.count, in: rect) { header(at: headerIDs[$0])?.frame ?? .zero }
    return items.compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) } + headers.compactMap { header(at: headerIDs[$0]) }
  }
  func title(at id: Int) -> String { (progress < 0.5 ? fromHeaders[id]?.title ?? toHeaders[id]?.title : toHeaders[id]?.title ?? fromHeaders[id]?.title) ?? "" }
  override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { newBounds.width != collectionView?.bounds.width }
}
@MainActor final class TimelineDateHeader: NSView {
  private let label = NSTextField(labelWithString: "")
  override init(frame: NSRect) { super.init(frame: frame); label.font = .systemFont(ofSize: 16, weight: .semibold); label.textColor = NSColor(DuckColors.text); addSubview(label) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layout() { super.layout(); label.frame = bounds }
  func setTitle(_ title: String) { label.stringValue = title }
}
#endif

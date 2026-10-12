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
    inset: CGFloat, gap: CGFloat, headerHeight: CGFloat, calendar: Calendar = .current) {
    let columns = max(mode == .months ? 5 : 3, Int((width - inset * 2 + gap) / (target + gap)))
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

#if os(iOS)
import UIKit
@MainActor final class LibraryTimelineLayout: UICollectionViewLayout {
  static let headerKind = "library.timeline.header"
  let library: PhotoLibraryModel
  var mode: LibraryViewMode
  var anchorID: String?
  var anchorInset: CGFloat = 0
  private var key = ""
  private var geometry = LibraryTimelineGeometry(dates: [], mode: .all, width: 1, target: 135, inset: 8, gap: 3, headerHeight: 44)
  init(library: PhotoLibraryModel, mode: LibraryViewMode) { self.library = library; self.mode = mode; super.init() }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func prepare() {
    super.prepare(); guard let view = collectionView else { return }
    let count = view.numberOfSections > 0 ? view.numberOfItems(inSection: 0) : 0
    let height = max(44, UIFont.preferredFont(forTextStyle: .headline).lineHeight + 20)
    let next = "\(view.bounds.width)|\(count)|\(library.generation)|\(mode.rawValue)|\(height)"
    guard next != key else { return }; key = next
    geometry = LibraryTimelineGeometry(dates: (0..<count).map { library.asset(at: $0)?.creationDate }, mode: mode,
      width: view.bounds.width, target: mode == .months ? 80 : 135, inset: 8, gap: 3, headerHeight: height)
  }
  override var collectionViewContentSize: CGSize { CGSize(width: collectionView?.bounds.width ?? 0, height: geometry.height) }
  override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    guard geometry.items.indices.contains(indexPath.item) else { return nil }
    let result = UICollectionViewLayoutAttributes(forCellWith: indexPath); result.frame = geometry.items[indexPath.item]; return result
  }
  override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    guard kind == Self.headerKind, geometry.headers.indices.contains(indexPath.item) else { return nil }
    let result = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: indexPath)
    result.frame = geometry.headers[indexPath.item].frame; return result
  }
  override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    let cells = geometry.visibleItems(in: rect).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    return cells + geometry.visibleHeaders(in: rect)
      .compactMap { layoutAttributesForSupplementaryView(ofKind: Self.headerKind, at: IndexPath(item: $0, section: 0)) }
  }
  override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
    guard let index = library.index(of: anchorID), geometry.items.indices.contains(index), let view = collectionView else { return proposedContentOffset }
    if index == 0 && anchorInset <= 0 { return CGPoint(x: proposedContentOffset.x, y: -view.adjustedContentInset.top) }
    let maximum = max(-view.adjustedContentInset.top, geometry.height - view.bounds.height + view.adjustedContentInset.bottom)
    return CGPoint(x: proposedContentOffset.x, y: min(maximum, max(-view.adjustedContentInset.top, geometry.items[index].minY + anchorInset)))
  }
  func title(at index: Int) -> String { geometry.headers.indices.contains(index) ? geometry.headers[index].title : "" }
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
  var target: CGFloat
  private var key = ""
  private var geometry = LibraryTimelineGeometry(dates: [], mode: .all, width: 1, target: 160, inset: 28, gap: 10, headerHeight: 44)
  init(library: PhotoLibraryModel, mode: LibraryViewMode, target: CGFloat) { self.library = library; self.mode = mode; self.target = target; super.init() }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func prepare() {
    super.prepare(); guard let view = collectionView else { return }
    let width = view.enclosingScrollView?.contentSize.width ?? view.bounds.width
    let count = view.numberOfSections > 0 ? view.numberOfItems(inSection: 0) : 0
    let next = "\(width)|\(count)|\(library.generation)|\(mode.rawValue)|\(target)"
    guard next != key else { return }; key = next
    geometry = LibraryTimelineGeometry(dates: (0..<count).map { library.asset(at: $0)?.creationDate }, mode: mode,
      width: width, target: mode == .months ? min(100, target) : target, inset: 28, gap: 10, headerHeight: 44)
  }
  override var collectionViewContentSize: NSSize { NSSize(width: collectionView?.enclosingScrollView?.contentSize.width ?? 0, height: geometry.height) }
  override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    guard geometry.items.indices.contains(indexPath.item) else { return nil }
    let result = NSCollectionViewLayoutAttributes(forItemWith: indexPath); result.frame = geometry.items[indexPath.item]; return result
  }
  override func layoutAttributesForSupplementaryView(ofKind kind: String, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    guard kind == Self.headerKind, geometry.headers.indices.contains(indexPath.item) else { return nil }
    let result = NSCollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: indexPath)
    result.frame = geometry.headers[indexPath.item].frame; return result
  }
  override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
    geometry.visibleItems(in: rect).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
      + geometry.visibleHeaders(in: rect)
        .compactMap { layoutAttributesForSupplementaryView(ofKind: Self.headerKind, at: IndexPath(item: $0, section: 0)) }
  }
  func title(at index: Int) -> String { geometry.headers.indices.contains(index) ? geometry.headers[index].title : "" }
  override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { newBounds.width != collectionView?.bounds.width }
}
@MainActor final class TimelineDateHeader: NSView {
  private let label = NSTextField(labelWithString: "")
  override init(frame: NSRect) { super.init(frame: frame); label.font = .systemFont(ofSize: 16, weight: .semibold); label.textColor = NSColor(DuckColors.text); addSubview(label) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layout() { super.layout(); label.frame = bounds }
  func setTitle(_ title: String) { label.stringValue = title }
}
#endif

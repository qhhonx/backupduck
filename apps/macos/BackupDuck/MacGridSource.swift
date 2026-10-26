import AppKit
import Photos
import SwiftUI

/// Browsing state belongs to a source/view, independently of its membership.
@MainActor final class MacGridScrollState {
  var offset: CGPoint = .zero
  var anchor: String?
  var inset: CGFloat = 0
}

/// The collection owns geometry, gestures, reuse and diffing. A source supplies
/// stable identities and configures an existing cell without replacing its view.
@MainActor protocol MacGridSource: AnyObject {
  var identifiers: [String] { get }
  var contextID: String { get }
  var contentRevision: String { get }
  var membershipReady: Bool { get }
  var groups: [Int: String] { get }
  func introduction(at index: Int) -> AnyView?
  func headerHeights(width: CGFloat) -> [Int: CGFloat]
  var selection: Set<String> { get set }
  var scroll: MacGridScrollState { get }
  var startsAtEnd: Bool { get }
  var zoomStops: [Int] { get }
  var footer: String { get }
  var thumbnails: ThumbnailPipeline? { get }
  var previewPoster: ((String) -> NSImage?)? { get set }
  var previewFrame: ((String) -> CGRect?)? { get set }
  func asset(_ id: String) -> PHAsset?
  func date(_ id: String) -> Date?
  func fact(_ id: String) -> MacThumbnailTables.Fact?
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool)
  func zoomTile(_ id: String, side: CGFloat, scale: CGFloat, originalAspect: Bool) -> NSView
  func preheat(_ ids: [String], pixels: CGFloat)
  func prefill()
  func loadAllIfNeeded()
  func loadAll() async
  func loadMore(visible: [String])
  func refreshMarks(_ cells: [PhotoCell], receiver: String?, revision: String) async
  func saveScroll()
}

extension MacGridSource {
  var membershipReady: Bool { true }
  var groups: [Int: String] { [:] }
  func introduction(at index: Int) -> AnyView? { nil }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] { [:] }
  var startsAtEnd: Bool { false }
  var zoomStops: [Int] { MacLibraryDensity.grid }
  var footer: String { "" }
  var thumbnails: ThumbnailPipeline? { nil }
  func asset(_ id: String) -> PHAsset? { nil }
  func fact(_ id: String) -> MacThumbnailTables.Fact? { nil }
  func preheat(_ ids: [String], pixels: CGFloat) {}
  func prefill() {}
  func loadAllIfNeeded() {}
  func loadAll() async {}
  func loadMore(visible: [String]) {}
  func refreshMarks(_ cells: [PhotoCell], receiver: String?, revision: String) async {}
  func saveScroll() {}
  func zoomTile(_ id: String, side: CGFloat, scale: CGFloat, originalAspect: Bool) -> NSView {
    let tile = MacSourceZoomTile()
    tile.frame.size = NSSize(width: side, height: side)
    configure(tile.cell, id: id, pixels: side * scale, originalAspect: originalAspect)
    tile.cell.isSelected = selection.contains(id)
    return tile
  }
}

/// File-backed sources reuse the production cell, including marks and request
/// cancellation. It remains mounted throughout the native density transition.
@MainActor final class MacSourceZoomTile: NSView {
  let cell = PhotoCell()
  override init(frame: NSRect) {
    super.init(frame: frame); addSubview(cell.view)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func layout() { super.layout(); cell.view.frame = bounds }
  func cancel() { cell.cancel() }
}

struct MacLibraryGrid: View {
  @ObservedObject var library: PhotoLibraryModel
  @ObservedObject var navigation: MacLibraryNavigation
  var preparationRevision: String = ""
  var queueRevision: Int64
  var receiverID: String?
  var columns: Int
  var selecting = true
  var readOnly = false
  var active = true
  var prefillsTables = true
  var preview: (PHAsset) -> Void = { _ in }
  var enterSelection: () -> Void = {}
  var resize: (Int) -> Void = { _ in }
  @StateObject private var storage = MacLibraryGridStorage()
  var body: some View {
    let source = storage.source(for: library)
    MacMediaGrid(source: source, navigation: navigation, preparationRevision: preparationRevision,
      queueRevision: queueRevision, receiverID: receiverID, columns: columns,
      selecting: selecting, readOnly: readOnly, active: active, prefillsTables: prefillsTables,
      preview: { id in if let asset = source.asset(id) { preview(asset) } },
      enterSelection: enterSelection, resize: resize)
  }
}
@MainActor private final class MacLibraryGridStorage: ObservableObject {
  private var current: MacPhotoLibrarySource?
  func source(for library: PhotoLibraryModel) -> MacPhotoLibrarySource {
    if let current, current.library === library { return current }
    let source = MacPhotoLibrarySource(library); current = source; return source
  }
}

@MainActor final class MacPhotoLibrarySource: MacGridSource {
  let library: PhotoLibraryModel
  private var membershipKey = ""
  private var cachedIDs: [String] = []
  private var scrollKey = ""
  private let retainedScroll = MacGridScrollState()
  private var bulkGeneration = -1
  init(_ library: PhotoLibraryModel) { self.library = library }
  var identifiers: [String] {
    let key = "\(library.generation)|\(library.loaded)"
    if membershipKey != key {
      membershipKey = key
      cachedIDs = (0..<library.loaded).reversed().compactMap { library.identifier(at: $0) }
    }
    return cachedIDs
  }
  var contextID: String { "\(library.filter)|\(library.scrollResetGeneration)" }
  var contentRevision: String { "\(library.generation)|\(library.contentGeneration)" }
  var selection: Set<String> { get { library.selection } set { library.selection = newValue } }
  var startsAtEnd: Bool { true }
  var zoomStops: [Int] { MacLibraryDensity.columns }
  var scroll: MacGridScrollState {
    if scrollKey != contextID {
      scrollKey = contextID; retainedScroll.offset = library.scrollOffset
      retainedScroll.anchor = library.scrollAnchorID; retainedScroll.inset = library.scrollAnchorInset
    }
    return retainedScroll
  }
  func saveScroll() {
    library.scrollOffset = retainedScroll.offset; library.scrollAnchorID = retainedScroll.anchor
    library.scrollAnchorInset = retainedScroll.inset
  }
  var thumbnails: ThumbnailPipeline? { library.thumbnails }
  var previewPoster: ((String) -> NSImage?)? { get { library.previewPoster } set { library.previewPoster = newValue } }
  var previewFrame: ((String) -> CGRect?)? { get { library.previewFrame } set { library.previewFrame = newValue } }
  func asset(_ id: String) -> PHAsset? { library.index(of: id).flatMap { library.asset(at: $0) } }
  func date(_ id: String) -> Date? { fact(id)?.date ?? asset(id)?.creationDate }
  func fact(_ id: String) -> MacThumbnailTables.Fact? {
    library.index(of: id).flatMap { library.rawIndex(at: $0) }.flatMap { MacThumbnailTables.fact(library.fetch, at: $0) }
  }
  var footer: String {
    guard let fetch = library.fetch else { return "" }
    return String(format: NSLocalizedString("library_footer_counts", comment: ""),
      fetch.countOfAssets(with: .image).formatted(), fetch.countOfAssets(with: .video).formatted())
  }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    if let asset = asset(id) { cell.configure(asset, pipeline: library.thumbnails, pixels: pixels, originalAspect: originalAspect, identifier: id) }
  }
  func zoomTile(_ id: String, side: CGFloat, scale: CGFloat, originalAspect: Bool) -> NSView {
    guard let asset = asset(id) else { return NSView() }
    let tile = MacZoomMediaTile(); tile.frame.size = CGSize(width: side, height: side)
    tile.configure(asset, side: side, pixels: side * scale, pipeline: library.thumbnails,
      originalAspect: originalAspect, selected: selection.contains(id), scale: scale)
    return tile
  }
  func preheat(_ ids: [String], pixels: CGFloat) { library.thumbnails.preheat(ids.compactMap(asset), pixels: pixels) }
  func prefill() { MacThumbnailTables.prefill(library.fetch) }
  func loadAllIfNeeded() {
    guard library.hasMoreRows, bulkGeneration != library.generation else { return }
    bulkGeneration = library.generation
    let generation = library.generation
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(1))
      for _ in 0..<40 {
        guard let self, self.library.hasMoreRows, self.library.generation == generation else { return }
        await self.library.loadAllRows()
        if self.library.hasMoreRows { try? await Task.sleep(for: .milliseconds(250)) }
      }
    }
  }
  func loadAll() async { await library.loadAllRows() }
  func loadMore(visible: [String]) {
    if visible.contains(where: { (library.index(of: $0) ?? 0) >= library.loaded - 48 }) { library.loadMore() }
  }
  func refreshMarks(_ cells: [PhotoCell], receiver: String?, revision: String) async {
    let generation = library.generation
    let assets = cells.compactMap { $0.presentationID.flatMap(asset) }
    let groups = await library.visibleGroups(assets)
    guard !Task.isCancelled, generation == library.generation,
      let states = await librarySourceStates(groups, receiver: receiver, cache: library.tileStates,
        revision: "\(generation)|\(revision)") else { return }
    guard !Task.isCancelled, generation == library.generation else { return }
    for cell in cells {
      let id = cell.assetID ?? ""
      let group = groups[id]
      cell.setGroup(count: asset(cell.presentationID ?? "")?.burstIdentifier != nil ? group?.count : nil, state: group?.state(states))
    }
  }
}

/// Shared grouped geometry, also read by the live zoom faces and anchor math.
@MainActor enum MacGridGeometry {
  static func make(count: Int, groups: [Int: String], columns: Int, width: CGFloat, headerHeights: [Int: CGFloat] = [:]) -> LibraryTimelineGeometry {
    LibraryTimelineGeometry(dates: Array(repeating: nil, count: count), mode: .all, width: width,
      target: 135, inset: 2, gap: 2, headerHeight: 44, columns: columns, sectionTitles: groups, sectionHeaderHeights: headerHeights)
  }
}


/// Date text is the library header on every source; an optional source summary
/// sits above it without changing tile padding or date typography.
@MainActor final class MacGridSectionHeader: NSView, NSCollectionViewElement {
  private let date = TimelineDateHeader(frame: .zero)
  private(set) var summary: NSHostingView<AnyView>?
  private var introduction: AnyView?
  private var summaryWidth: CGFloat = -1
  static let dateHeight: CGFloat = 44
  /// Date text and folder summaries share the library header's 28 pt inset.
  static let inset: CGFloat = 28
  static func contentWidth(for gridWidth: CGFloat) -> CGFloat { max(1, gridWidth - inset * 2) }
  static func fittingHeight(introduction: AnyView, width: CGFloat) -> CGFloat {
    let host = NSHostingView(rootView: constrained(introduction, width: width))
    return ceil(host.fittingSize.height) + dateHeight
  }
  private static func constrained(_ content: AnyView, width: CGFloat) -> AnyView {
    AnyView(content.frame(width: max(1, width)).fixedSize(horizontal: false, vertical: true))
  }
  override var isFlipped: Bool { true }
  override init(frame: NSRect) { super.init(frame: frame); addSubview(date) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  func configure(title: String, introduction: AnyView?) {
    date.setTitle(title)
    self.introduction = introduction
    summaryWidth = bounds.width
    if let introduction {
      let content = Self.constrained(introduction, width: bounds.width)
      if let summary { summary.rootView = content }
      else { let host = NSHostingView(rootView: content); summary = host; addSubview(host) }
    } else { summary?.removeFromSuperview(); summary = nil }
    needsLayout = true
  }
  override func layout() {
    super.layout()
    let height = min(Self.dateHeight, bounds.height)
    if summaryWidth != bounds.width, let introduction {
      summaryWidth = bounds.width
      summary?.rootView = Self.constrained(introduction, width: bounds.width)
    }
    summary?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - height))
    // The date belongs to the photos below it: it sits near them, with the
    // header's remaining space separating it from the previous section.
    date.frame = CGRect(x: 0, y: bounds.height - 30, width: bounds.width, height: min(height, 24))
  }
}

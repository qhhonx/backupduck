import AppKit
import Photos
import SwiftUI

/// All source grids share one column-count preference.
@MainActor final class MacGridSize: ObservableObject {
  static let shared = MacGridSize()
  @Published var columns = MacLibraryDensity.remembered {
    didSet { MacLibraryDensity.remember(columns) }
  }
  var ordinaryColumns: Int {
    get { MacLibraryDensity.grid.min(by: { abs($0 - columns) < abs($1 - columns) }) ?? MacLibraryDensity.standard }
    set { columns = newValue }
  }
  func resolve(_ requested: Int, width: CGFloat, stops: [Int], active: Bool) -> Int {
    requested
  }
}

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
  /// Source explanations and reason headings scroll with the photos.
  var flowHeaders: Set<Int> { get }
  var dateIDs: [Int: String] { get }
  func folderHeaders(width: CGFloat) -> [Int: MacTimelineFolder]
  func folderIdentity(at index: Int) -> AnyView?
  func introduction(at index: Int) -> AnyView?
  func headerHeights(width: CGFloat) -> [Int: CGFloat]
  var selection: Set<String> { get set }
  var scroll: MacGridScrollState { get }
  var startsAtEnd: Bool { get }
  var zoomStops: [Int] { get }
  var footer: String { get }
  var footerNotes: [String] { get }
  var thumbnails: ThumbnailPipeline? { get }
  var previewPoster: ((String) -> NSImage?)? { get set }
  var previewFrame: ((String) -> CGRect?)? { get set }
  func asset(_ id: String) -> PHAsset?
  func informationTarget(_ id: String) -> MacPhotoInformationTarget
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
  var flowHeaders: Set<Int> { [] }
  var dateIDs: [Int: String] { [:] }
  func folderHeaders(width: CGFloat) -> [Int: MacTimelineFolder] { [:] }
  func folderIdentity(at index: Int) -> AnyView? { nil }
  func introduction(at index: Int) -> AnyView? { nil }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] { [:] }
  var startsAtEnd: Bool { false }
  var zoomStops: [Int] { MacLibraryDensity.grid }
  var footer: String { "" }
  var footerNotes: [String] { [] }
  var thumbnails: ThumbnailPipeline? { nil }
  func asset(_ id: String) -> PHAsset? { nil }
  func informationTarget(_ id: String) -> MacPhotoInformationTarget {
    if let asset = asset(id) { return .library(asset, nil, nil) }
    return .selection(0)
  }
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
  override func layout() { super.layout(); cell.zoomReadingFrame = frame; cell.view.frame = bounds }
  func cancel() { setReadingHost(nil); setReadingRect(nil); cell.cancel() }
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
  var sharesSize = false
  var ordinaryOnly = false
  var prefillsTables = true
  var preview: (PHAsset) -> Void = { _ in }
  var enterSelection: () -> Void = {}
  var resize: (Int) -> Void = { _ in }
  @StateObject private var storage = MacLibraryGridStorage()
  var body: some View {
    let source = storage.source(for: library, ordinaryOnly: ordinaryOnly)
    MacMediaGrid(source: source, navigation: navigation, preparationRevision: preparationRevision,
      queueRevision: queueRevision, receiverID: receiverID, columns: columns,
      selecting: selecting, readOnly: readOnly, active: active,
      sharedSize: sharesSize ? .shared : nil, prefillsTables: prefillsTables,
      preview: { id in if let asset = source.asset(id) { preview(asset) } },
      enterSelection: enterSelection, resize: resize)
      .modifier(MacGridInspector(navigation: navigation, source: source, active: active, selection: library.selection))
  }
}
@MainActor private final class MacLibraryGridStorage: ObservableObject {
  private var current: MacPhotoLibrarySource?
  func source(for library: PhotoLibraryModel, ordinaryOnly: Bool) -> MacPhotoLibrarySource {
    if let current, current.library === library { return current }
    let source = MacPhotoLibrarySource(library); source.ordinaryOnly = ordinaryOnly; current = source; return source
  }
}

@MainActor final class MacPhotoLibrarySource: MacGridSource {
  let library: PhotoLibraryModel
  var ordinaryOnly = false
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
  var zoomStops: [Int] { ordinaryOnly ? MacLibraryDensity.grid : MacLibraryDensity.columns }
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
  func informationTarget(_ id: String) -> MacPhotoInformationTarget {
    guard let asset = asset(id) else { return .selection(0) }
    return .library(asset, library, nil)
  }
  func date(_ id: String) -> Date? { fact(id)?.date ?? asset(id)?.creationDate }
  func fact(_ id: String) -> MacThumbnailTables.Fact? {
    library.index(of: id).flatMap { library.rawIndex(at: $0) }.flatMap { MacThumbnailTables.fact(library.fetch, at: $0) }
  }
  var footer: String {
    guard library.placeholder == nil, let fetch = library.fetch else { return "" }
    return MacGridTotals(total: fetch.count,
      photos: fetch.countOfAssets(with: .image), videos: fetch.countOfAssets(with: .video)).text()
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

/// The window describes the first photo row that is actually visible, not the
/// fetched page or the entire viewport. Missing dates remain absent.
enum MacGridDateRange {
  enum Period { case year, month, monthAndYear }
  static func topRow(in viewport: CGRect, items: [(index: Int, frame: CGRect)]) -> [Int] {
    let visible = items.filter { $0.frame.intersects(viewport) && !$0.frame.isEmpty }
    guard let top = visible.map({ $0.frame.minY }).min() else { return [] }
    return visible.filter { abs($0.frame.minY - top) < 0.5 }.map(\.index).sorted()
  }

  static var applicationLocale: Locale {
    let language = Bundle.main.preferredLocalizations.first ?? "en"
    let region = Locale.current.region.map { "_" + $0.identifier } ?? ""
    return Locale(identifier: language + region)
  }

  static func periodTitle(_ date: Date, period: Period = .monthAndYear,
    calendar: Calendar = .current, locale: Locale = applicationLocale) -> String {
    let month = locale.language.languageCode?.identifier == "zh" ? "MMM" : "MMMM"
    let template: String
    switch period {
    case .year: template = "y"
    case .month: template = month
    case .monthAndYear: template = "y" + month
    }
    let formatter = DateFormatter()
    formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }

  static func title(dates: [Date], calendar: Calendar = .current, locale: Locale = applicationLocale) -> String {
    guard let first = dates.min(), let last = dates.max() else { return "" }
    let start = calendar.startOfDay(for: first), end = calendar.startOfDay(for: last)
    let template = locale.language.languageCode?.identifier == "zh" ? "yMMMd" : "yMMMMd"
    if start == end {
      let formatter = DateFormatter()
      formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
      formatter.setLocalizedDateFormatFromTemplate(template)
      return formatter.string(from: start)
    }
    let formatter = DateIntervalFormatter()
    formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
    formatter.dateTemplate = template
    return formatter.string(from: start, to: end)
  }
}

/// A complete collection total can exist without a trustworthy media split.
/// Missing type metadata must never turn every item into a photo.
struct MacGridTotals: Equatable {
  let total: Int
  let photos: Int?
  let videos: Int?
  init(total: Int, photos: Int? = nil, videos: Int? = nil) {
    self.total = max(0, total)
    if let photos, let videos, photos >= 0, videos >= 0, photos + videos == total {
      self.photos = photos; self.videos = videos
    } else { self.photos = nil; self.videos = nil }
  }
  static func complete(kinds: [String?]) -> Self {
    let photos = kinds.filter { ["photo", "motion", "burst"].contains($0 ?? "") }.count
    let videos = kinds.filter { $0 == "video" }.count
    return Self(total: kinds.count, photos: photos, videos: videos)
  }
  func text(bundle: Bundle = .main, locale: Locale = MacGridDateRange.applicationLocale) -> String {
    func phrase(_ count: Int, _ singular: String, _ plural: String) -> String {
      String(format: bundle.localizedString(forKey: count == 1 ? singular : plural, value: nil, table: nil),
        count.formatted(.number.locale(locale)))
    }
    guard let photos, let videos else { return phrase(total, "scope_album_item", "scope_album_items") }
    if videos == 0 { return phrase(photos, "grid_footer_photo", "grid_footer_photos") }
    if photos == 0 { return phrase(videos, "grid_footer_video", "grid_footer_videos") }
    return [phrase(photos, "grid_footer_photo", "grid_footer_photos"),
      phrase(videos, "grid_footer_video", "grid_footer_videos")].joined(separator: " · ")
  }
}

/// One native reading surface travels with the existing grid zoom. Supporting
/// notes reserve their lines even while an exact count is still unavailable.
@MainActor enum MacGridFooter {
  static let minimumHeight: CGFloat = 56
  static let topInset: CGFloat = 14
  static func attributed(total: String, notes: [String]) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping
    paragraph.firstLineHeadIndent = DuckSpacing.large; paragraph.headIndent = DuckSpacing.large
    paragraph.tailIndent = -DuckSpacing.large
    // An empty paragraph can take a different font metric on older AppKit.
    let countLine = total.isEmpty && !notes.isEmpty ? "\u{00A0}" : total
    let text = ([countLine] + notes).joined(separator: "\n")
    let result = NSMutableAttributedString(string: text, attributes: [
      .font: NSFont.preferredFont(forTextStyle: .caption1),
      .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
    if !total.isEmpty {
      result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: (total as NSString).length))
    }
    return result
  }
  static func textHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
    let cell = NSTextFieldCell(textCell: "")
    cell.attributedStringValue = text
    cell.wraps = true; cell.isScrollable = false; cell.usesSingleLineMode = false
    cell.lineBreakMode = .byWordWrapping
    return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(1, width),
      height: .greatestFiniteMagnitude)).height)
  }
  static func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
    max(minimumHeight, textHeight(text, width: width) + topInset * 2)
  }
}

/// Shared grouped geometry, also read by the live zoom faces and anchor math.
@MainActor enum MacGridGeometry {
  static func make(count: Int, groups: [Int: String], columns: Int, width: CGFloat, headerHeights: [Int: CGFloat] = [:],
    folders: [Int: MacTimelineFolder] = [:], dateIDs: [Int: String] = [:], flowHeaders: Set<Int> = []) -> LibraryTimelineGeometry {
    var geometry = LibraryTimelineGeometry(dates: Array(repeating: nil, count: count), mode: .all, width: width,
      target: 135, inset: 2, gap: 2, headerHeight: 44, columns: columns, sectionTitles: groups, sectionHeaderHeights: headerHeights)
    geometry.configureMacCaptions(folders: folders, dateIDs: dateIDs, flowHeaders: flowHeaders)
    return geometry
  }
}


/// Native supplementary content for overview periods and ordinary source notes.
/// Ordinary media dates belong to the window subtitle, never these headers.
@MainActor final class MacGridSectionHeader: NSView, NSCollectionViewElement {
  private let date = TimelineDateHeader(frame: .zero)
  private(set) var summary: NSHostingView<AnyView>?
  private var introduction: AnyView?
  private var summaryWidth: CGFloat = -1
  private var role: MacTimelineCaption.Kind = .date
  private var naturalY: CGFloat = 0
  var floatingDate = false { didSet { date.floating = floatingDate; needsLayout = true } }
  private(set) var captionID: MacTimelineCaption.ID?
  private(set) var contentRevision = ""
  private(set) var representedTitle = ""
  var onLayout: (() -> Void)?
  static let dateHeight: CGFloat = 44
  /// Date text and folder summaries share the library header's 28 pt inset.
  static let inset: CGFloat = 28
  static func contentWidth(for gridWidth: CGFloat) -> CGFloat { max(1, gridWidth - inset * 2) }
  static func fittingHeight(introduction: AnyView, width: CGFloat) -> CGFloat {
    fittingContentHeight(introduction, width: width) + dateHeight
  }
  static func fittingContentHeight(_ content: AnyView, width: CGFloat) -> CGFloat {
    let host = NSHostingView(rootView: constrained(content, width: contentWidth(for: width)))
    return ceil(host.fittingSize.height)
  }
  private static func constrained(_ content: AnyView, width: CGFloat) -> AnyView {
    AnyView(content.frame(width: max(1, width)).fixedSize(horizontal: false, vertical: true))
  }
  override var isFlipped: Bool { true }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance(); updateBackground()
  }
  private func updateBackground() {
    // Keep the entire reading surface opaque within its own backing layer.
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = role == .date ? nil : DuckRole.backgroundNSColor.cgColor
    }
  }
  override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; addSubview(date) }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  func configure(caption: MacTimelineCaption, content: AnyView?, revision: String) {
    role = caption.id.kind; captionID = caption.id; contentRevision = revision
    naturalY = caption.frame.minY
    configure(title: caption.title, introduction: content)
  }
  func configure(title: String, introduction: AnyView?) {
    representedTitle = title
    date.setTitle(title)
    date.isHidden = role != .date
    self.introduction = introduction
    let width = Self.contentWidth(for: bounds.width)
    summaryWidth = width
    if let introduction {
      let content = Self.constrained(introduction, width: width)
      if let summary { summary.rootView = content }
      else { let host = NSHostingView(rootView: content); summary = host; addSubview(host) }
    } else { summary?.removeFromSuperview(); summary = nil }
    needsLayout = true
  }
  func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
    floatingDate = role == .date && layoutAttributes.frame.minY > naturalY + 0.5
  }
  override func layout() {
    super.layout()
    updateBackground()
    let height = role == .date ? min(Self.dateHeight, bounds.height) : 0
    let width = Self.contentWidth(for: bounds.width)
    if summaryWidth != width, let introduction {
      summaryWidth = width
      summary?.rootView = Self.constrained(introduction, width: width)
    }
    summary?.frame = CGRect(x: Self.inset, y: 0, width: width, height: max(0, bounds.height - height))
    // The date belongs to the photos below it: it sits near them, with the
    // header's remaining space separating it from the previous section.
    date.frame = CGRect(x: Self.inset, y: bounds.height - 30, width: width, height: min(height, 24))
    onLayout?()
  }
  func isReady(for caption: MacTimelineCaption, revision: String) -> Bool {
    guard captionID == caption.id, representedTitle == caption.title, contentRevision == revision else { return false }
    layoutSubtreeIfNeeded(); displayIfNeeded()
    if role == .date { return !date.isHidden && date.readingReady }
    guard layer?.backgroundColor != nil else { return false }
    guard let summary, summary.superview === self, !summary.isHidden,
      abs(summary.frame.width - Self.contentWidth(for: bounds.width)) < 0.5,
      abs(summary.frame.height - bounds.height) < 0.5 else { return false }
    summary.layoutSubtreeIfNeeded(); summary.displayIfNeeded()
    return true
  }
}

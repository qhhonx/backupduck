import AppKit
import SwiftUI

/// Folders are an item source for the same native grid as the photo library.
struct MacFolderGrid: View {
  @Environment(\.macViewerPresentation) private var present
  @ObservedObject var folders: FolderSources
  @ObservedObject var browser: FolderBrowser
  @ObservedObject var navigation: MacLibraryNavigation
  var columns: Int
  var resize: (Int) -> Void
  var settings: (String) -> Void
  var stop: (FolderSource) -> Void
  var body: some View {
    let source = MacFolderGridSource(folders: folders, browser: browser, settings: settings, stop: stop)
    Group {
    if source.identifiers.isEmpty && browser.type == .all && browser.filter == .all && browser.search.isEmpty {
      ScrollView { LazyVStack(spacing: 0) {
        ForEach(folders.sources) { folder in
          FolderSectionHeader(folders: folders, source: folder, settings: settings, stop: stop)
        }
      } }
    } else {
    MacMediaGrid(source: source, navigation: navigation, queueRevision: 0,
      receiverID: nil, columns: columns, prefillsTables: false, preview: { id in
        guard let photo = source.photos[id] else { return }
        let context = source.identifiers.compactMap { source.photos[$0] }
        let returnTo: (FolderPhoto) -> Void = { navigation.focus($0.id) }
        if let present { present(.folder(photo, context, folders, returnTo)) }
        else { MacFolderViewer.open(photo, context: context, folders: folders) }
      }, resize: resize)
      .overlay {
        if source.identifiers.isEmpty {
          MacGridFilterEmpty { browser.filter = .all; browser.type = .all; browser.search = "" }
        }
      }
    }
    }
    .task(id: "\(browser.key)|\(browser.sections.map { $0.photos.count })") {
      // Type filtering is a browse projection. Continue bounded native pages
      // when a loaded page has no matches, including an all-video first page.
      if source.identifiers.isEmpty {
        for section in browser.sections where section.hasMore { await browser.more(section.id, folders: folders) }
      }
    }
  }
}

@MainActor final class MacFolderGridSource: MacGridSource {
  let folders: FolderSources
  let browser: FolderBrowser
  let photos: [String: FolderPhoto]
  let identifiers: [String]
  let groups: [Int: String]
  private var introductions: [Int: AnyView] = [:]
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  init(folders: FolderSources, browser: FolderBrowser, settings: @escaping (String) -> Void = { _ in }, stop: @escaping (FolderSource) -> Void = { _ in }) {
    self.folders = folders; self.browser = browser
    let rows = browser.sections.flatMap(\.photos).filter { browser.type.matches(kind: $0.media_type.hasPrefix("video/") ? "video" : "photo") }
    photos = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    identifiers = rows.map(\.id)
    var titles: [Int: String] = [:], previous = ""
    for (index, photo) in rows.enumerated() {
      let day = Calendar.current.startOfDay(for: photo.date)
      let key = (browser.byFolder ? photo.folder_id : "") + "|\(day.timeIntervalSince1970)"
      if key != previous {
        titles[index] = photo.date.formatted(date: .long, time: .omitted); previous = key
      }
    }
    groups = titles
    if browser.byFolder && browser.search.isEmpty {
      var seen = Set<String>()
      for (index, photo) in rows.enumerated() where seen.insert(photo.folder_id).inserted {
        if let folder = folders.sources.first(where: { $0.id == photo.folder_id }) {
          introductions[index] = AnyView(FolderSectionHeader(folders: folders, source: folder, settings: settings, stop: stop))
        }
      }
    }
  }
  func introduction(at index: Int) -> AnyView? { introductions[index] }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] {
    introductions.mapValues { content in
      MacGridSectionHeader.fittingHeight(introduction: content, width: MacGridSectionHeader.contentWidth(for: width))
    }
  }
  var membershipReady: Bool { browser.resultKey == browser.key }
  var contextID: String { browser.key }
  var contentRevision: String { "\(folders.indexRevision)|\(folders.revision)" }
  var selection: Set<String> { get { browser.selection } set { browser.selection = newValue } }
  var scroll: MacGridScrollState {
    if let stored = browser.gridScrolls[contextID] { return stored }
    let state = MacGridScrollState(); state.offset = browser.offsets[contextID] ?? .zero
    browser.gridScrolls[contextID] = state; return state
  }
  func saveScroll() { browser.offsets[contextID] = scroll.offset }
  func date(_ id: String) -> Date? { photos[id]?.date }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    guard let photo = photos[id], let source = folders.sources.first(where: { $0.id == photo.folder_id }) else { return }
    cell.configureFolder(photo, source: source, pixels: pixels, synthetic: folders.syntheticImage(photo))
    cell.view.alphaValue = folders.facts[photo.folder_id]?.available == false ? 0.5 : 1
  }
  func loadMore(visible: [String]) {
    for section in browser.sections where section.hasMore && section.photos.filter({ photos[$0.id] != nil }).suffix(20).contains(where: { visible.contains($0.id) }) {
      Task { await browser.more(section.id, folders: folders) }
    }
  }
}

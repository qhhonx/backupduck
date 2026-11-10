import AppKit
import SwiftUI

/// Folders are an item source for the same native grid as the photo library.
struct MacFolderGrid: View {
  @Environment(\.macViewerPresentation) private var present
  @ObservedObject var folders: FolderSources
  @ObservedObject var browser: FolderBrowser
  @ObservedObject var navigation: MacLibraryNavigation
  var columns: Int
  var active = true
  var resize: (Int) -> Void
  var settings: (String) -> Void
  var stop: (FolderSource) -> Void
  var body: some View {
    let source = MacFolderGridSource(folders: folders, browser: browser, settings: settings, stop: stop)
    MacMediaGrid(source: source, navigation: navigation, queueRevision: 0,
      receiverID: nil, columns: columns, initialLoadingIndicator: true, active: active, sharedSize: .shared, prefillsTables: false, preview: { id in
        guard let photo = source.photos[id] else { return }
        let context = source.identifiers.compactMap { source.photos[$0] }
        let returnTo: (FolderPhoto) -> Void = { navigation.focus($0.id) }
        if let present { present(.folder(photo, context, folders, returnTo, navigation: navigation)) }
        else { MacFolderViewer.open(photo, context: context, folders: folders) }
      }, resize: resize)
    .modifier(MacGridInspector(navigation: navigation, source: source, active: active))
  }
}

@MainActor final class MacFolderGridSource: MacGridSource {
  let folders: FolderSources
  let browser: FolderBrowser
  let photos: [String: FolderPhoto]
  private let sources: [String: FolderSource]
  let fetchResult: MacGridFetchResult
  let contextID: String
  let membershipReady: Bool
  let groups: [Int: String]
  let flowHeaders: Set<Int>
  private let notice: AnyView?
  private var measured: (width: CGFloat, heights: [Int: CGFloat])?
  var previewPoster: ((String) -> NSImage?)?
  var previewFrame: ((String) -> CGRect?)?
  init(folders: FolderSources, browser: FolderBrowser, settings: @escaping (String) -> Void = { _ in }, stop: @escaping (FolderSource) -> Void = { _ in }) {
    self.folders = folders; self.browser = browser
    sources = Dictionary(uniqueKeysWithValues: folders.sources.map { ($0.id, $0) })
    let rows = browser.visiblePhotos
    photos = browser.photosByID
    fetchResult = browser.result?.grid ?? MacGridFetchResult(identifiers: [])
    contextID = browser.key
    membershipReady = browser.resultKey == contextID
    if case let .folder(id) = browser.scope, !rows.isEmpty,
      let folder = folders.sources.first(where: { $0.id == id }), folderScopeHasNotice(folders.facts[id]) {
      notice = AnyView(FolderScopeNotice(folders: folders, source: folder))
      groups = [0: ""]; flowHeaders = [0]
    } else {
      notice = nil; groups = [:]; flowHeaders = []
    }
  }
  func informationTarget(_ id: String) -> MacPhotoInformationTarget {
    guard let photo = photos[id] else { return .selection(0) }
    return .folder(photo, folders, nil)
  }
  func introduction(at index: Int) -> AnyView? { index == 0 ? notice : nil }
  func headerHeights(width: CGFloat) -> [Int: CGFloat] {
    if let measured, measured.width == width { return measured.heights }
    let heights = notice.map { [0: MacGridSectionHeader.fittingContentHeight($0, width: width)] } ?? [:]
    measured = (width, heights)
    return heights
  }
  var contentRevision: String { "\(folders.indexRevision)|\(folders.revision)" }
  var footer: String { totals?.text() ?? "" }
  var totals: MacGridTotals? {
    guard membershipReady, !browser.loading, browser.error == nil else { return nil }
    return fetchResult.totals
  }
  var selection: Set<String> { get { browser.selection } set { browser.selection = newValue } }
  var scroll: MacGridScrollState {
    if let stored = browser.gridScrolls[contextID] { return stored }
    let state = MacGridScrollState(); state.offset = browser.offsets[contextID] ?? .zero
    browser.gridScrolls[contextID] = state; return state
  }
  func saveScroll() { browser.offsets[contextID] = scroll.offset }
  func date(_ id: String) -> Date? {
    guard let photo = photos[id], photo.capture_ms > 0,
      photo.date_source == "embedded" || photo.date_source == "file_modified" else { return nil }
    return photo.date
  }
  func configure(_ cell: PhotoCell, id: String, pixels: CGFloat, originalAspect: Bool) {
    guard let photo = photos[id], let source = sources[photo.folder_id] else { return }
    cell.configureFolder(photo, source: source, pixels: pixels, synthetic: folders.syntheticImage(photo))
    cell.view.alphaValue = folders.facts[photo.folder_id]?.available == false ? 0.5 : 1
  }
  func preheat(_ ids: [String], pixels: CGFloat) {
    guard !folders.isPreview, contextID == browser.key else { return }
    browser.preheat(ids.compactMap { photos[$0] }, sources: sources, pixels: pixels)
  }
  func stopPreheating() { browser.stopPreheating() }
}

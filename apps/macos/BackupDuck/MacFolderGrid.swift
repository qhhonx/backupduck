import AppKit
import SwiftUI

/// Native virtualization and selection. Each view/filter owns its retained scroll offset.
struct MacFolderGrid: NSViewRepresentable {
  @Environment(\.macViewerPresentation) private var present
  @ObservedObject var folders: FolderSources
  @ObservedObject var browser: FolderBrowser
  var settings: (String) -> Void
  var stop: (FolderSource) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScrollView {
    let layout = NSCollectionViewFlowLayout()
    layout.minimumInteritemSpacing = 2; layout.minimumLineSpacing = 2 // V3 photo grid gap
    layout.sectionInset = NSEdgeInsets(top: 0, left: DuckSpacing.large, bottom: DuckSpacing.large, right: DuckSpacing.large)
    let collection = FolderCollection()
    collection.collectionViewLayout = layout; collection.backgroundColors = [.clear]
    collection.isSelectable = true; collection.allowsMultipleSelection = true
    collection.register(PhotoCell.self, forItemWithIdentifier: .init("photo"))
    collection.register(FolderGridHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: .init("header"))
    collection.dataSource = context.coordinator; collection.delegate = context.coordinator
    collection.context = { [weak c = context.coordinator] path in c?.menu(path) }
    collection.open = { [weak c = context.coordinator] path in c?.open(path) }
    let scroll = FolderGridScroll()
    scroll.hasVerticalScroller = true; scroll.drawsBackground = false
    scroll.documentView = collection; scroll.contentView.postsBoundsChangedNotifications = true
    context.coordinator.collection = collection
    context.coordinator.scroll = scroll
    context.coordinator.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak c = context.coordinator] _ in
      MainActor.assumeIsolated { c?.scrolled() }
    }
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let c = context.coordinator; c.parent = self
    guard let collection = c.collection else { return }
    let oldKey = c.key
    if oldKey != browser.key { browser.offsets[oldKey] = scroll.contentView.bounds.origin; c.key = browser.key }
    let signature = browser.sections.map { $0.id + $0.photos.map { $0.id + $0.revision + $0.backup }.joined() }.joined()
    if signature != c.signature || oldKey != browser.key {
      c.signature = signature
      let anchorPath = collection.indexPathsForVisibleItems().sorted().first
      let anchorID = anchorPath.flatMap { c.photo($0)?.id }
      let anchorInset = anchorPath.flatMap { collection.collectionViewLayout?.layoutAttributesForItem(at: $0)?.frame.minY }.map { scroll.contentView.bounds.minY - $0 } ?? 0
      let wasFirstUpdate = c.firstUpdate
      var offset = oldKey != browser.key || wasFirstUpdate ? browser.offsets[browser.key] ?? .zero : scroll.contentView.bounds.origin
      c.firstUpdate = false
      c.sections = browser.sections
      collection.reloadData(); collection.layoutSubtreeIfNeeded()
      if oldKey == browser.key, !wasFirstUpdate, let anchorID {
        for (section, group) in c.sections.enumerated() {
          if let item = group.photos.firstIndex(where: { $0.id == anchorID }), let frame = collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: item, section: section))?.frame {
            offset.y = max(0, frame.minY + anchorInset); break
          }
        }
      }
      offset.y = min(max(0, collection.frame.height - scroll.contentSize.height), max(0, offset.y))
      scroll.contentView.scroll(to: offset); scroll.reflectScrolledClipView(scroll.contentView)
    }
    c.applyingSelection = true
    collection.selectionIndexPaths = Set(c.sections.enumerated().flatMap { section, group in
      group.photos.enumerated().compactMap { item, photo in browser.selection.contains(photo.id) ? IndexPath(item: item, section: section) : nil }
    })
    c.applyingSelection = false
    for path in collection.indexPathsForVisibleItems() {
      guard let row = c.photo(path), let source = folders.sources.first(where: { $0.id == row.folder_id }) else { continue }
      let cell = collection.item(at: path) as? PhotoCell
      cell?.configureFolder(row, source: source, pixels: c.side * (collection.window?.backingScaleFactor ?? 2), synthetic: folders.syntheticImage(row))
      cell?.view.alphaValue = folders.facts[row.folder_id]?.available == false ? 0.5 : 1
    }
  }
  static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
    if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
    coordinator.parent.browser.offsets[coordinator.key] = scroll.contentView.bounds.origin
    coordinator.collection?.visibleItems().forEach { ($0 as? PhotoCell)?.cancel() }
  }
  @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    var parent: MacFolderGrid
    weak var collection: NSCollectionView?
    weak var scroll: NSScrollView?
    var observer: NSObjectProtocol?
    var sections: [FolderBrowser.Section] = []
    var signature = ""
    var key = ""
    var applyingSelection = false
    var firstUpdate = true
    var side: CGFloat { max(1, floor(((scroll?.contentSize.width ?? 800) - DuckSpacing.large * 2 - 10) / 6)) }
    init(_ parent: MacFolderGrid) { self.parent = parent; key = parent.browser.key }
    func photo(_ path: IndexPath) -> FolderPhoto? {
      guard sections.indices.contains(path.section), sections[path.section].photos.indices.contains(path.item) else { return nil }
      return sections[path.section].photos[path.item]
    }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].photos.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt path: IndexPath) -> NSCollectionViewItem {
      let cell = collectionView.makeItem(withIdentifier: .init("photo"), for: path) as! PhotoCell
      if let row = photo(path), let source = parent.folders.sources.first(where: { $0.id == row.folder_id }) {
        cell.configureFolder(row, source: source, pixels: side * (collectionView.window?.backingScaleFactor ?? 2), synthetic: parent.folders.syntheticImage(row))
        cell.view.alphaValue = parent.folders.facts[row.folder_id]?.available == false ? 0.5 : 1
      }
      return cell
    }
    func collectionView(_ collectionView: NSCollectionView, layout: NSCollectionViewLayout, sizeForItemAt path: IndexPath) -> NSSize { NSSize(width: side, height: side) }
    func collectionView(_ collectionView: NSCollectionView, layout: NSCollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> NSSize {
      guard let source = parent.folders.sources.first(where: { $0.id == sections[section].id }) else { return NSSize(width: 0, height: DuckSpacing.medium) }
      let width = scroll?.contentSize.width ?? 800
      let host = NSHostingView(rootView: header(source).frame(width: width))
      host.frame.size.width = width
      return NSSize(width: host.frame.width, height: max(100, host.fittingSize.height))
    }
    func header(_ source: FolderSource) -> FolderSectionHeader {
      FolderSectionHeader(folders: parent.folders, source: source, settings: parent.settings, stop: parent.stop)
    }
    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at path: IndexPath) -> NSView {
      let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: .init("header"), for: path) as! FolderGridHeader
      if let source = parent.folders.sources.first(where: { $0.id == sections[path.section].id }) { view.show(AnyView(header(source))) }
      else { view.show(AnyView(EmptyView())) }
      return view
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { changed() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { changed() }
    func changed() {
      guard !applyingSelection, let collection else { return }
      parent.browser.selection = Set(collection.selectionIndexPaths.compactMap { photo($0)?.id })
    }
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt path: IndexPath) { (item as? PhotoCell)?.cancel() }
    func scrolled() {
      guard let collection, let scroll else { return }
      parent.browser.offsets[key] = scroll.contentView.bounds.origin
      for path in collection.indexPathsForVisibleItems() where sections.indices.contains(path.section) && path.item >= sections[path.section].photos.count - 15 {
        let id = sections[path.section].id
        Task { await parent.browser.more(id, folders: parent.folders) }
      }
    }
    func menu(_ path: IndexPath) -> NSMenu? {
      guard let row = photo(path), let source = parent.folders.sources.first(where: { $0.id == row.folder_id }) else { return nil }
      if !parent.browser.selection.contains(row.id) { collection?.selectionIndexPaths = [path]; changed() }
      let menu = NSMenu()
      func item(_ key: String, enabled: Bool = true, _ action: @escaping () -> Void) {
        let item = FolderMenuItem(title: NSLocalizedString(key, comment: ""), action: action)
        item.isEnabled = enabled; menu.addItem(item)
      }
      item("folders_back_up_selected", enabled: !parent.browser.selected.isEmpty) { [weak self] in
        guard let self else { return }
        Task { if await self.parent.folders.backUp(self.parent.browser.selected) { await self.parent.browser.reload(self.parent.folders) } }
      }
      item("folder_reveal", enabled: !parent.folders.isPreview) { [weak self] in self?.parent.folders.reveal(source, relative: row.relative) }
      item("folders_settings") { [weak self] in self?.parent.settings(source.id) }
      item("folders_stop_title") { [weak self] in self?.parent.stop(source) }
      return menu
    }
    func open(_ path: IndexPath) {
      guard let row = photo(path) else { return }
      if let present = parent.present { present(.folder(row, sections.flatMap(\.photos), parent.folders, { [weak self] current in
        guard let self, let collection = self.collection else { return }
        for (section, group) in self.sections.enumerated() {
          if let item = group.photos.firstIndex(where: { $0.id == current.id }) {
            collection.scrollToItems(at: [IndexPath(item: item, section: section)], scrollPosition: .centeredVertically)
            break
          }
        }
      })) }
      else { MacFolderViewer.open(row, context: sections.flatMap(\.photos), folders: parent.folders) }
    }
  }
}
private final class FolderCollection: NSCollectionView {
  var open: ((IndexPath) -> Void)?
  var context: ((IndexPath) -> NSMenu?)?
  override func menu(for event: NSEvent) -> NSMenu? {
    guard let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
    return context?(path)
  }
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    if event.clickCount == 2, let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) { open?(path) }
  }
}
private final class FolderGridHeader: NSView, NSCollectionViewElement {
  private var host: NSHostingView<AnyView>?
  func show(_ content: AnyView) {
    if let host { host.rootView = content }
    else {
      let host = NSHostingView(rootView: content); host.autoresizingMask = [.width, .height]; host.frame = bounds
      addSubview(host); self.host = host
    }
  }
}
private final class FolderGridScroll: NSScrollView {
  override func layout() {
    super.layout()
    if let collection = documentView as? NSCollectionView, collection.frame.width != contentSize.width {
      collection.setFrameSize(NSSize(width: contentSize.width, height: collection.frame.height))
      collection.collectionViewLayout?.invalidateLayout()
    }
  }
}

private final class FolderMenuItem: NSMenuItem {
  private let perform: () -> Void
  init(title: String, action: @escaping () -> Void) {
    perform = action; super.init(title: title, action: #selector(run), keyEquivalent: ""); target = self
  }
  required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  @objc private func run() { perform() }
}

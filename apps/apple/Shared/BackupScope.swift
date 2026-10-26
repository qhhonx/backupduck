import Combine
import Foundation
import Photos
import SwiftUI

enum BackupMediaKind: String, Codable, CaseIterable, Identifiable {
  case photo, motion, video, burst
  var id: String { rawValue }
  var title: String { LibraryFilter(rawValue: rawValue)!.title }
  var symbol: String { LibraryFilter(rawValue: rawValue)!.symbol }
  static func classify(image: Bool, video: Bool, live: Bool, burst: Bool) -> Self? {
    if video { return .video }
    guard image else { return nil }
    if burst { return .burst }
    return live ? .motion : .photo
  }
  static func kind(of asset: PHAsset) -> Self? {
    classify(image: asset.mediaType == .image, video: asset.mediaType == .video,
      live: asset.mediaSubtypes.contains(.photoLive), burst: asset.burstIdentifier != nil)
  }
}
struct BackupScopeRule: Codable, Equatable {
  var types: Set<BackupMediaKind> = Set(BackupMediaKind.allCases)
  var restrictAlbums = false
  var albums: Set<String> = []
  var albumNames: [String: String] = [:]
  var usesSpecifiedAlbums: Bool { restrictAlbums }
  func includes(kind: BackupMediaKind?, id: String, albumMembers: Set<String>) -> Bool {
    guard let kind, types.contains(kind) else { return false }
    return !usesSpecifiedAlbums || albumMembers.contains(id)
  }
  /// PhotoKit owns library membership. Capture only matching IDs, never media bytes.
  func selectedIDs(from identifiers: Set<String>? = nil) -> Set<String> {
    guard BackupEnvironment.usesPhotoLibrary else { return [] }
    var albumMembers: Set<String> = []
    if usesSpecifiedAlbums {
      let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(albums), options: nil)
      collections.enumerateObjects { collection, _, _ in
        PHAsset.fetchAssets(in: collection, options: photoLibraryFetchOptions()).enumerateObjects { asset, _, _ in
          if identifiers == nil || identifiers!.contains(asset.localIdentifier) { albumMembers.insert(asset.localIdentifier) }
        }
      }
    }
    let assets = identifiers.map { PHAsset.fetchAssets(withLocalIdentifiers: Array($0), options: photoLibraryFetchOptions()) }
      ?? PHAsset.fetchAssets(with: photoLibraryFetchOptions(for: .all))
    var result: Set<String> = []
    assets.enumerateObjects { asset, _, _ in
      if includes(kind: BackupMediaKind.kind(of: asset), id: asset.localIdentifier, albumMembers: albumMembers) { result.insert(asset.localIdentifier) }
    }
    return result
  }
  /// One album choice: the first explicit choice leaves All albums. Removing
  /// the last keeps the scope restricted (and empty) until All albums is on.
  func toggling(album id: String, name: String) -> Self {
    var next = self
    if !next.restrictAlbums { next.albums = []; next.albumNames = [:] }
    next.restrictAlbums = true
    if next.albums.contains(id) { next.albums.remove(id); next.albumNames.removeValue(forKey: id) }
    else { next.albums.insert(id); next.albumNames[id] = name }
    return next
  }
  func choosesAlbum(_ id: String) -> Bool { usesSpecifiedAlbums && albums.contains(id) }
}
@MainActor final class BackupScopeStore: ObservableObject {
  static let shared = BackupScopeStore()
  @Published private(set) var rule: BackupScopeRule
  @Published private(set) var loadFailed = false
  private let defaults: UserDefaults
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let stored = defaults.object(forKey: "photoBackupScope") {
      if let data = stored as? Data, let saved = try? JSONDecoder().decode(BackupScopeRule.self, from: data) { rule = saved }
      else { rule = BackupScopeRule(types: []); loadFailed = true }
    } else { rule = BackupScopeRule() }
  }
  func save(_ choice: BackupScopeRule) {
    let next = choice
    guard next != rule || loadFailed else { return }
    guard let data = try? JSONEncoder().encode(next) else { return }
    defaults.set(data, forKey: "photoBackupScope"); rule = next
    if loadFailed { loadFailed = false }
  }
  var summary: String {
    let types = BackupMediaKind.allCases.filter { rule.types.contains($0) }.map { NSLocalizedString($0.title, comment: "") }.joined(separator: ", ")
    if types.isEmpty { return NSLocalizedString("scope_empty", comment: "") }
    return types + " · " + (rule.usesSpecifiedAlbums
      ? String(format: NSLocalizedString("scope_album_count", comment: ""), rule.albums.count)
      : NSLocalizedString("scope_all_albums", comment: ""))
  }
}
enum BackupScopeDestination: String, Identifiable, Hashable {
  case types, albums
  var id: String { rawValue }
  var title: String { self == .types ? "scope_media_types" : "scope_albums_title" }
}

extension BackupScopeStore {
  /// The selected media types, or "no media types selected".
  var typesSummary: String {
    let value = rule.types.count == BackupMediaKind.allCases.count ? NSLocalizedString("scope_all_types", comment: "")
      : BackupMediaKind.allCases.filter { rule.types.contains($0) }.map { NSLocalizedString($0.title, comment: "") }.joined(separator: ", ")
    return value.isEmpty ? NSLocalizedString("scope_empty", comment: "") : value
  }
  var albumsSummary: String {
    rule.usesSpecifiedAlbums ? String(format: NSLocalizedString("scope_album_count", comment: ""), rule.albums.count)
      : NSLocalizedString("scope_all_albums", comment: "")
  }
}

struct ScopeAlbum: Identifiable, Hashable {
  let id: String
  let name: String
  let count: Int
  let system: Bool
  let cover: PHAsset?
  static func == (a: Self, b: Self) -> Bool { a.id == b.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
@MainActor final class ScopeAlbumsModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
  static let shared = ScopeAlbumsModel()
  @Published var albums: [ScopeAlbum] = []
  private var lastLoad: Date?
  private var lastAuthorization: PHAuthorizationStatus?
  private var loadedSelections = Set<String>()
  @Published var loading = false
  @Published var denied = false
  @Published private(set) var authorizationStatus: PHAuthorizationStatus = .denied
  private let suppliedAlbums: Bool
  init(albums: [ScopeAlbum]? = nil, denied: Bool = false) {
    suppliedAlbums = albums != nil
    super.init()
    self.albums = albums ?? []
    self.denied = denied
    guard !suppliedAlbums, BackupEnvironment.usesPhotoLibrary else { return }
    // Registering asks for photo access when it has not been decided yet.
    let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    authorizationStatus = access
    if BackupEnvironment.usesPhotoLibrary, access == .authorized || access == .limited { PHPhotoLibrary.shared().register(self) }
  }
  nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
    Task { @MainActor [weak self] in
      BackupEnvironment.activeModel().refreshPhotoAccess()
      self?.lastLoad = nil
    }
  }
  func load(requestPermission: Bool = false, selectedIDs: Set<String> = []) async {
    guard !suppliedAlbums, BackupEnvironment.usesPhotoLibrary, !loading else { return }; loading = true
    defer { loading = false }
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if requestPermission, status == .notDetermined {
      status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
      BackupEnvironment.activeModel().refreshPhotoAccess()
    }
    authorizationStatus = status
    denied = status != .authorized && status != .limited
    guard !denied else { return }
    if lastAuthorization == status, let lastLoad, Date().timeIntervalSince(lastLoad) < 30, selectedIDs.isSubset(of: loadedSelections.union(Set(albums.map(\.id)))) { return }
    albums = await Task.detached(priority: .utility) {
      var result: [ScopeAlbum] = []
      var seen = Set<String>()
      func append(_ collection: PHAssetCollection) {
        guard let name = collection.localizedTitle, seen.insert(collection.localIdentifier).inserted else { return }
        let options = photoLibraryFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let photos = PHAsset.fetchAssets(in: collection, options: options)
        result.append(ScopeAlbum(id: collection.localIdentifier, name: name, count: photos.count,
          system: collection.assetCollectionType == .smartAlbum, cover: PHAsset.fetchKeyAssets(in: collection, options: nil)?.firstObject))
      }
      PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { collection, _, _ in append(collection) }
      // Resolve existing explicit choices without enumerating every smart album.
      PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(selectedIDs), options: nil).enumerateObjects { collection, _, _ in append(collection) }
      return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }.value
    loadedSelections = selectedIDs; lastLoad = Date(); lastAuthorization = status
  }
}

/// A6: fixed choices are inline; collection choices use a searchable native list.
struct BackupScopeEditor: View {
  let destination: BackupScopeDestination
  @ObservedObject private var store: BackupScopeStore
  @StateObject private var model: ScopeAlbumsModel
  @State private var search: String
  @State private var openedAlbum: ScopeAlbum?

  @MainActor init(destination: BackupScopeDestination, store: BackupScopeStore? = nil,
    model: ScopeAlbumsModel? = nil, search: String = "") {
    self.destination = destination
    _store = ObservedObject(wrappedValue: store ?? .shared)
    _model = StateObject(wrappedValue: model ?? .shared)
    _search = State(initialValue: search)
  }

  var body: some View {
    searchableContent
      .task { if destination == .albums { await loadAlbums() } }
  }

  private var showsAlbumSearch: Bool {
    guard destination == .albums && !model.denied else { return false }
    #if os(macOS)
    return !model.albums.isEmpty
    #else
    return true
    #endif
  }

  private var searchableContent: some View {
    Group {
      // Search only where there is a list to search; the window toolbar on the Mac.
      if showsAlbumSearch {
        #if os(macOS)
        scopeContent.searchable(text: $search, placement: .toolbar, prompt: Text("scope_search_albums"))
        #else
        scopeContent.searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("scope_search_albums"))
        #endif
      } else { scopeContent }
    }
      .navigationTitle(LocalizedStringKey(destination.title))
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      #endif
      .navigationDestination(item: $openedAlbum) { album in albumBrowser(album) }
  }

  @ViewBuilder private func albumBrowser(_ album: ScopeAlbum) -> some View {
    #if os(iOS)
    ScopeAlbumBrowser(album: album, store: store)
    #else
    MacScopeAlbumBrowser(album: album, store: store)
    #endif
  }

  @Environment(\.duckSettingsNavigator) private var navigator
  private func view(_ album: ScopeAlbum) {
    if let navigator { navigator.open(DuckSettingsPage(title: Text(verbatim: album.name), content: AnyView(albumBrowser(album)))) }
    else { openedAlbum = album }
  }

  @ViewBuilder private var scopeContent: some View {
    if destination == .types {
      Form {
        Section {
          ForEach(BackupMediaKind.allCases) { kind in
            Toggle(isOn: typeBinding(kind)) {
              HStack(spacing: DuckSpacing.small) {
                Image(systemName: kind.symbol).foregroundStyle(DuckRole.secondaryText)
                  .frame(width: DuckSpacing.large).accessibilityHidden(true)
                Text(LocalizedStringKey(kind.title))
              }
            }
            .disabled(store.rule.types.count == 1 && store.rule.types.contains(kind))
            .accessibilityIdentifier("backup.scope.type." + kind.rawValue)

          }
        }
      }
      .formStyle(.grouped)
      .toggleStyle(DuckPreferenceToggleStyle())
      .accessibilityIdentifier("backup.scope.choices")
    } else if model.denied {
      // The library's own permission state: the right copy and action for
      // denied, restricted or undecided access, at the optical center.
      LibraryPlaceholder(kind: .permission(model.authorizationStatus),
        requestingAccess: model.loading,
        requestAccess: { Task { await loadAlbums(requestPermission: true) } })
    } else {
      #if os(macOS)
      if model.albums.isEmpty && !model.loading && missing.isEmpty {
        VStack(spacing: 0) {
          Form { Section { albumSelection } }.formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
          ContentUnavailableView {
            Label("scope_albums_empty", systemImage: "rectangle.stack")
          } description: { Text("scope_summary_note") }
            .labeledContentStyle(.automatic)
            .duckOpticalCenter()
        }
      } else { albumList }
      #else
      albumList
      #endif
    }
  }

  private var albumSelection: some View {
    Group {
      Text(selectionSummary).foregroundStyle(.secondary)
        .accessibilityIdentifier("backup.scope.album_count")
      Toggle("scope_all_albums", isOn: allAlbums)
        #if os(macOS)
        .toggleStyle(DuckPreferenceToggleStyle())
        #else
        .toggleStyle(.switch).frame(minHeight: DuckPreferenceMetrics.rowHeight)
        #endif
        .accessibilityIdentifier("backup.scope.all_albums")
    }
  }

  private var albumList: some View {
    let chosen = store.rule.usesSpecifiedAlbums ? store.rule.albums : []
    let visible = model.albums.filter { (!$0.system || chosen.contains($0.id)) && matches($0.name) }
    #if os(iOS)
    return List {
      Section {
        albumSelection
      }
      Section {
        if visible.isEmpty && !model.loading {
          if !search.isEmpty { ContentUnavailableView.search(text: search) }
          else {
            ContentUnavailableView {
              Label("scope_albums_empty", systemImage: "rectangle.stack")
            } description: { Text("scope_summary_note") } actions: {
              Button("retry_task") { Task { await loadAlbums() } }.buttonStyle(.bordered)
            }
          }
        }
        ForEach(visible) { album in
          ScopeChoiceRow(title: album.name, subtitle: albumItemCount(album.count),
            showsCover: true, cover: album.cover, selected: chosen.contains(album.id)) { selectAlbum(album) }
            .contextMenu {
              Button("scope_album_view") { view(album) }
              Button(chosen.contains(album.id) ? "scope_album_deselect" : "scope_album_choose") { selectAlbum(album) }
            }
            .accessibilityAction(named: Text("scope_album_view")) { view(album) }
            .accessibilityIdentifier("backup.scope.album." + album.id)
        }
      }
      if !model.loading && !missing.isEmpty {
        Section("scope_album_unavailable") {
          ForEach(missing.sorted().filter { matches(store.rule.albumNames[$0] ?? NSLocalizedString("scope_album_unavailable", comment: "")) }, id: \.self) { id in
            let name = store.rule.albumNames[id] ?? NSLocalizedString("scope_album_unavailable", comment: "")
            ScopeChoiceRow(title: name, subtitle: NSLocalizedString("scope_album_unavailable", comment: ""),
                showsCover: true, selected: true) {
                var next = store.rule; next.albums.remove(id); next.albumNames.removeValue(forKey: id); store.save(next)
              }.accessibilityIdentifier("backup.scope.album." + id)
          }
        }
      }
    }
    .scopeChoiceList()
    .overlay { if model.loading { ProgressView("library_loading") } }
    #else
    return ScrollView {
      VStack(alignment: .leading, spacing: DuckSpacing.large) {
        albumSelection
        if visible.isEmpty && !model.loading { ContentUnavailableView.search(text: search) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: DuckSpacing.medium)], alignment: .leading, spacing: DuckSpacing.large) {
          ForEach(visible) { album in
            MacScopeAlbumCard(album: album, selected: chosen.contains(album.id), action: { selectAlbum(album) })
              .contextMenu {
                Button("scope_album_view") { view(album) }
                Button(chosen.contains(album.id) ? "scope_album_deselect" : "scope_album_choose") { selectAlbum(album) }
              }
              .accessibilityAction(named: Text("scope_album_view")) { view(album) }
          }
        }
        if !model.loading && !missing.isEmpty {
          Text("scope_album_unavailable").font(.headline)
          ForEach(missing.sorted().filter { matches(store.rule.albumNames[$0] ?? "") }, id: \.self) { id in
            ScopeChoiceRow(title: store.rule.albumNames[id] ?? NSLocalizedString("scope_album_unavailable", comment: ""),
              subtitle: NSLocalizedString("scope_album_unavailable", comment: ""), showsCover: true, selected: true) {
                var next = store.rule; next.albums.remove(id); next.albumNames.removeValue(forKey: id); store.save(next)
              }
          }
        }
      }.padding(DuckSpacing.large)
    }.overlay { if model.loading { ProgressView("library_loading") } }
    #endif

  }

  private var missing: Set<String> {
    store.rule.usesSpecifiedAlbums ? store.rule.albums.subtracting(Set(model.albums.map(\.id))) : []
  }
  private var selectionSummary: String {
    guard store.rule.usesSpecifiedAlbums else { return NSLocalizedString("scope_all_albums_summary", comment: "") }
    let count = String(format: NSLocalizedString(store.rule.albums.count == 1 ? "scope_selection_album" : "scope_selection_albums", comment: ""),
      store.rule.albums.count.formatted())
    // Album totals can overlap; this is an estimate, never a unique asset count.
    guard !model.loading, missing.isEmpty else {
      return String(format: NSLocalizedString("scope_albums_unknown_count", comment: ""), count)
    }
    let photos = model.albums.filter { store.rule.albums.contains($0.id) }.reduce(0) { $0 + $1.count }
    let photoCount = String(format: NSLocalizedString(photos == 1 ? "scope_selection_photo" : "scope_selection_photos", comment: ""), photos.formatted())
    return String(format: NSLocalizedString("scope_albums_selection", comment: ""), count, photoCount)
  }
  private func matches(_ title: String) -> Bool { search.isEmpty || title.localizedStandardContains(search) }
  private func loadAlbums(requestPermission: Bool = false) async {
    await model.load(requestPermission: requestPermission, selectedIDs: store.rule.usesSpecifiedAlbums ? store.rule.albums : [])
  }
  private var allAlbums: Binding<Bool> {
    Binding(get: { !store.rule.restrictAlbums }, set: { enabled in
      var next = store.rule
      next.restrictAlbums = !enabled; next.albums = []; next.albumNames = [:]
      store.save(next)
    })
  }
  private func typeBinding(_ kind: BackupMediaKind) -> Binding<Bool> {
    Binding(get: { store.rule.types.contains(kind) }, set: { included in
      var next = store.rule
      if included { next.types.insert(kind) } else if next.types.count > 1 { next.types.remove(kind) }
      store.save(next)
    })
  }
  private func selectAlbum(_ album: ScopeAlbum) {
    store.save(store.rule.toggling(album: album.id, name: album.name))
  }
}

/// A fixed trailing checkmark slot keeps choices aligned without repainting the row.
private struct ScopeChoiceRow: View {
  let title: String
  var subtitle: String? = nil
  var symbol: String? = nil
  var showsCover = false
  var cover: PHAsset? = nil
  let selected: Bool
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: DuckSpacing.small) {
        if showsCover { ReadOnlyMediaThumbnail(asset: cover, width: 36, height: 36) }
        else if let symbol {
          Image(systemName: symbol).foregroundStyle(DuckRole.secondaryText)
            .frame(width: DuckSpacing.large).accessibilityHidden(true)
        }
        VStack(alignment: .leading) {
          Text(title).foregroundStyle(DuckRole.primaryText)
          if let subtitle { Text(subtitle).font(.caption).foregroundStyle(DuckRole.secondaryText) }
        }
        Spacer(minLength: DuckSpacing.small)
        Image(systemName: "checkmark").foregroundStyle(DuckRole.accent)
          .opacity(selected ? 1 : 0).accessibilityHidden(true)
      }.font(.body).frame(minHeight: DuckPreferenceMetrics.rowHeight).contentShape(Rectangle())
    }.buttonStyle(.borderless).transaction { $0.animation = nil }
      .listRowInsets(EdgeInsets(top: 0, leading: DuckSpacing.medium, bottom: 0, trailing: DuckSpacing.medium))
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private extension View {
  func scopeChoiceList() -> some View {
    #if os(iOS)
    self.listStyle(.insetGrouped).accessibilityIdentifier("backup.scope.choices")
    #else
    self.listStyle(.inset).accessibilityIdentifier("backup.scope.choices")
    #endif
  }
}

struct ReadOnlyMediaThumbnail: View {
  let asset: PHAsset?
  var width: CGFloat = 44
  var height: CGFloat = 44
  @Environment(\.displayScale) private var displayScale
  @ObservedObject private var policy = PreviewNetworkPolicy.shared
  @State private var image: LibraryImage?
  @State private var request = PHInvalidImageRequestID
  @State private var identity: String?
  @State private var requestGeneration = UUID()
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: DuckRadius.control).fill(DuckRole.background)
      if let image {
        #if os(macOS)
        Image(nsImage: image).resizable().scaledToFill()
        #else
        Image(uiImage: image).resizable().scaledToFill()
        #endif
      } else {
        Image(systemName: "photo.on.rectangle").foregroundStyle(DuckRole.secondaryText)
          .accessibilityHidden(true)
      }
    }.frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: DuckRadius.control)).accessibilityHidden(true)
      .task(id: "\(asset.map { $0.localIdentifier + "|" + PhotoLibraryModel.revision($0) } ?? "")|\(Int(width*displayScale))|\(Int(height*displayScale))|\(policy.choice)") {
        ScopeThumbnailCache.pipeline.cancel(request)
        if identity != asset?.localIdentifier { image = nil }
        identity = asset?.localIdentifier
        let generation = UUID(); requestGeneration = generation
        guard let asset, width > 0, height > 0 else { return }
        let pixels = max(width,height)*displayScale
        request = ScopeThumbnailCache.pipeline.request(asset,pixels: pixels) { value,_ in
          guard identity == asset.localIdentifier, requestGeneration == generation else { return }
          if let value { image = value }
        }
      }.onReceive(policy.$choice.dropFirst()) { _ in image = nil }
      .onDisappear {
        requestGeneration = UUID(); ScopeThumbnailCache.pipeline.cancel(request); request = PHInvalidImageRequestID
      }
  }
}

/// Album/strip posters are local, cancellable and reused across choice edits.
@MainActor enum ScopeThumbnailCache {
  static let pipeline = ThumbnailPipeline(cacheBudget: 24*1024*1024)
}

func albumItemCount(_ count: Int) -> String {
  String(format: NSLocalizedString(count == 1 ? "scope_album_item" : "scope_album_items",comment: ""),count.formatted())
}

#if os(macOS)
/// Album choices use covers as the complete keyboard- and pointer-operable target.
private struct MacScopeAlbumCard: View {
  let album: ScopeAlbum
  let selected: Bool
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
        GeometryReader { proxy in
          ReadOnlyMediaThumbnail(asset: album.cover, width: proxy.size.width, height: proxy.size.width)
            .overlay(alignment: .bottomTrailing) {
              if selected {
                Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
                  .foregroundStyle(Color.white, DuckRole.accent).font(.title3) // design-exception: selection check over a photo
                  .padding(DuckSpacing.xSmall)
              }
            }
        }.aspectRatio(1, contentMode: .fit)
        Text(verbatim: album.name).font(.body).lineLimit(2)
        Text(verbatim: albumItemCount(album.count)).font(.callout).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel(Text(verbatim: album.name + ", " + albumItemCount(album.count)))
      .accessibilityValue(Text(LocalizedStringKey(selected ? "scope_album_deselect" : "scope_album_choose")))
      .accessibilityAddTraits(selected ? .isSelected : [])
      .accessibilityIdentifier("backup.scope.album." + album.id)
  }
}
#endif

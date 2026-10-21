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
enum BackupScopeDestination: String, Identifiable {
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

struct BackupScopeSettings: View {
  @ObservedObject private var store = BackupScopeStore.shared
  var navigate: ((BackupScopeDestination) -> Void)? = nil
  private var typesValue: String { store.typesSummary }
  private var albumsValue: String { store.albumsSummary }
  var body: some View {
    #if os(macOS)
    MacPreferenceGroup(title: "scope_title", note: "scope_summary_note") {
      Button { navigate?(.types) } label: {
        MacPreferenceRow(title: "scope_media_types") { MacPreferenceValue(value: typesValue) }
      }.buttonStyle(.plain).accessibilityIdentifier("backup.scope.types")
      Button { navigate?(.albums) } label: {
        MacPreferenceRow(title: "scope_albums_title", first: false) { MacPreferenceValue(value: albumsValue) }
      }.buttonStyle(.plain).accessibilityIdentifier("backup.scope.albums")
      if store.loadFailed { DuckNotice(title: "scope_load_failed", tone: .failure) }
    }
    #else
    VStack(alignment: .leading, spacing: 8) {
      IOSPreferenceSection(title: "scope_title") {
        NavigationLink { IOSPrototypeDestination(title: "scope_media_types") { BackupScopeEditor(destination: .types) } } label: {
          IOSPreferenceRow(title: "scope_media_types") { IOSPreferenceValue(value: typesValue) }
        }.buttonStyle(.plain).accessibilityIdentifier("backup.scope.types")
        Divider()
        NavigationLink { IOSPrototypeDestination(title: "scope_albums_title") { BackupScopeEditor(destination: .albums) } } label: {
          IOSPreferenceRow(title: "scope_albums_title") { IOSPreferenceValue(value: albumsValue) }
        }.buttonStyle(.plain).accessibilityIdentifier("backup.scope.albums")
      }
      Text("scope_summary_note").font(.footnote).foregroundStyle(Color.secondary)
      if store.loadFailed { DuckNotice(title: "scope_load_failed", tone: .failure) }
    }
    #endif
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
  override init() {
    super.init()
    // Registering asks for photo access when it has not been decided yet.
    let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if BackupEnvironment.usesPhotoLibrary, access == .authorized || access == .limited { PHPhotoLibrary.shared().register(self) }
  }
  nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
    Task { @MainActor [weak self] in self?.lastLoad = nil }
  }
  func load(requestPermission: Bool = false, selectedIDs: Set<String> = []) async {
    guard !loading else { return }; loading = true
    defer { loading = false }
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if requestPermission, status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
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
          system: collection.assetCollectionType == .smartAlbum, cover: photos.firstObject))
      }
      PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { collection, _, _ in append(collection) }
      // Resolve existing explicit choices without enumerating every smart album.
      PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(selectedIDs), options: nil).enumerateObjects { collection, _, _ in append(collection) }
      return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }.value
    loadedSelections = selectedIDs; lastLoad = Date(); lastAuthorization = status
  }
}

struct BackupScopeEditor: View {
  let destination: BackupScopeDestination
  #if os(macOS)
  /// The sheet owns the opened album so its title and Back follow it.
  var opened: Binding<ScopeAlbum?> = .constant(nil)
  #endif
  @ObservedObject private var store = BackupScopeStore.shared
  @StateObject private var model = ScopeAlbumsModel.shared
  @State private var search = ""
  #if os(iOS)
  @State private var openedAlbum: ScopeAlbum?
  #else
  private var openedAlbum: ScopeAlbum? {
    get { opened.wrappedValue }
    nonmutating set { opened.wrappedValue = newValue }
  }
  #endif
  var body: some View {
    Group {
      #if os(macOS)
      NavigationStack { searchableContent }
      #else
      searchableContent
      #endif
    }
    #if os(macOS)
    .opacity(openedAlbum == nil ? 1 : 0).allowsHitTesting(openedAlbum == nil)
    .accessibilityHidden(openedAlbum != nil)
    .overlay { if let openedAlbum { MacScopeAlbumBrowser(album: openedAlbum) } }
    #else
    .navigationDestination(item: $openedAlbum) { album in ScopeAlbumBrowser(album: album) }
    #endif
    .task { if destination == .albums { await model.load(selectedIDs: store.rule.usesSpecifiedAlbums ? store.rule.albums : []) } }
  }

  @ViewBuilder private var searchableContent: some View {
    if destination == .albums {
      scopeContent.searchable(text: $search, prompt: Text("scope_search_albums"))
    } else { scopeContent }
  }

  @ViewBuilder private var scopeContent: some View {
    if destination == .types {
      Form { Section { typeChoices } }.formStyle(.grouped)
    } else if model.denied {
      ContentUnavailableView {
        Label("photos_access_title", systemImage: "photo.badge.exclamationmark")
      } description: {
        Text("photos_permission_needed")
      } actions: {
        Button("library_request_access") {
          Task { await model.load(requestPermission: true, selectedIDs: store.rule.usesSpecifiedAlbums ? store.rule.albums : []) }
        }.duckPrimaryButton()
      }
    } else {
      albumList
    }
  }

  private var albumList: some View {
    let chosen = store.rule.usesSpecifiedAlbums ? store.rule.albums : []
    let visible = model.albums.filter { (!$0.system || chosen.contains($0.id))
      && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    return List {
      Section {
        Toggle("scope_all_albums", isOn: allAlbums)
          .accessibilityIdentifier("backup.scope.all_albums")
      } footer: {
        Text(store.rule.usesSpecifiedAlbums ? String(format: NSLocalizedString("scope_album_count", comment: ""), store.rule.albums.count)
          : NSLocalizedString("scope_all_albums_summary", comment: ""))
          .accessibilityIdentifier("backup.scope.album_count")
      }
      Section {
        if visible.isEmpty && !model.loading {
          ContentUnavailableView {
            Label("scope_albums_empty", systemImage: search.isEmpty ? "rectangle.stack" : "magnifyingglass")
          } description: { Text("scope_summary_note") } actions: {
            if !search.isEmpty { Button("library_show_all") { search = "" }.buttonStyle(.bordered) }
            else {
              Button("retry_task") {
                Task { await model.load(selectedIDs: store.rule.usesSpecifiedAlbums ? store.rule.albums : []) }
              }.buttonStyle(.bordered)
            }
          }
        }
        ForEach(visible) { album in
          Button { selectAlbum(album) } label: {
            HStack(spacing: DuckSpacing.small) {
              ReadOnlyMediaThumbnail(asset: album.cover, width: 44, height: 44)
              VStack(alignment: .leading) {
                Text(album.name).font(.body).foregroundStyle(.primary)
                Text(albumItemCount(album.count)).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "checkmark").foregroundStyle(DuckRole.accent)
                .opacity(chosen.contains(album.id) ? 1 : 0).accessibilityHidden(true)
            }.frame(minHeight: DuckPreferenceMetrics.rowHeight)
          }
          .buttonStyle(.borderless)
          .contextMenu {
            Button("scope_album_view") { openAlbum(album) }
            Button(chosen.contains(album.id) ? "scope_album_deselect" : "scope_album_choose") { selectAlbum(album) }
          }
          .accessibilityAction(named: Text("scope_album_view")) { openAlbum(album) }
          .accessibilityIdentifier("backup.scope.album." + album.id)
          .accessibilityAddTraits(chosen.contains(album.id) ? .isSelected : [])
        }
      }
      missingAlbums
    }
    #if os(iOS)
    .listStyle(.insetGrouped)
    #else
    .listStyle(.inset)
    #endif
    .overlay { if model.loading { ProgressView("library_loading") } }
    .accessibilityIdentifier("backup.scope.choices")
  }
  private var missingAlbums: some View {
    let missing = store.rule.usesSpecifiedAlbums ? store.rule.albums.subtracting(Set(model.albums.map(\.id))) : []
    return VStack(alignment: .leading, spacing: 8) {
      if !model.loading && !missing.isEmpty {
        Text("scope_album_unavailable").font(.headline)
        ForEach(missing.sorted(),id: \.self) { id in
          choiceRow(title: store.rule.albumNames[id] ?? NSLocalizedString("scope_album_unavailable",comment: ""),symbol: "rectangle.slash",selected: store.rule.restrictAlbums) {
            var next = store.rule; next.albums.remove(id); next.albumNames.removeValue(forKey: id); store.save(next)
          }
        }
      }
    }
  }
  private var allAlbums: Binding<Bool> {
    Binding(get: { !store.rule.restrictAlbums }, set: { enabled in
      var next = store.rule
      next.restrictAlbums = !enabled; next.albums = []; next.albumNames = [:]
      store.save(next)
    })
  }
  private func selectAlbum(_ album: ScopeAlbum) {
    store.save(store.rule.toggling(album: album.id, name: album.name))
  }
  /// Browsing reads the album only: it changes neither the scope nor any work.
  private func openAlbum(_ album: ScopeAlbum) {
    openedAlbum = album
  }
  private var typeChoices: some View {
    ForEach(BackupMediaKind.allCases) { kind in
      choiceRow(title: NSLocalizedString(kind.title, comment: ""), symbol: kind.symbol, selected: store.rule.types.contains(kind)) {
        var next = store.rule
        if next.types.contains(kind) { next.types.remove(kind) } else { next.types.insert(kind) }
        store.save(next)
      }.accessibilityIdentifier("backup.scope.type." + kind.rawValue)
    }
  }
  private func choiceRow(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: DuckSpacing.small) {
        Label(title, systemImage: symbol).foregroundStyle(.primary)
        Spacer()
        Image(systemName: "checkmark").foregroundStyle(DuckRole.accent)
          .opacity(selected ? 1 : 0).accessibilityHidden(true)
      }.font(.body).frame(minHeight: DuckPreferenceMetrics.rowHeight).contentShape(Rectangle())
    }.buttonStyle(.borderless).transaction { $0.animation = nil }
      .accessibilityAddTraits(selected ? .isSelected : [])
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
      RoundedRectangle(cornerRadius: 7).fill(DuckRole.groupedSurface)
      if let image {
        #if os(macOS)
        Image(nsImage: image).resizable().scaledToFill()
        #else
        Image(uiImage: image).resizable().scaledToFill()
        #endif
      } else { Image(systemName: "rectangle.stack").foregroundStyle(Color.secondary) }
    }.frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
      .task(id: "\(asset?.localIdentifier ?? "")|\(Int(width*displayScale))|\(Int(height*displayScale))|\(policy.choice)") {
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
      .onDisappear { identity = nil; ScopeThumbnailCache.pipeline.cancel(request) }
  }
}

/// Album/strip posters are local, cancellable and reused across choice edits.
@MainActor enum ScopeThumbnailCache {
  static let pipeline = ThumbnailPipeline(cacheBudget: 24*1024*1024)
}

func albumItemCount(_ count: Int) -> String {
  String(format: NSLocalizedString(count == 1 ? "scope_album_item" : "scope_album_items",comment: ""),count.formatted())
}

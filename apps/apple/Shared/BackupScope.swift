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
  func includes(kind: BackupMediaKind?, id: String, albumMembers: Set<String>) -> Bool {
    guard let kind, types.contains(kind) else { return false }
    return !restrictAlbums || albumMembers.contains(id)
  }
  /// PhotoKit owns library membership. Capture only matching IDs, never media bytes.
  func selectedIDs(from identifiers: Set<String>? = nil) -> Set<String> {
    var albumMembers: Set<String> = []
    if restrictAlbums {
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
  func save(_ next: BackupScopeRule) {
    guard let data = try? JSONEncoder().encode(next) else { return }
    defaults.set(data, forKey: "photoBackupScope"); rule = next; loadFailed = false
  }
  var summary: String {
    let types = BackupMediaKind.allCases.filter { rule.types.contains($0) }.map { NSLocalizedString($0.title, comment: "") }.joined(separator: ", ")
    if types.isEmpty { return NSLocalizedString("scope_empty", comment: "") }
    return types + " · " + (rule.restrictAlbums
      ? String(format: NSLocalizedString("scope_album_count", comment: ""), rule.albums.count)
      : NSLocalizedString("scope_all_albums", comment: ""))
  }
}
enum BackupScopeDestination: String, Identifiable {
  case types, albums
  var id: String { rawValue }
  var title: String { self == .types ? "scope_media_types" : "scope_albums_title" }
}

struct BackupScopeSettings: View {
  @ObservedObject private var store = BackupScopeStore.shared
  var navigate: ((BackupScopeDestination) -> Void)? = nil
  private var typesValue: String {
    store.rule.types.count == BackupMediaKind.allCases.count ? NSLocalizedString("scope_all_types", comment: "")
      : BackupMediaKind.allCases.filter { store.rule.types.contains($0) }.map { NSLocalizedString($0.title, comment: "") }.joined(separator: ", ")
  }
  private var albumsValue: String {
    store.rule.restrictAlbums ? String(format: NSLocalizedString("scope_album_count", comment: ""), store.rule.albums.count)
      : NSLocalizedString("scope_all_albums", comment: "")
  }
  var body: some View {
    #if os(macOS)
    MacPreferenceGroup(title: "scope_title", note: "scope_summary_note") {
      Button { navigate?(.types) } label: {
        MacPreferenceRow(title: "scope_media_types") { MacPreferenceValue(value: typesValue.isEmpty ? NSLocalizedString("scope_empty", comment: "") : typesValue) }
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
          IOSPreferenceRow(title: "scope_media_types") { IOSPreferenceValue(value: typesValue.isEmpty ? NSLocalizedString("scope_empty", comment: "") : typesValue) }
        }.buttonStyle(.plain).accessibilityIdentifier("backup.scope.types")
        Divider()
        NavigationLink { IOSPrototypeDestination(title: "scope_albums_title") { BackupScopeEditor(destination: .albums) } } label: {
          IOSPreferenceRow(title: "scope_albums_title") { IOSPreferenceValue(value: albumsValue) }
        }.buttonStyle(.plain).accessibilityIdentifier("backup.scope.albums")
      }
      Text("scope_summary_note").font(.footnote).foregroundStyle(DuckColors.textSecondary)
      if store.loadFailed { DuckNotice(title: "scope_load_failed", tone: .failure) }
    }
    #endif
  }
}

private struct ScopeAlbum: Identifiable {
  let id: String
  let name: String
  let count: Int
  let system: Bool
  let cover: PHAsset?
}
@MainActor private final class ScopeAlbumsModel: ObservableObject {
  @Published var albums: [ScopeAlbum] = []
  @Published var loading = false
  @Published var denied = false
  func load(requestPermission: Bool = false) async {
    guard !loading else { return }; loading = true
    defer { loading = false }
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if requestPermission, status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
    denied = status != .authorized && status != .limited
    guard !denied else { return }
    albums = await Task.detached(priority: .utility) {
      var result: [ScopeAlbum] = []
      for type in [PHAssetCollectionType.album, .smartAlbum] {
        PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil).enumerateObjects { collection, _, _ in
          guard let name = collection.localizedTitle else { return }
          let options = photoLibraryFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
          let photos = PHAsset.fetchAssets(in: collection, options: options)
          result.append(ScopeAlbum(id: collection.localIdentifier, name: name, count: photos.count, system: type == .smartAlbum, cover: photos.firstObject))
        }
      }
      return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }.value
  }
}

struct BackupScopeEditor: View {
  let destination: BackupScopeDestination
  @ObservedObject private var store = BackupScopeStore.shared
  @StateObject private var model = ScopeAlbumsModel()
  @State private var search = ""
  @FocusState private var searchFocused: Bool
  @Environment(\.dynamicTypeSize) private var textSize
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if destination == .albums {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass").foregroundStyle(DuckColors.textSecondary)
          TextField("scope_search_albums", text: $search).textFieldStyle(.plain).focused($searchFocused)
            .accessibilityIdentifier("backup.scope.album_search")
          if !search.isEmpty {
            Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DuckColors.textSecondary) }
              .buttonStyle(.plain).accessibilityLabel(Text("close"))
          }
        }.padding(10).background(DuckColors.subtle,in: RoundedRectangle(cornerRadius: 10))
          .padding(.horizontal, 16).padding(.top, 12)
        Text(store.rule.restrictAlbums ? String(format: NSLocalizedString("scope_album_count", comment: ""), store.rule.albums.count) : NSLocalizedString("scope_all_albums", comment: ""))
          .font(.callout).foregroundStyle(DuckColors.textSecondary).padding(.horizontal, 16)
          .accessibilityIdentifier("backup.scope.album_count")
      }
      if model.denied && destination == .albums {
        DuckNotice(title: "photos_permission_needed").padding(16)
        Button("library_request_access") { Task { await model.load(requestPermission: true) } }.duckPrimaryAction().padding(16)
      } else if destination == .types {
        #if os(macOS)
        MacPreferenceGroup { typeChoices }
        #else
        ScrollView { IOSPreferenceGroup { typeChoices }.padding(20) }
        #endif
      } else {
        #if os(iOS)
        if !textSize.isAccessibilitySize {
          ScrollView {
            VStack(alignment: .leading, spacing: 20) {
              choiceRow(title: NSLocalizedString("scope_all_albums",comment: ""), symbol: "rectangle.stack", selected: !store.rule.restrictAlbums) {
                var next = store.rule; next.restrictAlbums = false; store.save(next)
              }.padding(.horizontal,16).background(DuckColors.surface,in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("backup.scope.all_albums")
              albumCards(system: false,title: "scope_my_albums")
              albumCards(system: true,title: "scope_system_albums")
              missingAlbums
            }.padding(16)
          }.accessibilityIdentifier("backup.scope.choices")
        } else { albumList }
        #else
        albumList
        #endif
        if model.loading && destination == .albums { ProgressView("library_loading").frame(maxWidth: .infinity) }
      }
    }.background(DuckColors.canvas).tint(DuckColors.action)
      .task { if destination == .albums { await model.load() } }
      #if os(macOS)
      .frame(height: destination == .albums ? 440 : 208, alignment: .top)
      #endif
  }
  private var albumList: some View {
    List {
            Section {
              choiceRow(title: NSLocalizedString("scope_all_albums", comment: ""), symbol: "rectangle.stack", selected: !store.rule.restrictAlbums) {
                var next = store.rule; next.restrictAlbums = false; store.save(next)
              }.accessibilityIdentifier("backup.scope.all_albums")
            }
            albumSection(system: false, title: "scope_my_albums")
            albumSection(system: true, title: "scope_system_albums")
            let missing = store.rule.albums.subtracting(Set(model.albums.map(\.id)))
            if !missing.isEmpty {
              Section("scope_album_unavailable") {
                ForEach(missing.sorted(), id: \.self) { id in
                  choiceRow(title: store.rule.albumNames[id] ?? NSLocalizedString("scope_album_unavailable", comment: ""), symbol: "rectangle.slash", selected: store.rule.restrictAlbums) {
                    var next = store.rule; next.albums.remove(id); next.albumNames.removeValue(forKey: id); store.save(next)
                  }
                }
              }
            }
        }
      #if os(iOS)
          .listStyle(.insetGrouped)
          #else
          .listStyle(.inset)
          #endif
          .environment(\.defaultMinListRowHeight, DuckPreferenceMetrics.rowHeight)
          .scrollContentBackground(.hidden)
          .accessibilityIdentifier("backup.scope.choices")
  }
  private var missingAlbums: some View {
    let missing = store.rule.albums.subtracting(Set(model.albums.map(\.id)))
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
  private func selectAlbum(_ album: ScopeAlbum) {
    searchFocused = false
    var next = store.rule
    if !next.restrictAlbums { next.albums = []; next.albumNames = [:] }
    next.restrictAlbums = true
    if next.albums.contains(album.id) { next.albums.remove(album.id); next.albumNames.removeValue(forKey: album.id) }
    else { next.albums.insert(album.id); next.albumNames[album.id] = album.name }
    store.save(next)
  }
  @ViewBuilder private func albumCards(system: Bool,title: LocalizedStringKey) -> some View {
    let visible = model.albums.filter { $0.system == system && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    if !visible.isEmpty {
      Text(title).font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140,maximum: 240),spacing: 16)],alignment: .leading,spacing: 20) {
        ForEach(visible) { album in
          Button { selectAlbum(album) } label: {
            VStack(alignment: .leading,spacing: 5) {
              GeometryReader { geometry in
                ReadOnlyMediaThumbnail(asset: album.cover,width: geometry.size.width,height: geometry.size.height)
                  .overlay(alignment: .topTrailing) {
                    if store.rule.restrictAlbums && store.rule.albums.contains(album.id) {
                      Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(DuckColors.action)
                        .background(DuckColors.surface,in: Circle()).padding(8)
                    }
                  }
              }.aspectRatio(1,contentMode: .fit)
              Text(album.name).font(.body.weight(.medium)).foregroundStyle(DuckColors.text).lineLimit(2)
              Text(album.count.formatted()).font(.caption).foregroundStyle(DuckColors.textSecondary)
            }.frame(maxWidth: .infinity,alignment: .leading).contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityLabel(Text(album.name)).accessibilityValue(Text(album.count.formatted()))
            .accessibilityAddTraits(store.rule.restrictAlbums && store.rule.albums.contains(album.id) ? .isSelected : [])
        }
      }
    }
  }
  private var typeChoices: some View {
    VStack(spacing: 0) {
      ForEach(Array(BackupMediaKind.allCases.enumerated()), id: \.element.id) { index,kind in
        if index > 0 { Divider() }
        choiceRow(title: NSLocalizedString(kind.title, comment: ""), symbol: kind.symbol, selected: store.rule.types.contains(kind)) {
          var next = store.rule
          if next.types.contains(kind) { next.types.remove(kind) } else { next.types.insert(kind) }
          store.save(next)
        }.accessibilityIdentifier("backup.scope.type." + kind.rawValue)
        #if os(iOS)
        .padding(.horizontal,16)
        #endif
      }
    }
  }
  @ViewBuilder private func albumSection(system: Bool, title: LocalizedStringKey) -> some View {
    let visible = model.albums.filter { $0.system == system && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    if !visible.isEmpty {
      Section(title) {
        ForEach(visible) { album in
          Button { selectAlbum(album)          } label: {
            HStack(spacing: 12) {
              ReadOnlyMediaThumbnail(asset: album.cover)
              VStack(alignment: .leading, spacing: 4) {
                Text(album.name).foregroundStyle(DuckColors.text)
                Text(album.count.formatted()).font(.caption).foregroundStyle(DuckColors.textSecondary)
              }
              Spacer(minLength: 12)
              selectionMark(store.rule.restrictAlbums && store.rule.albums.contains(album.id))
            }.frame(minHeight: DuckPreferenceMetrics.rowHeight).contentShape(Rectangle())
          }.buttonStyle(.plain).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .accessibilityLabel(Text(album.name)).accessibilityValue(Text(album.count.formatted()))
            .accessibilityAddTraits(store.rule.restrictAlbums && store.rule.albums.contains(album.id) ? .isSelected : [])
        }
      }
    }
  }
  private func choiceRow(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol).frame(width: 24).foregroundStyle(DuckColors.textSecondary)
        Text(title).foregroundStyle(DuckColors.text)
        Spacer(minLength: 12)
        selectionMark(selected)
      }.frame(maxWidth: .infinity, minHeight: DuckPreferenceMetrics.rowHeight, alignment: .leading).contentShape(Rectangle())
    }.buttonStyle(.plain).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
  private func selectionMark(_ selected: Bool) -> some View {
    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(DuckColors.action)
      .frame(width: 24).opacity(selected ? 1 : 0).accessibilityHidden(true)
  }
}

struct ReadOnlyMediaThumbnail: View {
  let asset: PHAsset?
  var width: CGFloat = 44
  var height: CGFloat = 44
  @State private var image: LibraryImage?
  @State private var request = PHInvalidImageRequestID
  @State private var identity: String?
  @State private var requestGeneration = UUID()
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 7).fill(DuckColors.subtle)
      if let image {
        #if os(macOS)
        Image(nsImage: image).resizable().scaledToFill()
        #else
        Image(uiImage: image).resizable().scaledToFill()
        #endif
      } else { Image(systemName: "rectangle.stack").foregroundStyle(DuckColors.textSecondary) }
    }.frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
      .task(id: "\(asset?.localIdentifier ?? "")|\(Int(width))|\(Int(height))") {
        ScopeThumbnailCache.manager.cancelImageRequest(request); image = nil; identity = asset?.localIdentifier
        let generation = UUID(); requestGeneration = generation
        guard let asset else { return }
        guard width > 0, height > 0 else { return }
        let pixels = min(600,max(132,Int(max(width,height)*2)))
        let key = "\(asset.localIdentifier)|\(PhotoLibraryModel.revision(asset))|\(pixels)" as NSString
        if let cached = ScopeThumbnailCache.images.object(forKey: key) { image = cached; return }
        let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = false
        options.resizeMode = .fast; options.deliveryMode = .opportunistic
        request = ScopeThumbnailCache.manager.requestImage(for: asset, targetSize: CGSize(width: pixels, height: pixels), contentMode: .aspectFill, options: options) { value, info in
          Task { @MainActor in
            guard identity == asset.localIdentifier, requestGeneration == generation,
              info?[PHImageCancelledKey] as? Bool != true else { return }
            if let value {
              image = value
              if info?[PHImageResultIsDegradedKey] as? Bool != true {
                ScopeThumbnailCache.images.setObject(value,forKey: key,cost: pixels*pixels*4)
              }
            }
          }
        }
      }.onDisappear { identity = nil; ScopeThumbnailCache.manager.cancelImageRequest(request) }
  }
}

/// Album/strip posters are local, cancellable and reused across choice edits.
@MainActor private enum ScopeThumbnailCache {
  static let manager = PHCachingImageManager()
  static let images: NSCache<NSString, LibraryImage> = {
    let cache = NSCache<NSString, LibraryImage>(); cache.countLimit = 120; cache.totalCostLimit = 24*1024*1024; return cache
  }()
}

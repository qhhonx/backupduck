import Combine
import Foundation
import Photos
import SwiftUI

enum BackupMediaKind: String, Codable, CaseIterable, Identifiable {
  case photo, motion, video, burst
  var id: String { rawValue }
  var title: String { "scope_type_" + rawValue }
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
struct BackupScopeSettings: View {
  @ObservedObject private var store = BackupScopeStore.shared
  @State private var albums: [(id: String, name: String)] = []
  @State private var loading = false
  @State private var denied = false
  #if os(macOS)
  @ScaledMetric(relativeTo: .body) private var labelSize = 14
  @ScaledMetric(relativeTo: .headline) private var headingSize = 16
  #else
  @ScaledMetric(relativeTo: .body) private var labelSize = 16
  @ScaledMetric(relativeTo: .headline) private var headingSize = 19
  #endif
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("scope_title").font(.system(size: headingSize, weight: .semibold))
      Text(store.summary).font(.callout).foregroundStyle(DuckColors.textSecondary)
        .accessibilityIdentifier("backup.scope.summary")
      VStack(spacing: 0) {
        ForEach(BackupMediaKind.allCases) { kind in
          scopeToggle(kind.title, value: store.rule.types.contains(kind)) { enabled in
            var next = store.rule
            if enabled { next.types.insert(kind) } else { next.types.remove(kind) }; store.save(next)
          }.accessibilityIdentifier("backup.scope.type." + kind.rawValue)
          Divider()
        }
        scopeToggle("scope_restrict_albums", value: store.rule.restrictAlbums) { enabled in
          var next = store.rule; next.restrictAlbums = enabled; store.save(next)
          if enabled { Task { await loadAlbums(requestPermission: true) } }
        }.accessibilityIdentifier("backup.scope.albums_only")
        if store.rule.restrictAlbums {
          Divider()
          if loading { ProgressView("library_loading").padding(16) }
          else if denied {
            Text("photos_permission_needed").padding(16)
            Button("library_request_access") { Task { await loadAlbums(requestPermission: true) } }.padding(16)
          } else {
            ForEach(albums, id: \.id) { album in
              scopeToggle(album.name, localized: false, value: store.rule.albums.contains(album.id)) { enabled in
                var next = store.rule
                if enabled { next.albums.insert(album.id); next.albumNames[album.id] = album.name }
                else { next.albums.remove(album.id); next.albumNames.removeValue(forKey: album.id) }; store.save(next)
              }
              Divider()
            }
            ForEach(Array(store.rule.albums.subtracting(Set(albums.map(\.id)))).sorted(), id: \.self) { id in
              scopeToggle(store.rule.albumNames[id] ?? NSLocalizedString("scope_album_unavailable", comment: ""), localized: false, value: true) { _ in
                var next = store.rule; next.albums.remove(id); next.albumNames.removeValue(forKey: id); store.save(next)
              }
              Text("scope_album_unavailable").font(.caption).foregroundStyle(DuckColors.textSecondary).padding(.horizontal, 16)
            }
            if albums.isEmpty { Text("scope_albums_empty").padding(16) }
          }
        }
      }.background(DuckColors.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(DuckColors.border) }
      Text("scope_note").font(.footnote).foregroundStyle(DuckColors.textSecondary)
      if store.loadFailed { DuckNotice(title: "scope_load_failed", tone: .failure) }
    }.task { await loadAlbums(requestPermission: false) }
  }
  private func scopeToggle(_ title: String, localized: Bool = true, value: Bool, save: @escaping (Bool) -> Void) -> some View {
    Toggle(isOn: Binding(get: { value }, set: save)) {
      if localized { Text(LocalizedStringKey(title)) } else { Text(title) }
    }
      .font(.system(size: labelSize)).toggleStyle(.switch).padding(.horizontal, 16).padding(.vertical, 8)
      .frame(minHeight: DuckPreferenceMetrics.rowHeight)
  }
  private func loadAlbums(requestPermission: Bool) async {
    guard !loading else { return }; loading = true
    defer { loading = false }
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if requestPermission, status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
    denied = status != .authorized && status != .limited
    guard !denied else { return }
    albums = await Task.detached(priority: .utility) {
      var names: [String: String] = [:]
      for type in [PHAssetCollectionType.album, .smartAlbum] {
        PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil).enumerateObjects { collection, _, _ in
          if let title = collection.localizedTitle { names[collection.localIdentifier] = title }
        }
      }
      return names.map { (id: $0.key, name: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }.value
  }
}

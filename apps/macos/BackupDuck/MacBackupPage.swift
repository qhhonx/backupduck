import Photos
import SwiftUI

struct MacBackupPage: View {
  @ObservedObject var model: BackupModel
  @ObservedObject var folders: FolderSources = .shared
  var pair: () -> Void
  var library: () -> Void
  var sources: () -> Void
  var receiver: () -> Void = {}
  var showTransfers: (String) -> Void
  @State private var sourcePreferences = false

  var body: some View {
    ScrollView {
      if !model.ready {
        DuckNotice(title: "backup_initializing").padding(28)
      } else if model.pairing == nil {
        VStack(spacing: 20) {
          DuckBrandMark(size: 64)
          Text("mac_fidelity_connect_first").font(.system(size: 26, weight: .semibold))
          Text("mac_fidelity_connect_first_note").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
          Button("mac_fidelity_connect_receiver", action: receiver).duckPrimaryAction()
        }.frame(maxWidth: .infinity).padding(.vertical, 50).padding(.horizontal, 24)
      } else { pairedContent }
    }.background(DuckRole.background)
      .sheet(isPresented: $sourcePreferences) {
        MacBackupPreferences(model: model)
      }
  }
  private var pairedContent: some View {
      VStack(alignment: .leading, spacing: MacContentMetrics.sectionSpacing) {
        DuckActions {
          VStack(alignment: .leading, spacing: 6) {
            Text("backup_overview_heading").font(.system(size: 26, weight: .semibold))
            Text("apple_backup_total_note").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
          }
          Spacer(minLength: 12)
        }
        HStack(alignment: .top, spacing: 20) {
          DuckBackupProgress(model: model, showTransfers: { showTransfers("all") })
            .frame(maxWidth: .infinity)
          receiverSummary.frame(width: 240)
        }


        MacContentSection(title: "backup_settings", actionTitle: "backup_more_settings",
          actionIdentifier: "backup.manage_source", action: { sourcePreferences = true }) {
        MacPreferenceGroup {
          MacPreferenceRow(title: "auto_backup_new") {
            Toggle("auto_backup_new", isOn: Binding(get: { model.autoBackup }, set: { enabled in Task { await model.setAutoBackup(enabled) } }))
              .labelsHidden().toggleStyle(.switch).disabled(model.changingAutoBackup)
              .accessibilityIdentifier("backup.auto_backup")
          }
          if let error = model.autoBackupError { DuckNotice(title: LocalizedStringKey(error), tone: .failure) }
          Button(action: sources) {
            MacPreferenceRow(title: "mac_nav_sources", first: false) {
              MacPreferenceValue(value: folders.loadFailed ? NSLocalizedString("mac_folder_settings_unavailable", comment: "") : String(format: NSLocalizedString("mac_sources_count", comment: ""), folders.sources.count), width: 168)
            }
          }.buttonStyle(.plain).help("design_manage_folders").accessibilityIdentifier("backup.manage_folders")
        }
        }
        DuckRecentTransfers(model: model, showTransfers: { showTransfers("all") })


      }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
  }
  private var receiverSummary: some View {
    DuckSurface {
      VStack(alignment: .leading, spacing: 12) {
        Text(model.peerDevice?.name ?? NSLocalizedString("receiver_paired", comment: "")).font(.system(size: 16, weight: .semibold))
        Text("mac_receiver_paired_subtitle").font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
        if let endpoint = model.pairing?.endpoint {
          Text(endpoint).font(.system(size: 14)).foregroundStyle(DuckColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        Button("mac_receiver_device_details", action: receiver).duckSecondaryAction()

      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct MacBackupPreferences: View {
  @ObservedObject var model: BackupModel
  @Environment(\.dismiss) private var dismiss
  @State private var scopeDestination: BackupScopeDestination?
  private var title: LocalizedStringKey {
    return LocalizedStringKey(scopeDestination?.title ?? "backup_settings")
  }
  private func back() { scopeDestination = nil }
  private var busy: Bool { model.changingHistory || model.changingAutoBackup || model.savingConcurrency }
  var body: some View {
    DuckSheetLayout(title: title, busy: busy,
      desktopMinHeight: scopeDestination == .types ? 340 : 360,
      desktopIdealHeight: scopeDestination == .types ? 392 : scopeDestination == .albums ? 640 : 560,
      back: scopeDestination == nil ? nil : back) {
      if let scopeDestination {
        NavigationStack { BackupScopeEditor(destination: scopeDestination) }
      } else {
      MacPreferenceGroup(title: "source_system_library") { DuckLibrarySource(model: model, compactMac: true) }
      BackupScopeSettings(navigate: { scopeDestination = $0 })
      MacPreferenceGroup(title: "transfer_settings", layout: .content) { MacConcurrencyPanel(model: model) }
      MacPreferenceGroup(title: "history_title", layout: .content) { HistoricalImportSettings(model: model) }
      }
    } actions: {
      Button("settings_done") {
        if scopeDestination != nil { back() } else { dismiss() }
      }.duckSecondaryAction().disabled(busy)
    }
  }
}

/// One album's photos in the Mac library grid, read-only, inside the backup
/// settings sheet. Its own scoped model keeps the main library's fetch,
/// selection and scroll untouched; browsing registers no work.
struct MacScopeAlbumBrowser: View {
  let album: ScopeAlbum
  @StateObject private var library: PhotoLibraryModel
  @StateObject private var navigation = MacLibraryNavigation()
  @ObservedObject private var store: BackupScopeStore
  @ObservedObject private var model = BackupModel.shared
  @State private var columns = MacLibraryDensity.standard
  @MainActor init(album: ScopeAlbum, store: BackupScopeStore? = nil) {
    self.album = album
    self.store = store ?? .shared
    _library = StateObject(wrappedValue: PhotoLibraryModel(collection: album.id))
  }
  var body: some View {
    content.frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(album.name)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          let chosen = store.rule.choosesAlbum(album.id)
          Button(chosen ? "scope_album_deselect" : "scope_album_choose") {
            store.save(store.rule.toggling(album: album.id, name: album.name))
          }.accessibilityIdentifier("backup.scope.album_browser.choose")
        }
      }
      .task {
        if BackupEnvironment.usesPhotoLibrary { await library.open() }
        else { library.applyAuthorization(.denied) }
      }
      .onDisappear { library.thumbnails.clear() }
  }
  @ViewBuilder private var content: some View {
    switch library.placeholder {
    case .loading?: DuckLoadingState("library_loading")
    case .empty?:
      Text("scope_album_no_photos").foregroundStyle(DuckColors.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("backup.scope.album_browser.empty")
    case let placeholder?:
      MacLibraryPlaceholder(kind: placeholder, requestingAccess: library.requestingPermission,
        requestAccess: {
          guard BackupEnvironment.usesPhotoLibrary else { return }
          Task { await library.open(requestPermission: true) }
        }, clearFilter: {})
    case nil:
      // The sheet's first pass proposes a near-zero width; a grid laid out then
      // showed one frame of 1 pt cells. Mount it once the page has its width.
      GeometryReader { proxy in
        if proxy.size.width > 120 {
          MacLibraryGrid(library: library, navigation: navigation,
            preparationRevision: "\(model.pendingImports)|\(model.importingSourceID ?? "")",
            queueRevision: model.queueRevision, receiverID: model.pairing?.receiverID,
            columns: columns, selecting: false, prefillsTables: false, resize: { columns = $0 })
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityIdentifier("backup.scope.album_browser")
        }
      }
    }
  }
}

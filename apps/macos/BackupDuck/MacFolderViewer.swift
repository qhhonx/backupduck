import AppKit
import AVKit
import ImageIO
import SwiftUI

/// File-backed adapter for the shared window-scoped viewer.
@MainActor enum MacFolderViewer {
  static func open(_ photo: FolderPhoto, context: [FolderPhoto], folders: FolderSources) {
    MacPhotoViewerWindow.openFolder(photo, context: context, folders: folders)
  }
}
struct FolderViewer: View {
  @State var photo: FolderPhoto
  let context: [FolderPhoto]
  @ObservedObject var folders: FolderSources
  @ObservedObject var navigation: MacLibraryNavigation
  var close: (FolderPhoto) -> Void
  @ObservedObject private var model = BackupEnvironment.activeModel()
  @StateObject private var facts = MacViewerFacts()
  @State private var history = false
  @Environment(\.macViewerHistory) private var openHistory
  @State private var image: NSImage?
  @State private var player: AVPlayer?
  @State private var failure = false
  @State private var zoomed = false
  @State private var root: URL?
  var body: some View {
    Group {
      if let player { MacVideoWithPoster(player: player, image: image) }
      else if let image { MacMediaZoom(image: image, livePhoto: nil, playRequest: 0, fitRevision: 0, zoomed: { zoomed = $0 }) }
      else if failure {
        ContentUnavailableView { Label("library_preview_unavailable", systemImage: "photo.badge.exclamationmark") }
          actions: { Button("retry_task") { Task { await load() } } }
      } else { ProgressView("library_loading") }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(DuckSpacing.large)
    .background(DuckRole.background)
    .inspector(isPresented: $navigation.viewerInfo) {
      ScrollView {
        PhotoInformationLayout(takenAt: photo.date, job: facts.job,
          receiverName: facts.job.flatMap { model.receiverDeviceName(for: $0) } ?? model.peerDevice?.name ?? "Pixel",
          needsYou: photo.backup == "needs_you", filename: (photo.relative as NSString).lastPathComponent,
          fields: fileFields, model: model, loaded: facts.loaded, unavailable: facts.unavailable,
          preparing: facts.working || photo.backup == "sending", allowsRetry: false,
          showHistory: facts.job == nil ? nil : {
            if let job = facts.job, let openHistory { openHistory(HistoryPhoto(job: job)) } else { history = true }
          },
          actionKey: photo.canBackUp ? (photo.backup == "needs_you" ? "retry_task" : "library_context_backup") : nil,
          actionBusy: facts.working, performAction: requestBackup, actionFailure: facts.error,
          backupFacts: facts.job == nil && photo.backup == "saved" ? AnyView(savedFact) : nil)
          .padding(DuckSpacing.large)
      }.inspectorColumnWidth(min: 240, ideal: 290, max: 380)
    }
    .background(MacMediaKeyHandler { event in
      if event.keyCode == 53 { close(photo); return true }
      if event.modifierFlags.intersection([.command, .option, .control]).isEmpty, !zoomed {
        if event.keyCode == 123 { move(-1); return true }
        if event.keyCode == 124 { move(1); return true }
      }
      return false
    })
    .task(id: "\(photo.id)|\(model.queueRevision)|\(folders.revision)") {
      await facts.load(source: photo.source_id, revision: photo.revision, model: model, fallback: photo.backup)
      describe()
    }
    .onChange(of: facts.stateKey) { _, _ in describe() }
    .onChange(of: facts.job) { _, _ in describe() }
    .sheet(isPresented: $history) {
      NavigationStack {
        BackupHistoryView(model: model, initialFocus: facts.job.map(HistoryPhoto.init)).navigationTitle("records_title")
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("records_done") { history = false } } }
      }.frame(minWidth: 640, minHeight: 480)
    }
    .onAppear { navigation.viewerBack = { close(photo) } }
    .task(id: photo.id) { await load() }
    .onDisappear { player?.pause(); root?.stopAccessingSecurityScopedResource(); root = nil; navigation.viewerShare = nil; navigation.viewerBack = nil }
  }
  private var fileFields: [(String, String)] {
    var fields = [("preview_file_size", ByteCountFormatter.string(fromByteCount: Int64(clamping: photo.size), countStyle: .file)),
      ("preview_format", photo.media_type)]
    if photo.date_source == "file_modified" { fields.append(("design_capture_time", NSLocalizedString("folders_date_fallback", comment: ""))) }
    return fields
  }
  private var savedFact: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.small) {
      Label("records_fact_saved", systemImage: "checkmark.circle.fill").foregroundStyle(DuckRole.primaryText)
      if let time = photo.saved_at_ms {
        Text(Date(timeIntervalSince1970: Double(time) / 1000).formatted(date: .abbreviated, time: .shortened))
          .font(.callout).foregroundStyle(.secondary)
      }
    }
  }
  private func describe() {
    navigation.viewerTitle = MacViewerTitle.date(photo.date)
    navigation.viewerSubtitle = MacViewerTitle.subtitle(photo.date, index: index + 1, total: context.count)
    navigation.viewerState = facts.stateKey; navigation.viewerProgress = facts.progress
  }
  private func requestBackup() {
    guard !facts.working else { return }
    let source = photo.id
    Task {
      facts.working = true
      if let job = facts.job, job.state == "failed" || job.processing == "failed" {
        facts.error = await model.retry(job.id) ? nil : model.message
      } else { facts.error = await folders.backUp([photo]) ? nil : folders.error }
      guard photo.id == source else { return }
      await refresh(); facts.working = false
      await facts.load(source: photo.source_id, revision: photo.revision, model: model, fallback: photo.backup); describe()
    }
  }
  private var index: Int { context.firstIndex { $0.id == photo.id } ?? 0 }
  private func move(_ step: Int) {
    let next = index + step
    guard context.indices.contains(next) else { return }
    guard !zoomed else { return }; photo = context[next]
  }
  private func refresh() async {
    if let page = try? await folders.browse(photo.folder_id, offset: 0, search: photo.relative, filter: .all), let latest = page.rows.first(where: { $0.id == photo.id }) { photo = latest }
  }
  private func load() async {
    player?.pause(); player = nil; image = nil; failure = false; zoomed = false
    navigation.viewerShare = nil
    root?.stopAccessingSecurityScopedResource(); root = nil
    if folders.isPreview { image = folders.syntheticImage(photo); navigation.viewerShare = { MacViewerSharing.show(image) }; return }
    guard let source = folders.sources.first(where: { $0.id == photo.folder_id }), let root = folders.sourceURL(source) else { failure = true; return }
    _ = root.startAccessingSecurityScopedResource(); self.root = root
    let file = root.appendingPathComponent(photo.relative).standardizedFileURL
    guard file.path.hasPrefix(root.path + "/"), file.resolvingSymlinksInPath().path == file.path else { failure = true; return }
    navigation.viewerShare = { MacViewerSharing.show(file) }
    let expected = photo.id
    if photo.media_type.hasPrefix("video/") { player = AVPlayer(url: file) }
    else {
      let result = await Task.detached(priority: .userInitiated) { () -> NSImage? in
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
      }.value
      guard !Task.isCancelled, photo.id == expected else { return }
      image = result; failure = result == nil
    }
  }
}

import AppKit
import AVKit
import ImageIO
import SwiftUI

/// File-backed adapter for the library's zoom and AVKit surfaces; one viewer window.
@MainActor enum MacFolderViewer {
  private static var controller: NSWindowController?
  static func toggleInfo() {
    guard controller?.window?.isKeyWindow == true else { return }
    NotificationCenter.default.post(name: Notification.Name("BackupDuckFolderViewerInfo"), object: nil)
  }
  static func open(_ photo: FolderPhoto, context: [FolderPhoto], folders: FolderSources) {
    if let controller { controller.close() }
    let view = FolderViewer(photo: photo, context: context, folders: folders)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = (photo.relative as NSString).lastPathComponent
    window.contentViewController = NSHostingController(rootView: NavigationStack { view }.preferredColorScheme(.dark))
    window.isReleasedWhenClosed = false; window.center()
    let controller = NSWindowController(window: window)
    self.controller = controller; controller.showWindow(nil)
  }
}
private struct FolderViewer: View {
  @State var photo: FolderPhoto
  let context: [FolderPhoto]
  @ObservedObject var folders: FolderSources
  @AppStorage("macPhotoViewerInfo") private var information = true
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
    .background(DuckRole.background)
    .inspector(isPresented: $information) {
      ScrollView {
        VStack(alignment: .leading, spacing: DuckSpacing.medium) {
          Text(photo.date.formatted(date: .long, time: .shortened)).font(.headline)
          Text(LocalizedStringKey(photo.backup == "saved" ? "folders_photo_saved" : photo.backup == "saving" ? "folders_photo_saving" : photo.backup == "sending" ? "folders_photo_sending" : photo.backup == "needs_you" ? "folders_photo_needs_you" : "folders_photo_not_backed_up"))
          if let date = photo.saved_at_ms {
            Text(String(format: NSLocalizedString("folders_saved_confirmed", comment: ""), Date(timeIntervalSince1970: Double(date) / 1000).formatted(date: .abbreviated, time: .shortened))).font(.callout).foregroundStyle(.secondary)
          }
          if photo.canBackUp {
            Button("folders_back_up_selected") {
              Task { if await folders.backUp([photo]) { await refresh() } }
            }.buttonStyle(.borderedProminent)
          }
          Divider()
          Text(photo.relative).textSelection(.enabled)
          Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: photo.size), countStyle: .file))
          if photo.date_source == "file_modified" { Text("folders_date_fallback") }
        }.font(.callout).padding(DuckSpacing.large)
      }.inspectorColumnWidth(min: 240, ideal: 290, max: 380)
    }
    .toolbar {
      ToolbarItemGroup(placement: .navigation) {
        Button { move(-1) } label: { Label("preview_previous", systemImage: "chevron.left") }.disabled(index == 0 || zoomed)
        Button { move(1) } label: { Label("preview_next", systemImage: "chevron.right") }.disabled(index >= context.count - 1 || zoomed)
      }
      ToolbarItem {
        Toggle(isOn: $information) { Label("folders_show_info", systemImage: "info.circle") }
          .toggleStyle(.button)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackupDuckFolderViewerInfo"))) { _ in information.toggle() }
    .task(id: photo.id) { await load() }
    .onDisappear { player?.pause(); root?.stopAccessingSecurityScopedResource(); root = nil }
  }
  private var index: Int { context.firstIndex { $0.id == photo.id } ?? 0 }
  private func move(_ step: Int) {
    let next = index + step
    guard context.indices.contains(next) else { return }
    photo = context[next]
  }
  private func refresh() async {
    if let page = try? await folders.browse(photo.folder_id, offset: 0, search: photo.relative, filter: .all), let latest = page.rows.first(where: { $0.id == photo.id }) { photo = latest }
  }
  private func load() async {
    player?.pause(); player = nil; image = nil; failure = false
    root?.stopAccessingSecurityScopedResource(); root = nil
    if folders.isPreview { image = folders.syntheticImage(photo); return }
    guard let source = folders.sources.first(where: { $0.id == photo.folder_id }), let root = folders.sourceURL(source) else { failure = true; return }
    _ = root.startAccessingSecurityScopedResource(); self.root = root
    let file = root.appendingPathComponent(photo.relative).standardizedFileURL
    guard file.path.hasPrefix(root.path + "/"), file.resolvingSymlinksInPath().path == file.path else { failure = true; return }
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

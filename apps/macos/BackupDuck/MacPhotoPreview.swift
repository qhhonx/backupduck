import AppKit
import AVKit
import Photos
import PhotosUI
import SwiftUI

enum MacLocalPreviewPolicy {
  static func imageOptions() -> PHImageRequestOptions {
    let value = PHImageRequestOptions(); value.isNetworkAccessAllowed = false; value.deliveryMode = .highQualityFormat
    return value
  }
  static func videoOptions() -> PHVideoRequestOptions {
    let value = PHVideoRequestOptions(); value.isNetworkAccessAllowed = false
    return value
  }
  static func liveOptions() -> PHLivePhotoRequestOptions {
    let value = PHLivePhotoRequestOptions(); value.isNetworkAccessAllowed = false; value.deliveryMode = .highQualityFormat
    return value
  }
}

/// Preview only locally available PhotoKit media. It does not export an original
/// or create a backup task; every PhotoKit request forbids network access.
struct MacPhotoPreview: View {
  let asset: PHAsset
  @Environment(\.dismiss) private var dismiss
  @State private var image: NSImage?
  @State private var livePhoto: PHLivePhoto?
  @State private var player: AVPlayer?
  @State private var showingDetails = false
  @State private var unavailable = false
  @State private var requests: [PHImageRequestID] = []
  @State private var active = false
  @State private var playRequest = 0
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Text("library_preview").font(.system(size: 22, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
          .buttonStyle(.plain).accessibilityLabel(Text("close"))
      }.padding(20)
      Divider()
      VStack(spacing: 12) {
        Group {
          if let player { VideoPlayer(player: player).accessibilityIdentifier("library.preview.video") }
          else if let livePhoto {
            VStack(spacing: 12) {
              MacLivePhotoPreview(photo: livePhoto, playRequest: playRequest)
              Button("mac_library_play_live") { playRequest += 1 }.duckSecondaryAction()
            }.accessibilityIdentifier("library.preview.live")
          } else if let image { Image(nsImage: image).resizable().scaledToFit().accessibilityIdentifier("library.preview.photo") }
          else if !unavailable { ProgressView("library_loading") }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        if unavailable { DuckNotice(title: "mac_library_preview_unavailable", tone: .attention).accessibilityIdentifier("library.preview.unavailable") }
        Text("mac_library_preview_local_note").font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
      }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(DuckColors.canvas)
      Divider()
      HStack { Button("apple_photo_detail") { showingDetails = true }.duckSecondaryAction(); Spacer(); Button("settings_done") { dismiss() }.duckSecondaryAction().keyboardShortcut(.cancelAction).accessibilityIdentifier("library.preview.close") }.padding(20)
    }.background(MacSheetInitialFocus().frame(width: 0, height: 0)).frame(width: 760, height: 600).foregroundStyle(DuckColors.text).background(DuckColors.surface)
      .sheet(isPresented: $showingDetails) { DuckPhotoDetail(asset: asset) }
      .onAppear(perform: load).onDisappear {
        active = false
        requests.forEach { PHImageManager.default().cancelImageRequest($0) }
        requests.removeAll(); player?.pause(); player = nil; livePhoto = nil; image = nil
      }
  }
  private func load() {
    guard !active else { return }; active = true
    let size = CGSize(width: 1600, height: 1600)
    let photoOptions = MacLocalPreviewPolicy.imageOptions()
    requests.append(PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: photoOptions) { result, _ in
      Task { @MainActor in
        guard active else { return }; image = result
        if result == nil && player == nil && livePhoto == nil { unavailable = true }
      }
    })
    if asset.mediaType == .video {
      let options = MacLocalPreviewPolicy.videoOptions()
      requests.append(PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
        Task { @MainActor in
          guard active else { return }
          if let item { player = AVPlayer(playerItem: item); unavailable = false }
          else { unavailable = true }
        }
      })
    } else if asset.mediaSubtypes.contains(.photoLive) {
      let options = MacLocalPreviewPolicy.liveOptions()
      requests.append(PHImageManager.default().requestLivePhoto(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { result, _ in
        Task { @MainActor in guard active else { return }; livePhoto = result; unavailable = result == nil }
      })
    }
  }
}

private struct MacLivePhotoPreview: NSViewRepresentable {
  let photo: PHLivePhoto
  let playRequest: Int
  final class Coordinator { var lastPlayRequest = 0 }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> PHLivePhotoView {
    let view = PHLivePhotoView(); view.contentMode = .aspectFit; view.livePhoto = photo
    return view
  }
  func updateNSView(_ view: PHLivePhotoView, context: Context) {
    if view.livePhoto !== photo { view.livePhoto = photo }
    if context.coordinator.lastPlayRequest != playRequest {
      context.coordinator.lastPlayRequest = playRequest; view.startPlayback(with: .full)
    }
  }
  static func dismantleNSView(_ view: PHLivePhotoView, coordinator: Coordinator) { view.stopPlayback(); view.livePhoto = nil }
}

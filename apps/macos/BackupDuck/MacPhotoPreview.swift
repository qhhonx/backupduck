import AppKit
import AVKit
import Photos
import PhotosUI
import SwiftUI

struct MacPhotoPreview: View {
  @ObservedObject var library: PhotoLibraryModel
  @StateObject private var preview: MediaPreviewModel
  @ObservedObject private var policy = PreviewNetworkPolicy.shared
  @Environment(\.dismiss) private var dismiss
  @State private var showingDetails = false
  @State private var playRequest = 0
  @State private var zoom: CGFloat = 1
  @GestureState private var magnification: CGFloat = 1
  @State private var moving = false
  init(asset: PHAsset, library: PhotoLibraryModel) {
    self.library = library; _preview = StateObject(wrappedValue: MediaPreviewModel(asset: asset))
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(preview.asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? NSLocalizedString("library_preview", comment: "")).font(.title2)
        Spacer()
        Button("settings_done") { dismiss() }.duckSecondaryAction().keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("library.preview.close")
      }.padding(20)
      Divider()
      HStack(spacing: 0) {
        VStack(spacing: 12) {
          Group {
            if let player = preview.player { VideoPlayer(player: player).accessibilityIdentifier("library.preview.video") }
            else if let photo = preview.livePhoto {
              MacLivePhotoPreview(photo: photo, playRequest: playRequest)
                .accessibilityIdentifier("library.preview.live")
              Button("mac_library_play_live") { playRequest += 1 }.duckSecondaryAction()
            } else if let image = preview.image {
              GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                  Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: geometry.size.width * min(4, max(1, zoom * magnification)), height: geometry.size.height * min(4, max(1, zoom * magnification)))
                    .accessibilityIdentifier("library.preview.photo")
                }.gesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }.onEnded { zoom = min(4, max(1, zoom * $0)) })
              }
            }
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
          BurstPreviewControls(preview: preview)
          if preview.loading { ProgressView(value: preview.progress > 0 ? preview.progress : nil) }
          if preview.cloudNeeded {
            Button(policy.allowed ? "retry_task" : "preview_cloud_allow") {
              if !policy.allowed { policy.decide(true) }; preview.load()
            }.duckSecondaryAction()
          }
          if preview.failure { DuckNotice(title: "library_preview_unavailable", tone: .attention) }
        }.padding(20)
        if showingDetails {
          Divider()
          ScrollView { PhotoMetadataPanel(preview: preview).padding(20) }.frame(width: 290)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      HStack {
        Button("preview_previous") { move(-1) }.duckSecondaryAction().keyboardShortcut(.leftArrow, modifiers: [])
          .disabled(moving || library.previewIndex(of: preview.asset) == 0)
          .accessibilityIdentifier("library.preview.previous")
        Button("preview_next") { move(1) }.duckSecondaryAction().keyboardShortcut(.rightArrow, modifiers: [])
          .disabled(moving || (!library.hasMoreRows && library.previewIndex(of: preview.asset) == library.loaded - 1))
          .accessibilityIdentifier("library.preview.next")
        Spacer()
        if preview.kind == "photo" || preview.kind == "burst" {
          Button { zoom = zoom > 1 ? 1 : 2 } label: { Image(systemName: zoom > 1 ? "minus.magnifyingglass" : "plus.magnifyingglass") }.duckSecondaryAction()
        }
        Button("apple_photo_detail") { showingDetails.toggle() }.duckSecondaryAction()
          .accessibilityIdentifier("library.preview.info")
      }.padding(20)
    }.frame(minWidth: 640, idealWidth: 900, minHeight: 500, idealHeight: 650)
      .foregroundStyle(DuckColors.text).background(DuckColors.canvas)
      .onAppear { preview.load() }.onDisappear { preview.cancel() }
      .onChange(of: policy.choice) { _, _ in preview.load(); if showingDetails { preview.loadMetadata() } }
      .previewCloudConsent()
  }
  private func move(_ direction: Int) {
    guard !moving else { return }; moving = true
    Task {
      if let asset = await library.previewNeighbor(of: preview.asset, direction: direction) { zoom = 1; preview.load(asset) }
      moving = false
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

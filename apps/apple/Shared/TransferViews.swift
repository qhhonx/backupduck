import Photos
import SwiftUI

struct AssetThumbnail: View {
  let sourceID: String
  var size: CGFloat = 56
  var cornerRadius: CGFloat = 8
  #if os(macOS)
    @AppStorage("macListThumbnails") private var enabled = true
  #endif
  @State private var image: LibraryImage?
  @State private var request: PHImageRequestID = PHInvalidImageRequestID
  @State private var requestToken = UUID()
  private static let pipeline = ThumbnailPipeline()
  private var requestKey: String {
    #if os(macOS)
      return "\(sourceID)|\(enabled)|\(size)"
    #else
      return "\(sourceID)|\(size)"
    #endif
  }
  var body: some View {
    ZStack {
      Rectangle().fill(.quaternary)
      if let sample = BackupEnvironment.sampleThumbnail?(sourceID) {
        sample.resizable().scaledToFill()
      } else if let image {
        #if os(macOS)
          Image(nsImage: image).resizable().scaledToFill()
        #else
          Image(uiImage: image).resizable().scaledToFill()
        #endif
      } else {
        Image(systemName: "photo").foregroundStyle(.secondary)
          #if os(iOS)
            .font(.system(size: 22)).symbolVariant(.none)
          #endif
      }
    }.frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .task(id: requestKey) {
        Self.pipeline.cancel(request)
        image = nil
        requestToken = UUID()
        let token = requestToken
        #if os(macOS)
          guard enabled else { return }
        #endif
        guard BackupEnvironment.usesPhotoLibrary,
          let asset = PHAsset.fetchAssets(withLocalIdentifiers: [sourceID], options: photoLibraryFetchOptions())
            .firstObject
        else { return }
        request = Self.pipeline.request(asset, pixels: size * 2) { value, _ in
          guard requestToken == token else { return }
          if let value { image = value }
        }
      }.onDisappear {
        requestToken = UUID()
        Self.pipeline.cancel(request)
      }
  }
}

struct BackupTaskItem: Decodable, Identifiable, Equatable {
  let id: String
  let cursor: Int64
  let sort_value: Int64?
  let job: BackupJob?
  let preparation: SourceBrowserItem?
}


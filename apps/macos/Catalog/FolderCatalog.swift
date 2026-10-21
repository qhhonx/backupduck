import AppKit
import SwiftUI

/// Entirely synthetic inventory and rendered images. No bookmarks or real media access.
@MainActor enum FolderCatalog {
  static func install(_ id: String, folders: FolderSources, sheet: String?) {
    DesignPreview.proposedDesign = true
    folders.previewRows = []
    folders.initialSheet = sheet
    folders.previewSettings = id.hasPrefix("settings.folder")
    guard id != "folders.empty" else { return }
    let chinese = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true
    let names = chinese ? ["相机导出", "周末", "旅行照片"] : ["Camera Exports", "Weekend", "Travel Photos"]
    folders.sources = names.enumerated().map { index, name in
      FolderSource(id: "fixture-\(index)", name: name, bookmark: Data(), automatic: true, enabled: true,
        receiver: "catalog-pixel", lastCheck: nil, lastKnownPath: index == 2 ? "/Volumes/SanDisk/\(name)" : "/Synthetic/Pictures/\(name)")
    }
    folders.facts = [
      "fixture-0": FolderFacts(supported: 18, saved: 18, available: true, unsupported_by_kind: ["cr3": 8, "nef": 4]),
      "fixture-1": FolderFacts(supported: 24, saved: 6, in_flight: 18, in_flight_bytes: 284_000_000, available: true),
      "fixture-2": FolderFacts(supported: 48, saved: 40, not_backed_up: 8, available: false)
    ]
    var photos: [FolderPhoto] = []
    for folder in 0..<3 {
      for index in 0..<[18, 24, 48][folder] {
        let date = UInt64(Date().timeIntervalSince1970 * 1000) - UInt64(folder * 86400_000 + index * 3600_000)
        photos.append(FolderPhoto(relative: "\(index < 4 ? "Coast" : "Mountains")/IMG_\(1000 + folder * 100 + index).jpg", source_id: "fixture-photo-\(folder)-\(index)", revision: "fixture-v1", size: 8_000_000, media_type: "image/jpeg", modified_ms: date,
          folder_id: "fixture-\(folder)", capture_ms: date, date_source: "embedded",
          backup: folder == 0 || folder == 1 && index < 6 || folder == 2 && index < 40 ? "saved" : folder == 1 ? "sending" : "not_backed_up", saved_at_ms: folder == 0 || folder == 1 && index < 6 || folder == 2 && index < 40 ? date + 60_000 : nil))
      }
    }
    folders.previewRows = photos
    folders.previewImage = image
    if id == "folders.all-not-backed-up" { folders.initialFilter = .notBackedUp }
    if id == "settings.folder-detail" || sheet == "rules" || sheet == "stop" { folders.initialSettingsFolder = "fixture-0" }
  }
  private static func image(_ id: String) -> NSImage? {
    guard let picture = SampleImages.cgImage(for: id) else { return nil }
    return NSImage(cgImage: picture, size: NSSize(width: picture.width, height: picture.height))
  }
}

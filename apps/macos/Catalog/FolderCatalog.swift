import AppKit
import SwiftUI

/// Synthetic inventory with optional local sample photos. No bookmarks or library access.
@MainActor enum FolderCatalog {
  static func install(_ id: String, folders: FolderSources, sheet: String?) {
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
        let sourceID = "fixture-photo-\(folder)-\(index)"
        let fallback = Date().addingTimeInterval(-Double(folder * 86400 + index * 3600))
        let capture = id == "folders.viewer-received" && sourceID == "fixture-photo-0-4"
          ? Date(timeIntervalSince1970: 1_792_495_800) : SampleImages.takenDate(for: sourceID) ?? fallback
        let date = UInt64(max(0, capture.timeIntervalSince1970 * 1000))
        let saved = UInt64(max(0, fallback.timeIntervalSince1970 * 1000)) + 60_000
        photos.append(FolderPhoto(relative: "\(index < 4 ? "Coast" : "Mountains")/IMG_\(1000 + folder * 100 + index).jpg", source_id: sourceID, revision: "fixture-v1", size: 8_000_000, media_type: "image/jpeg", modified_ms: date,
          folder_id: "fixture-\(folder)", capture_ms: date, date_source: "embedded",
          backup: id == "folders.viewer-received" && sourceID == "fixture-photo-0-4" ? "saving" : folder == 0 || folder == 1 && index < 6 || folder == 2 && index < 40 ? "saved" : folder == 1 ? "sending" : "not_backed_up", saved_at_ms: id == "folders.viewer-received" && sourceID == "fixture-photo-0-4" ? nil : folder == 0 || folder == 1 && index < 6 || folder == 2 && index < 40 ? saved : nil))
      }
    }
    folders.previewRows = photos
    folders.previewImage = image
    if id.hasPrefix("folders.viewer") {
      folders.browser.search = "Mountains"
      folders.browser.searchExpanded = true
      folders.browser.selection = ["fixture-2|fixture-photo-2-40"]
    }
    if id == "folders.toolbar-search" { folders.browser.searchExpanded = true }
    if id == "folders.toolbar-selection" {
      folders.initialFilter = .notBackedUp
      folders.browser.filter = .notBackedUp
      folders.browser.byFolder = false
      folders.browser.selection = ["fixture-2|fixture-photo-2-40"]
    }
    if id == "folders.all-not-backed-up" { folders.initialFilter = .notBackedUp }
    if id == "settings.folder-detail" || sheet == "rules" || sheet == "stop" { folders.initialSettingsFolder = "fixture-0" }
  }
  private static func image(_ id: String) -> NSImage? {
    // The UI row key includes the folder; mapping uses the photo's source ID.
    let sourceID = String(id.split(separator: "|", maxSplits: 1).last ?? Substring(id))
    guard let picture = SampleImages.cgImage(for: sourceID) else { return nil }
    let size = NSSize(width: picture.width, height: picture.height)
    // The same provider serves native cells and the zoomable viewer. Draw at the
    // destination's pixel size so cells stay small and detail can resolve to 2048px.
    let image = NSImage(size: size, flipped: false) { rect in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      let pixels = rect.applying(context.ctm)
      let edge = Int(ceil(min(2048, max(abs(pixels.width), abs(pixels.height)))))
      guard let bitmap = SampleImages.cgImage(for: sourceID, maxPixelSize: edge) else { return false }
      context.draw(bitmap, in: rect)
      return true
    }
    image.cacheMode = .never
    return image
  }
}

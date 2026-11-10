import AppKit
import SwiftUI
import XCTest
#if canImport(BackupDuckCatalog)
@testable import BackupDuckCatalog
#else
@testable import BackupDuck
#endif

@MainActor final class MacGridLabelTests: XCTestCase {
  func testFloatingDateUsesNativeMaterialWithoutBlockingHeaderAdoption() {
    let caption = MacTimelineCaption(id: .init(kind: .date, value: "day"), firstItem: 0,
      title: "November 5, 2026", frame: CGRect(x: 0, y: 4, width: 804, height: 44))
    let header = MacGridSectionHeader(frame: caption.frame)
    header.configure(caption: caption, content: nil, revision: "current")
    header.floatingDate = true; header.layoutSubtreeIfNeeded()
    XCTAssertNil(header.layer?.backgroundColor, "A date must not cover moving photos with a full-width strip")
    XCTAssertTrue(header.isReady(for: caption, revision: "current"), "A ready material date must let the native grid adopt")
    XCTAssertFalse(header.isReady(for: caption, revision: "stale"))
    let date = header.subviews.compactMap { $0 as? TimelineDateHeader }.first!
    XCTAssertTrue(date.floating)
    XCTAssertTrue(date.subviews.contains { $0 is MacTimelineReadingSurface && !$0.isHidden })
  }

  func testOrdinaryReasonHeaderKeepsFlowContentWithoutDateMaterial() {
    let caption = MacTimelineCaption(id: .init(kind: .summary, value: "reason"), firstItem: 0,
      title: "Needs attention", frame: CGRect(x: 0, y: 4, width: 804, height: 44))
    let header = MacGridSectionHeader(frame: caption.frame)
    header.configure(caption: caption, content: AnyView(Text(caption.title)), revision: "current")
    let attributes = NSCollectionViewLayoutAttributes(forSupplementaryViewOfKind: MacTimelineCaption.Kind.summary.rawValue,
      with: IndexPath(item: 0, section: 0))
    attributes.frame = CGRect(x: 0, y: 100, width: 804, height: 44)
    header.apply(attributes); header.layoutSubtreeIfNeeded()
    XCTAssertFalse(header.floatingDate)
    XCTAssertTrue(header.subviews.compactMap { $0 as? TimelineDateHeader }.allSatisfy(\.isHidden))
    XCTAssertNotNil(header.summary)
    XCTAssertTrue(header.isReady(for: caption, revision: "current"))
  }

  func testChineseDateRangeUsesNumericMonthsAndOneSharedCalendar() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let locale = Locale(identifier: "zh_Hans_CN")
    let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23))!
    let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1))!
    XCTAssertEqual(MacGridDateRange.title(dates: [october], calendar: calendar, locale: locale), "2026年10月31日")
    XCTAssertEqual(MacGridDateRange.periodTitle(october, period: .month, calendar: calendar, locale: locale), "10月")
    XCTAssertEqual(MacGridDateRange.periodTitle(october, calendar: calendar, locale: locale), "2026年10月")
    XCTAssertEqual(MacGridDateRange.periodTitle(october, period: .year, calendar: calendar, locale: locale), "2026年")
    let interval = MacGridDateRange.title(dates: [november, october], calendar: calendar, locale: locale)
    XCTAssertTrue(interval.contains("10月31日")); XCTAssertTrue(interval.contains("11月1日"))
    XCTAssertFalse(interval.contains("十月")); XCTAssertFalse(interval.contains("十一月"))
    XCTAssertEqual(interval.components(separatedBy: "2026").count, 2, "The shared year appears once in a compact interval")
    var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = calendar.timeZone
    XCTAssertTrue(MacGridDateRange.title(dates: [october], calendar: buddhist, locale: locale).contains("2569"),
      "The application language must not replace the user's calendar")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    XCTAssertEqual(MacGridDateRange.title(dates: [october, november], calendar: calendar, locale: locale), "2026年10月31日")
  }

  func testFooterCountsUnknownTypesAsItemsInsteadOfInventingPhotos() {
    XCTAssertEqual(MacGridTotals.complete(kinds: ["photo", "motion", "video"]),
      MacGridTotals(total: 3, photos: 2, videos: 1))
    let unknown = MacGridTotals.complete(kinds: ["photo", nil, "video"])
    XCTAssertEqual(unknown.total, 3); XCTAssertNil(unknown.photos); XCTAssertNil(unknown.videos)
    XCTAssertNil(MacGridTotals(total: 50, photos: 40, videos: 0).photos,
      "An incomplete media split must not claim all remaining items are photos")
  }

  func testFilteredFolderFooterWaitsForCompleteMembershipAndIgnoresSelection() async {
    let folders = FolderSources(backup: BackupModel.shared)
    folders.previewRows = (0..<330).map { index in
      FolderPhoto(relative: "media-\(index)", source_id: "\(index)", revision: "1", size: 1,
        media_type: index % 3 == 0 ? "video/mp4" : "image/jpeg", modified_ms: 1,
        folder_id: "folder", capture_ms: UInt64(index + 1), date_source: "embedded",
        backup: "not_backed_up", saved_at_ms: nil)
    }
    let browser = FolderBrowser(); browser.scope = .folder("folder"); browser.type = .video
    await browser.reload(folders)
    XCTAssertNil(MacFolderGridSource(folders: folders, browser: browser).totals,
      "A loaded prefix cannot become a filtered total")
    await browser.more("folder", folders: folders)
    let totals = MacFolderGridSource(folders: folders, browser: browser).totals
    XCTAssertEqual(totals, MacGridTotals(total: 110, photos: 0, videos: 110))
    browser.selection = ["folder|0"]
    XCTAssertEqual(MacFolderGridSource(folders: folders, browser: browser).totals, totals)
  }

  func testFooterNotesWrapWithoutLosingTheirReservedCountLine() {
    let notes = ["To a receiver with a long device name", "Check cloud backup after reviewing the receiving device."]
    let waiting = MacGridFooter.attributed(total: "", notes: notes)
    let ready = MacGridFooter.attributed(total: "150 items", notes: notes)
    XCTAssertEqual(MacGridFooter.height(waiting, width: 220), MacGridFooter.height(ready, width: 220))
    XCTAssertGreaterThan(MacGridFooter.height(ready, width: 220), MacGridFooter.height(ready, width: 800))
    XCTAssertGreaterThan(MacGridFooter.height(ready, width: 220), MacGridFooter.minimumHeight)
  }

  func testVideoDurationKeepsItsReadingSizeAcrossPhotoDensitiesAndRelease() {
    let usesPhotoLibrary = BackupEnvironment.usesPhotoLibrary
    BackupEnvironment.usesPhotoLibrary = false
    defer { BackupEnvironment.usesPhotoLibrary = usesPhotoLibrary }
    let pipeline = ThumbnailPipeline()
    let tile = MacZoomMediaTile(frame: CGRect(x: 0, y: 0, width: 198, height: 198))
    tile.configure(CatalogLibraryAsset(1), side: 198, pixels: 396, pipeline: pipeline,
      originalAspect: false, selected: false, scale: 2)
    func textLayers(_ layer: CALayer) -> [MacTextBadgeLayer] {
      (layer as? MacTextBadgeLayer).map { [$0] } ?? (layer.sublayers ?? []).flatMap(textLayers)
    }
    guard let duration = textLayers(tile.layer!).first else { XCTFail("Missing duration label"); return }
    XCTAssertEqual(duration.text, "1:23")
    let readingSize: CGFloat = 18
    for side: CGFloat in [132, 198, 264, 132, 198] {
      tile.frame.size = CGSize(width: side, height: side)
      tile.needsLayout = true; tile.layoutSubtreeIfNeeded()
      var displayedSize = duration.bounds.height
      var layer: CALayer? = duration
      while let current = layer {
        displayedSize *= abs(current.affineTransform().d)
        layer = current.superlayer
      }
      XCTAssertEqual(displayedSize, readingSize, accuracy: 0.001,
        "Photo scaling must not change the duration's displayed type size")
      XCTAssertEqual(duration.frame.height, 18)
      XCTAssertEqual(duration.frame.maxX, side - 7, accuracy: 0.001)
    }
    let model = GridZoom.Settle(start: CACurrentMediaTime(), pitch: 134, focus: .zero,
      velocity: 200, targetPitch: 200, targetFocus: .zero)
    MacGridSpring.animate(tile, from: CGRect(x: 0, y: 0, width: 132, height: 132),
      derivative: CGRect(x: 0, y: 0, width: 1, height: 1), model: model, duration: model.duration)
    XCTAssertNil(duration.animation(forKey: "zoom.transform.scale.x"))
    XCTAssertNil(duration.animation(forKey: "zoom.transform.scale.y"))
    XCTAssertNil(duration.animation(forKey: "zoom.bounds.size.height"))
    XCTAssertNotNil(duration.animation(forKey: "zoom.position.x"))
    tile.cancel()
  }
}

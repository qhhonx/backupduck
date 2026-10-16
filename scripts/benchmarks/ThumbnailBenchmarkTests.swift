import Photos
import UIKit
import XCTest
import Darwin
#if NUKE_BENCHMARK
import Nuke
#endif
@testable import BackupDuck

/// Controlled loader timing isolates cache/scheduling cost from PhotoKit and iCloud.
@MainActor final class ThumbnailBenchmarkTests: XCTestCase {
  func testCompareBaselineAndCandidate() async throws {
    let status = await PHPhotoLibrary.requestAuthorization(for:.readWrite)
    guard status == .authorized || status == .limited else { throw XCTSkip("Photo permission is required on a disposable fixture simulator") }
    let fetch = PHAsset.fetchAssets(with:.image,options:photoLibraryFetchOptions())
    guard fetch.count >= 120 else { throw XCTSkip("Import at least 120 synthetic images into the simulator") }
    let assets = (0..<min(480,fetch.count)).map { fetch.object(at:$0) }
    var rows: [[String:Any]] = []
    for round in 0..<3 {
      var strategies = ["baseline","candidate"]
      #if NUKE_BENCHMARK
      strategies += ["nuke_default","nuke_tuned"]
      #endif
      // Rotate order to avoid systematically giving one strategy the warm host.
      let pivot = round % strategies.count
      strategies = Array(strategies.dropFirst(pivot)) + Array(strategies.prefix(pivot))
      for strategy in strategies {
        let baseline = strategy == "baseline"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let manager = BenchmarkImageManager()
        let old = BenchmarkBaselinePipeline(manager:manager)
        let new = ThumbnailPipeline(manager:manager)
        old.disk = nil; new.disk = nil
        #if NUKE_BENCHMARK
        let nuke = NukeBenchmarkAdapter(manager:manager,tuned:strategy == "nuke_tuned")
        #endif
        func request(_ asset:PHAsset,_ side:CGFloat,prefetch:Bool = false,_ completion:@escaping (UIImage?,Bool)->Void)->PHImageRequestID {
          #if NUKE_BENCHMARK
          if strategy.hasPrefix("nuke_") { return nuke.request(asset,side:side,prefetch:prefetch,completion:completion) }
          #endif
          return baseline ? old.request(asset,pixels:side,completion:completion) : new.request(asset,pixels:side,priority:prefetch ? .prefetch : .visible,completion:completion)
        }
        func clearMemory() {
          #if NUKE_BENCHMARK
          if strategy.hasPrefix("nuke_") { nuke.clearMemory(); return }
          #endif
          if baseline { old.clear() } else { new.clear() }
        }
        func cancel(_ id:PHImageRequestID) {
          #if NUKE_BENCHMARK
          if strategy.hasPrefix("nuke_") { nuke.cancel(id); return }
          #endif
          if baseline { old.cancel(id) } else { new.cancel(id) }
        }
        func scenario(_ name:String,side:CGFloat,repeats:Int=1,cancelHalf:Bool=false) async {
          let pulse = BenchmarkMainActorPulse(); pulse.start()
          let started = CACurrentMediaTime(), before = manager.started
          var first: [Double] = [], complete: [Double] = [], seenFirst = Set<Int>(),seenComplete = Set<Int>()
          let count = assets.count*repeats
          let done = expectation(description:name); done.expectedFulfillmentCount = cancelHalf ? count/2 : count
          for token in 0..<count {
            let time = CACurrentMediaTime()
            let id = request(assets[token % assets.count],side) { image,_ in
              guard let image else { return }
              if seenFirst.insert(token).inserted { first.append((CACurrentMediaTime()-time)*1000) }
              if image.size.width*image.scale >= side-1,seenComplete.insert(token).inserted {
                complete.append((CACurrentMediaTime()-time)*1000); done.fulfill()
              }
            }
            if cancelHalf && token % 2 == 0 { cancel(id) }
          }
          await fulfillment(of:[done],timeout:30)
          pulse.stop()
          XCTAssertEqual(complete.count, cancelHalf ? count / 2 : count, "No request may disappear from a latency result")
          if name.hasSuffix("repeat") { XCTAssertEqual(manager.started-before, 0, "A seeded cache revisit must not refetch") }
          func percentile(_ values:[Double],_ p:Double)->Double {
            let v = values.sorted(); return v.isEmpty ? -1 : v[min(v.count-1,Int(Double(v.count-1)*p))]
          }
          rows.append(["strategy":strategy,"round":round,"scenario":name,
            "requests":count,"loader_starts":manager.started-before,"completed":complete.count,
            "elapsed_ms":(CACurrentMediaTime()-started)*1000,"first_p50_ms":percentile(first,0.5),
            "first_p95_ms":percentile(first,0.95),"final_p50_ms":percentile(complete,0.5),"final_p95_ms":percentile(complete,0.95),
            "main_gap_p95_ms":pulse.percentile(0.95),"main_gap_max_ms":pulse.gaps.max() ?? 0,
            "resident_bytes":residentBytes()])
        }
        func visibleDuringPrefetch() async {
          clearMemory()
          let background = expectation(description: "Speculative requests drain")
          background.expectedFulfillmentCount = assets.count - 24
          var backgroundSeen = Set<Int>()
          for i in 0..<(assets.count - 24) {
            _ = request(assets[i], 320, prefetch: true) { image,_ in
              if let image, image.size.width * image.scale >= 320,
                backgroundSeen.insert(i).inserted { background.fulfill() }
            }
          }
          try? await Task.sleep(for: .milliseconds(5))
          let visible = expectation(description: "Viewport overtakes speculative requests")
          visible.expectedFulfillmentCount = 24
          let started = CACurrentMediaTime(), before = manager.started
          let pulse = BenchmarkMainActorPulse(); pulse.start()
          var times: [Double] = [], seen = Set<Int>()
          for i in (assets.count - 24)..<assets.count {
            _ = request(assets[i], 320) { image,_ in
              if let image, image.size.width * image.scale >= 320, seen.insert(i).inserted {
                times.append((CACurrentMediaTime()-started)*1000); visible.fulfill()
              }
            }
          }
          await fulfillment(of: [visible], timeout: 30)
          pulse.stop()
          let elapsed = (CACurrentMediaTime()-started)*1000, sorted = times.sorted()
          XCTAssertEqual(times.count, 24)
          rows.append(["strategy":strategy,"round":round,"scenario":"visible_during_prefetch",
            "requests":24,"loader_starts":manager.started-before,"completed":times.count,
            "elapsed_ms":elapsed,"first_p50_ms":sorted.isEmpty ? -1 : sorted[sorted.count/2],
            "first_p95_ms":sorted.isEmpty ? -1 : sorted[Int(Double(sorted.count-1)*0.95)],
            "final_p50_ms":sorted.isEmpty ? -1 : sorted[sorted.count/2],
            "final_p95_ms":sorted.isEmpty ? -1 : sorted[Int(Double(sorted.count-1)*0.95)],
            "main_gap_p95_ms":pulse.percentile(0.95),"main_gap_max_ms":pulse.gaps.max() ?? 0,
            "resident_bytes":residentBytes()])
          await fulfillment(of: [background], timeout: 30)
        }
        await scenario("cold_dense",side:64)
        await scenario("memory_repeat",side:64)
        clearMemory(); await scenario("duplicate_dense",side:64,repeats:5)
        clearMemory(); await scenario("cancel_scroll",side:128,cancelHalf:true)
        await visibleDuringPrefetch()
        clearMemory(); await scenario("cover_upgrade",side:320)
        clearMemory(); await scenario("prefetch_dense",side:64)
        await scenario("prefetch_revisit",side:64)
        #if NUKE_BENCHMARK
        if strategy.hasPrefix("nuke_") { try nuke.enableDisk(directory:directory) }
        else if baseline { old.disk = BenchmarkBaselineDiskCache(directory:directory) }
        else { new.disk = ThumbnailDiskCache(directory:directory) }
        #else
        if baseline { old.disk = BenchmarkBaselineDiskCache(directory:directory) }
        else { new.disk = ThumbnailDiskCache(directory:directory) }
        #endif
        clearMemory(); await scenario("disk_seed",side:64)
        // Let utility writes settle, then reopen the disk object to exclude staged RAM data.
        try? await Task.sleep(for:.seconds(2))
        #if NUKE_BENCHMARK
        if strategy.hasPrefix("nuke_") { try nuke.reopenDisk() }
        else if baseline { old.disk = BenchmarkBaselineDiskCache(directory:directory) }
        else { new.disk = ThumbnailDiskCache(directory:directory) }
        #else
        if baseline { old.disk = BenchmarkBaselineDiskCache(directory:directory) }
        else { new.disk = ThumbnailDiskCache(directory:directory) }
        #endif
        clearMemory(); await scenario("disk_repeat",side:64)
        clearMemory(); await scenario("disk_cover_seed",side:320)
        try? await Task.sleep(for:.seconds(2))
        #if NUKE_BENCHMARK
        if strategy.hasPrefix("nuke_") { try nuke.reopenDisk() }
        else if baseline { old.disk = BenchmarkBaselineDiskCache(directory:directory) }
        else { new.disk = ThumbnailDiskCache(directory:directory) }
        #else
        if baseline { old.disk = BenchmarkBaselineDiskCache(directory:directory) }
        else { new.disk = ThumbnailDiskCache(directory:directory) }
        #endif
        clearMemory(); await scenario("disk_cover_repeat",side:320)
        clearMemory()
        if baseline { old.disk = nil } else { new.disk = nil }
      }
    }
    let data = try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys])
    let attachment = XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
    attachment.name = "thumbnail-benchmark"; attachment.lifetime = .keepAlways; add(attachment)
    print("THUMBNAIL_BENCHMARK "+String(data:data,encoding:.utf8)!)
  }
  private func residentBytes()->UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to:&info) { p in
      p.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count) }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
  }
}

@MainActor final class BenchmarkImageManager: PHCachingImageManager, @unchecked Sendable {
  var started = 0
  var work: [PHImageRequestID:DispatchWorkItem] = [:]
  var images: [Int:UIImage] = [:]
  override func requestImage(for asset:PHAsset,targetSize:CGSize,contentMode:PHImageContentMode,
    options:PHImageRequestOptions?,resultHandler:@escaping (UIImage?,[AnyHashable:Any]?)->Void)->PHImageRequestID {
    started += 1; let id = PHImageRequestID(started),side = Int(targetSize.width)
    if images[side] == nil {
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      images[side] = UIGraphicsImageRenderer(size:targetSize,format:format).image { ctx in
        for y in stride(from:0,to:side,by:4) {
          for x in stride(from:0,to:side,by:4) {
            let n = (x*13+y*29)%251
            UIColor(red:CGFloat(n)/251,green:CGFloat((n*7)%251)/251,blue:CGFloat((n*3)%251)/251,alpha:1).setFill()
            ctx.fill(CGRect(x:x,y:y,width:4,height:4))
          }
        }
      }
    }
    let image = images[side]
    let job = DispatchWorkItem { [weak self] in
      self?.work.removeValue(forKey:id)
      resultHandler(image,[PHImageResultIsDegradedKey:options?.deliveryMode == .fastFormat])
    }
    work[id] = job; DispatchQueue.main.asyncAfter(deadline:.now()+0.004,execute:job)
    return id
  }
  override func cancelImageRequest(_ requestID:PHImageRequestID) { work.removeValue(forKey:requestID)?.cancel() }
  override func startCachingImages(for assets:[PHAsset],targetSize:CGSize,contentMode:PHImageContentMode,options:PHImageRequestOptions?) {}
  override func stopCachingImagesForAllAssets() {}
}

/// Main-queue scheduling delay is a CPU-contention proxy, not measured render FPS.
@MainActor private final class BenchmarkMainActorPulse {
  private var timer: DispatchSourceTimer?
  private var last: CFTimeInterval = 0
  var gaps: [Double] = []
  func start() {
    last = CACurrentMediaTime()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + .milliseconds(2), repeating: .milliseconds(2))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      let now = CACurrentMediaTime()
      gaps.append(max(0, (now-last)*1000-2)); last = now
    }
    self.timer = timer; timer.resume()
  }
  func stop() { timer?.cancel(); timer = nil }
  func percentile(_ p: Double) -> Double {
    let values = gaps.sorted()
    return values.isEmpty ? 0 : values[Int(Double(values.count-1)*p)]
  }
}

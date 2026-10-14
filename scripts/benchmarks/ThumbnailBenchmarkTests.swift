import Photos
import UIKit
import XCTest
import Darwin
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
      for baseline in round % 2 == 0 ? [true,false] : [false,true] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let manager = BenchmarkImageManager()
        let old = BenchmarkBaselinePipeline(manager:manager)
        let new = ThumbnailPipeline(manager:manager)
        old.disk = nil; new.disk = nil
        func request(_ asset:PHAsset,_ side:CGFloat,_ completion:@escaping (UIImage?,Bool)->Void)->PHImageRequestID {
          baseline ? old.request(asset,pixels:side,completion:completion) : new.request(asset,pixels:side,completion:completion)
        }
        func clearMemory() { if baseline { old.clear() } else { new.clear() } }
        func cancel(_ id:PHImageRequestID) { if baseline { old.cancel(id) } else { new.cancel(id) } }
        func scenario(_ name:String,side:CGFloat,repeats:Int=1,cancelHalf:Bool=false) async {
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
          func percentile(_ values:[Double],_ p:Double)->Double {
            let v = values.sorted(); return v.isEmpty ? -1 : v[min(v.count-1,Int(Double(v.count-1)*p))]
          }
          rows.append(["strategy":baseline ? "baseline62" : "candidate","round":round,"scenario":name,
            "requests":count,"loader_starts":manager.started-before,"completed":complete.count,
            "elapsed_ms":(CACurrentMediaTime()-started)*1000,"first_p50_ms":percentile(first,0.5),
            "first_p95_ms":percentile(first,0.95),"final_p50_ms":percentile(complete,0.5),"final_p95_ms":percentile(complete,0.95),
            "resident_bytes":residentBytes()])
        }
        await scenario("cold_dense",side:64)
        await scenario("memory_repeat",side:64)
        clearMemory(); await scenario("duplicate_dense",side:64,repeats:5)
        clearMemory(); await scenario("cancel_scroll",side:128,cancelHalf:true)
        clearMemory(); await scenario("cover_upgrade",side:320)
        if baseline { old.disk = BenchmarkBaselineDiskCache(directory:directory) }
        else { new.disk = ThumbnailDiskCache(directory:directory) }
        clearMemory(); await scenario("disk_seed",side:64)
        // Let utility writes settle before reopening the memory layer.
        try? await Task.sleep(for:.seconds(2))
        clearMemory(); await scenario("disk_repeat",side:64)
        clearMemory(); await scenario("disk_cover_seed",side:320)
        try? await Task.sleep(for:.seconds(2))
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

@MainActor private final class BenchmarkImageManager: PHCachingImageManager, @unchecked Sendable {
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

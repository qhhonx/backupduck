import AVFoundation
import UIKit

@main final class GridPreviewApp: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication, configurationForConnecting session: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let config = UISceneConfiguration(name: nil, sessionRole: session.role)
    config.delegateClass = GridPreviewScene.self
    return config
  }
}
final class GridPreviewScene: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  let images = NSCache<NSString, UIImage>()
  var previewMovie: URL?
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions
  ) {
    guard let scene = scene as? UIWindowScene else { return }
    images.totalCostLimit = 24 * 1024 * 1024
    let grid = CalendarGridController()
    if ProcessInfo.processInfo.arguments.contains("--movie-cover") {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("grid-preview.mov")
      DispatchQueue.global(qos: .utility).async { [weak self] in
        GridPreviewMovie.make(url) { Task { @MainActor in self?.previewMovie = url } }
      }
    }
    grid.requestVideo = { [weak self] _, done in
      done(self?.previewMovie.map { AVPlayerItem(url: $0) })
      return {}
    }
    let count = ProcessInfo.processInfo.arguments.contains("--long-library") ? 55000 : 1440
    grid.assets = (0..<count).map { i in
      let date =
        count > 1440
        ? Date(timeIntervalSince1970: 1_577_836_800 + Double(i) * 2700)
        : Calendar.current.date(
          from: DateComponents(
            year: 2023 + i / 360, month: 1 + (i % 360) / 30, day: 1 + (i % 30) / 5, hour: 10 + i % 8
          ))
      return CalendarGridAsset(
        id: "example-\(i)", date: date, aspect: i % 4 == 0 ? 0.75 : 1.5,
        videoDuration: i % 11 == 0
          || (ProcessInfo.processInfo.arguments.contains("--movie-cover") && i % 360 == 359)
          ? "0:32" : nil, live: i % 7 == 0)
    }
    let allAssets = grid.assets
    var filter = 0
    grid.menu = { [weak grid] in
      let names = ["All", "Photos", "Live Photos", "Videos", "Bursts"]
      let actions = names.enumerated().map { value, title in
        UIAction(title: title, state: filter == value ? .on : .off) { _ in
          filter = value
          let rows = allAssets.filter { asset in
            let i = Int(asset.id.split(separator: "-").last ?? "0") ?? 0
            switch value {
            case 1: return asset.videoDuration == nil && !asset.live && i % 19 != 0
            case 2: return asset.live
            case 3: return asset.videoDuration != nil
            case 4: return asset.videoDuration == nil && !asset.live && i % 19 == 0
            default: return true
            }
          }
          grid?.replaceAssets(rows)
          grid?.refreshMenu()
        }
      }
      return [UIMenu(title: "Media type", options: .displayInline, children: actions)]
    }
    grid.requestImage = { [weak self] asset, pixels, done in
      guard let self else { return {} }
      let index = Int(asset.id.split(separator: "-").last ?? "0") ?? 0
      let side = min(1000, max(64, Int(pixels)))
      let key = "\(index)|\(side/100)" as NSString
      if let cached = self.images.object(forKey: key) {
        done(cached, false)
        return {}
      }
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: side, height: Int(CGFloat(side) / asset.aspect)),format:format)
      let image = renderer.image { context in
        let c = context.cgContext
        let b = CGRect(x: 0, y: 0, width: side, height: Int(CGFloat(side) / asset.aspect))
        let hue = CGFloat(index % 12) / 12
        c.setFillColor(UIColor(hue: hue, saturation: 0.23, brightness: 0.95, alpha: 1).cgColor)
        c.fill(b)
        c.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        c.fillEllipse(
          in: CGRect(
            x: b.width * 0.7, y: b.height * 0.14, width: b.width * 0.12, height: b.width * 0.12))
        for layer in 0..<3 {
          c.setFillColor(
            UIColor(hue: hue, saturation: 0.36, brightness: 0.35 + CGFloat(layer) * 0.15, alpha: 1)
              .cgColor)
          c.beginPath()
          c.move(to: CGPoint(x: 0, y: b.height))
          c.addLine(to: CGPoint(x: 0, y: b.height * (0.48 + CGFloat(layer) * 0.1)))
          c.addCurve(
            to: CGPoint(x: b.width, y: b.height * 0.63),
            control1: CGPoint(x: b.width * 0.35, y: b.height * 0.2),
            control2: CGPoint(x: b.width * 0.7, y: b.height * 0.8))
          c.addLine(to: CGPoint(x: b.width, y: b.height))
          c.closePath()
          c.fillPath()
        }
      }
      let numbered = UIGraphicsImageRenderer(size:image.size,format:format).image { _ in
        image.draw(at:.zero)
        let text = "\(index)"
        let attributes: [NSAttributedString.Key:Any] = [
          .font:UIFont.monospacedDigitSystemFont(ofSize:max(12,CGFloat(side)*0.18),weight:.bold),
          .foregroundColor:UIColor.white]
        let textSize = text.size(withAttributes:attributes)
        text.draw(at:CGPoint(x:(image.size.width-textSize.width)/2,y:image.size.height*0.7),withAttributes:attributes)
      }
      self.images.setObject(numbered, forKey: key, cost: numbered.cgImage.map { $0.bytesPerRow*$0.height } ?? side*side*4)
      done(numbered, false)
      return {}
    }
    grid.onPreview = { _, _ in }
    let tabs = UITabBarController()
    grid.tabBarItem = UITabBarItem(
      title: "Library", image: UIImage(systemName: "photo.on.rectangle"), tag: 0)
    let nav = CalendarNavigationController(rootViewController: grid)
    let others = [
      ("Backup", "arrow.triangle.2.circlepath"), ("Receiver", "externaldrive.badge.wifi"),
      ("Settings", "gearshape"),
    ].map { title, symbol -> UIViewController in
      let c = UIViewController()
      c.view.backgroundColor = .systemBackground
      c.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: 1)
      return c
    }
    tabs.viewControllers = [nav] + others
    let window = UIWindow(windowScene: scene)
    window.rootViewController = tabs
    window.makeKeyAndVisible()
    self.window = window
  }
}

/// A small generated movie for the standalone study, not user media.
private enum GridPreviewMovie {
  static func make(_ url: URL, completion: @escaping () -> Void) {
    try? FileManager.default.removeItem(at: url)
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 128, AVVideoHeightKey: 128,
      ])
    let adapter = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 128,
      ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<60 {
      while !input.isReadyForMoreMediaData && writer.status == .writing {
        Thread.sleep(forTimeInterval: 0.01)
      }
      var value: CVPixelBuffer?
      CVPixelBufferCreate(nil, 128, 128, kCVPixelFormatType_32ARGB, nil, &value)
      guard let value else { continue }
      CVPixelBufferLockBaseAddress(value, [])
      if let base = CVPixelBufferGetBaseAddress(value),
        let context = CGContext(
          data: base, width: 128, height: 128,
          bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(value),
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
      {
        context.setFillColor(UIColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: CGFloat(frame) * 1.4, y: 38, width: 40, height: 40))
      }
      CVPixelBufferUnlockBaseAddress(value, [])
      _ = adapter.append(value, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
    }
    input.markAsFinished()
    writer.finishWriting { if writer.status == .completed { completion() } }
  }
}

#!/usr/bin/env swift
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Sample local recordings with source timestamps. Generated evidence belongs in
// ignored storage; this tool does not modify or upload the input recording.
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
  fputs("Usage: xcrun swift scripts/sample-motion.swift VIDEO OUTPUT [START END FPS]\n", stderr)
  exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: arguments[0]))
let duration = CMTimeGetSeconds(try await asset.load(.duration))
let track = try await asset.loadTracks(withMediaType: .video).first
let nominalRate = Double(try await track?.load(.nominalFrameRate) ?? 30)
let minimumDuration = try await track?.load(.minFrameDuration) ?? .invalid
let minimumSeconds = CMTimeGetSeconds(minimumDuration)
// Variable-frame-rate recordings may report a low average nominal rate while
// their actual interaction frames are much denser. Do not cap them at that average.
let fastestRate = minimumSeconds.isFinite && minimumSeconds > 0 ? 1/minimumSeconds : nominalRate
let sourceRate = max(1,max(nominalRate,fastestRate))
let start = arguments.count > 2 ? Double(arguments[2]) ?? 0 : 0
let end = arguments.count > 3 ? Double(arguments[3]) ?? duration : duration
let requestedRate = arguments.count > 4 ? Double(arguments[4]) ?? sourceRate : sourceRate
let rate = min(max(1, sourceRate), requestedRate)
guard start.isFinite, end.isFinite, rate.isFinite, rate > 0,
  start >= 0, end > start, start < duration else {
  fputs("Invalid time range or sample rate.\n", stderr); exit(2)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
var csv = "requested_seconds,actual_seconds,file\n"
var previousTime: Double?
var count = 0
for sample in 0..<Int(ceil((min(end,duration)-start)*rate)) {
  let requested = start + Double(sample)/rate
  let (image, actual) = try await generator.image(at: CMTime(seconds: requested,preferredTimescale: 60000))
  let seconds = CMTimeGetSeconds(actual)
  if let previousTime, abs(previousTime-seconds) < 0.000001 { continue }
  previousTime = seconds
  let name = String(format: "frame-%09.4f.jpg",requested)
  let destinationURL = output.appendingPathComponent(name)
  guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL,
    UTType.jpeg.identifier as CFString,1,nil) else {
    throw CocoaError(.fileWriteUnknown)
  }
  CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.94] as CFDictionary)
  guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
  csv += String(format:"%.6f,%.6f,%@\n",requested,seconds,name)
  count += 1
}
try csv.write(to:output.appendingPathComponent("frames.csv"),atomically:true,encoding:.utf8)
print("Saved \(count) frames at up to \(rate) samples/second with actual source timestamps.")

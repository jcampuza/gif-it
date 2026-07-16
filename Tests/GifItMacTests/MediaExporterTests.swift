@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import GifItCore
import GifItMac
import ImageIO
import Testing

@Test func mediaExporterProducesAnimatedGIF() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("fixture.mp4")
  let destination = root.appendingPathComponent("fixture.gif")
  try await makeFixtureVideo(at: source)

  let exporter = MediaExporter()
  _ = try await exporter.makeGIF(from: source, to: destination) { _ in }

  let imageSource = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
  #expect(CGImageSourceGetCount(imageSource) >= 2)
  let properties = CGImageSourceCopyProperties(imageSource, nil) as? [CFString: Any]
  let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
  #expect(gif?[kCGImagePropertyGIFLoopCount] as? Int == 0)
}

@Test func mediaExporterAppliesGIFQualityFrameRate() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("fixture.mp4")
  let lowDestination = root.appendingPathComponent("low.gif")
  let highDestination = root.appendingPathComponent("high.gif")
  try await makeFixtureVideo(at: source)

  let exporter = MediaExporter()
  _ = try await exporter.makeGIF(from: source, to: lowDestination, quality: .low) { _ in }
  _ = try await exporter.makeGIF(from: source, to: highDestination, quality: .high) { _ in }

  let lowSource = try #require(CGImageSourceCreateWithURL(lowDestination as CFURL, nil))
  let highSource = try #require(CGImageSourceCreateWithURL(highDestination as CFURL, nil))
  #expect(CGImageSourceGetCount(lowSource) < CGImageSourceGetCount(highSource))
}

private func makeFixtureVideo(at url: URL) async throws {
  let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
  let input = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 160,
      AVVideoHeightKey: 90,
    ]
  )
  input.expectsMediaDataInRealTime = false
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: 160,
      kCVPixelBufferHeightKey as String: 90,
    ]
  )
  writer.add(input)
  #expect(writer.startWriting())
  writer.startSession(atSourceTime: .zero)

  for index in 0..<6 {
    while !input.isReadyForMoreMediaData {
      try await Task.sleep(for: .milliseconds(10))
    }
    let pixelBuffer = try makePixelBuffer(value: UInt8(index * 35))
    #expect(
      adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: 15)))
  }
  input.markAsFinished()
  await writer.finishWriting()
  #expect(writer.status == .completed)
}

private func makePixelBuffer(value: UInt8) throws -> CVPixelBuffer {
  var optionalBuffer: CVPixelBuffer?
  let status = CVPixelBufferCreate(
    kCFAllocatorDefault,
    160,
    90,
    kCVPixelFormatType_32BGRA,
    [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
    &optionalBuffer
  )
  guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
    throw CocoaError(.fileWriteUnknown)
  }
  CVPixelBufferLockBaseAddress(buffer, [])
  if let base = CVPixelBufferGetBaseAddress(buffer) {
    memset(base, Int32(value), CVPixelBufferGetDataSize(buffer))
  }
  CVPixelBufferUnlockBaseAddress(buffer, [])
  return buffer
}

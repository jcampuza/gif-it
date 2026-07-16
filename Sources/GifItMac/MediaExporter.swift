@preconcurrency import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import GifItCore
import ImageIO
import UniformTypeIdentifiers

public enum MediaExporterError: LocalizedError {
  case missingVideoTrack
  case cannotCreateReader
  case cannotCreateDestination
  case noFrames
  case readerFailed(Error?)
  case finalizationFailed

  public var errorDescription: String? {
    switch self {
    case .missingVideoTrack: "The recording does not contain a video track."
    case .cannotCreateReader: "Gif It could not read the recording."
    case .cannotCreateDestination: "Gif It could not create the GIF file."
    case .noFrames: "Recording too short."
    case .readerFailed(let error): error?.localizedDescription ?? "Reading the recording failed."
    case .finalizationFailed: "Gif It could not finish writing the GIF."
    }
  }
}

public actor MediaExporter {
  private let context = CIContext(options: [.cacheIntermediates: false])

  public init() {}

  public func makeGIF(
    from source: URL,
    to destinationURL: URL,
    quality: GIFQuality = .standard,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    let asset = AVURLAsset(url: source)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let track = tracks.first else { throw MediaExporterError.missingVideoTrack }
    let duration = try await asset.load(.duration)
    let framesPerSecond = quality.framesPerSecond
    let durationSeconds = max(duration.seconds, 1.0 / framesPerSecond)
    let frameCount = max(1, Int(ceil(durationSeconds * framesPerSecond)))

    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      throw MediaExporterError.cannotCreateReader
    }
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw MediaExporterError.cannotCreateReader }
    reader.add(output)

    guard
      let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL,
        UTType.gif.identifier as CFString,
        frameCount,
        nil
      )
    else {
      throw MediaExporterError.cannotCreateDestination
    }
    CGImageDestinationSetProperties(
      destination,
      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
    )

    guard reader.startReading() else {
      throw MediaExporterError.readerFailed(reader.error)
    }

    let frameDelay = 1.0 / framesPerSecond
    let frameProperties =
      [
        kCGImagePropertyGIFDictionary: [
          kCGImagePropertyGIFDelayTime: frameDelay,
          kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
        ]
      ] as CFDictionary
    var emitted = 0
    var nextTargetTime = 0.0
    var firstPresentationTime: Double?
    var lastImage: CGImage?

    while emitted < frameCount, let sample = output.copyNextSampleBuffer() {
      try Task.checkCancellation()
      let presentation = CMSampleBufferGetPresentationTimeStamp(sample).seconds
      if firstPresentationTime == nil { firstPresentationTime = presentation }
      let relativeTime = presentation - (firstPresentationTime ?? presentation)
      guard relativeTime + 0.001 >= nextTargetTime else { continue }
      guard
        let pixelBuffer = CMSampleBufferGetImageBuffer(sample),
        let image = makeImage(
          from: pixelBuffer,
          maximumPixelDimension: quality.maximumPixelDimension
        )
      else { continue }

      CGImageDestinationAddImage(destination, image, frameProperties)
      lastImage = image
      emitted += 1
      nextTargetTime = Double(emitted) * frameDelay
      progress(Double(emitted) / Double(frameCount))
    }

    guard let lastImage else {
      throw MediaExporterError.noFrames
    }
    while emitted < frameCount {
      CGImageDestinationAddImage(destination, lastImage, frameProperties)
      emitted += 1
      progress(Double(emitted) / Double(frameCount))
    }

    guard reader.status == .completed || reader.status == .reading else {
      throw MediaExporterError.readerFailed(reader.error)
    }
    guard CGImageDestinationFinalize(destination) else {
      throw MediaExporterError.finalizationFailed
    }
    return destinationURL
  }

  private func makeImage(
    from pixelBuffer: CVPixelBuffer,
    maximumPixelDimension: Double
  ) -> CGImage? {
    let source = CIImage(cvPixelBuffer: pixelBuffer)
    let longestEdge = max(source.extent.width, source.extent.height)
    let scale = min(1, maximumPixelDimension / longestEdge)
    let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return context.createCGImage(scaled, from: scaled.extent.integral)
  }
}

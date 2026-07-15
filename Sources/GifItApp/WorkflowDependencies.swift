import Foundation
import GifItCore
import GifItMac
@preconcurrency import ScreenCaptureKit

@MainActor
protocol RecordingControlling: AnyObject {
  var onUnexpectedFinish: ((Result<URL, Error>) -> Void)? { get set }

  func start(
    filter: SCContentFilter,
    outputURL: URL,
    options: RecordingOptions,
    configureStream: (SCStream) -> Void
  ) async throws

  func stop() async throws -> URL
  func cancel() async
}

extension ScreenCaptureRecorder: RecordingControlling {}

protocol ArtifactStoring: Actor {
  func makeWorkingURL() throws -> URL
  func makeFinalURL(for format: CaptureFormat, date: Date) throws -> URL
  func promoteMP4(_ source: URL, date: Date) throws -> URL
  func remove(_ url: URL)
  func prune(now: Date, maximumAge: TimeInterval, limit: Int) throws
}

extension ArtifactStoring {
  func makeFinalURL(for format: CaptureFormat) throws -> URL {
    try makeFinalURL(for: format, date: Date())
  }

  func promoteMP4(_ source: URL) throws -> URL {
    try promoteMP4(source, date: Date())
  }

  func prune() throws {
    try prune(now: Date(), maximumAge: 86_400, limit: 10)
  }
}

extension ArtifactStore: ArtifactStoring {}

protocol MediaExporting: Actor {
  func makeGIF(
    from source: URL,
    to destinationURL: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL
}

extension MediaExporter: MediaExporting {}

@MainActor
protocol ArtifactDelivering: AnyObject {
  func deliver(
    artifact: URL,
    format: CaptureFormat,
    settings: CaptureSettings
  ) throws -> URL
}

extension ArtifactDelivery: ArtifactDelivering {}

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

public struct RecordingOptions: Sendable {
  public var includesCursor: Bool
  public var showsMouseClicks: Bool

  public init(includesCursor: Bool, showsMouseClicks: Bool) {
    self.includesCursor = includesCursor
    self.showsMouseClicks = showsMouseClicks
  }
}

public enum ScreenCaptureRecorderError: Error, LocalizedError {
  case recordingAlreadyActive
  case noActiveRecording
  case startInterrupted(outputURL: URL)
  case stopCaptureFailed(outputURL: URL, underlying: any Error)
  case recordingOutputFailed(outputURL: URL, underlying: any Error)
  case finalizationTimedOut(outputURL: URL)
  case streamStoppedUnexpectedly(outputURL: URL, underlying: any Error)

  public var outputURL: URL? {
    switch self {
    case .recordingAlreadyActive, .noActiveRecording:
      nil
    case .startInterrupted(let outputURL),
      .stopCaptureFailed(let outputURL, _),
      .recordingOutputFailed(let outputURL, _),
      .finalizationTimedOut(let outputURL),
      .streamStoppedUnexpectedly(let outputURL, _):
      outputURL
    }
  }

  public var errorDescription: String? {
    switch self {
    case .recordingAlreadyActive:
      "A screen recording is already active."
    case .noActiveRecording:
      "There is no active screen recording."
    case .startInterrupted:
      "The screen recording ended while it was starting."
    case .stopCaptureFailed(_, let error):
      "The screen recording could not be stopped: \(error.localizedDescription)"
    case .recordingOutputFailed(_, let error):
      "The recording output failed: \(error.localizedDescription)"
    case .finalizationTimedOut:
      "The recording did not finish writing in time."
    case .streamStoppedUnexpectedly(_, let error):
      "The screen recording stopped unexpectedly: \(error.localizedDescription)"
    }
  }
}

struct RecorderLifecycle: Equatable {
  enum Phase: Equatable {
    case idle
    case starting(UInt64)
    case recording(UInt64)
    case stopping(UInt64)
    case tearingDown(UInt64)
  }

  enum StopDisposition: Equatable {
    case begin
    case join
    case unavailable
  }

  private(set) var phase: Phase = .idle

  var isIdle: Bool { phase == .idle }

  func accepts(_ sessionID: UInt64) -> Bool {
    switch phase {
    case .idle:
      false
    case .starting(let activeID), .recording(let activeID), .stopping(let activeID),
      .tearingDown(let activeID):
      activeID == sessionID
    }
  }

  mutating func begin(_ sessionID: UInt64) -> Bool {
    guard isIdle else { return false }
    phase = .starting(sessionID)
    return true
  }

  mutating func captureStarted(_ sessionID: UInt64) -> Bool {
    guard phase == .starting(sessionID) else { return false }
    phase = .recording(sessionID)
    return true
  }

  mutating func requestStop(_ sessionID: UInt64) -> StopDisposition {
    switch phase {
    case .starting(sessionID), .recording(sessionID):
      phase = .stopping(sessionID)
      return .begin
    case .stopping(sessionID), .tearingDown(sessionID):
      return .join
    default:
      return .unavailable
    }
  }

  mutating func beginTeardown(_ sessionID: UInt64) -> Bool {
    guard accepts(sessionID) else { return false }
    phase = .tearingDown(sessionID)
    return true
  }

  mutating func finishTeardown(_ sessionID: UInt64) -> Bool {
    guard phase == .tearingDown(sessionID) else { return false }
    phase = .idle
    return true
  }
}

@MainActor
public final class ScreenCaptureRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
  public var onUnexpectedFinish: ((Result<URL, Error>) -> Void)?

  private enum OutputEvent {
    case finished
    case failed(any Error)
  }

  private final class Session {
    let id: UInt64
    let stream: SCStream
    let recordingOutput: SCRecordingOutput
    let streamIdentity: ObjectIdentifier
    let outputIdentity: ObjectIdentifier
    let outputURL: URL
    var outputEvent: OutputEvent?
    var outputWaiter: CheckedContinuation<OutputEvent?, Never>?
    var outputTimeoutTask: Task<Void, Never>?
    var streamStopFallback: Task<Void, Never>?
    var stopTask: Task<URL, Error>?
    var teardownTask: Task<Void, Never>?

    init(id: UInt64, stream: SCStream, recordingOutput: SCRecordingOutput, outputURL: URL) {
      self.id = id
      self.stream = stream
      self.recordingOutput = recordingOutput
      streamIdentity = ObjectIdentifier(stream)
      outputIdentity = ObjectIdentifier(recordingOutput)
      self.outputURL = outputURL
    }
  }

  private let finalizationTimeout: Duration
  private var nextSessionID: UInt64 = 0
  private var lifecycle = RecorderLifecycle()
  private var activeSession: Session?

  public override convenience init() {
    self.init(finalizationTimeout: .seconds(2))
  }

  init(finalizationTimeout: Duration) {
    self.finalizationTimeout = finalizationTimeout
    super.init()
  }

  public func start(
    filter: SCContentFilter,
    outputURL: URL,
    options: RecordingOptions,
    configureStream: (SCStream) -> Void = { _ in }
  ) async throws {
    guard lifecycle.isIdle else {
      throw ScreenCaptureRecorderError.recordingAlreadyActive
    }

    let configuration = SCStreamConfiguration()
    let requestedWidth = max(2, filter.contentRect.width * CGFloat(filter.pointPixelScale))
    let requestedHeight = max(2, filter.contentRect.height * CGFloat(filter.pointPixelScale))
    let scale = min(1, min(1920 / requestedWidth, 1080 / requestedHeight))
    configuration.width = Self.evenDimension(requestedWidth * scale)
    configuration.height = Self.evenDimension(requestedHeight * scale)
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.queueDepth = 6
    configuration.scalesToFit = true
    configuration.preservesAspectRatio = true
    configuration.showsCursor = options.includesCursor
    configuration.showMouseClicks = options.showsMouseClicks
    configuration.ignoreShadowsSingleWindow = true
    configuration.ignoreGlobalClipSingleWindow = true
    configuration.shouldBeOpaque = true
    configuration.capturesAudio = false

    let outputConfiguration = SCRecordingOutputConfiguration()
    outputConfiguration.outputURL = outputURL
    outputConfiguration.videoCodecType = .h264
    outputConfiguration.outputFileType = .mp4
    let recordingOutput = SCRecordingOutput(
      configuration: outputConfiguration,
      delegate: self
    )
    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

    nextSessionID &+= 1
    let session = Session(
      id: nextSessionID,
      stream: stream,
      recordingOutput: recordingOutput,
      outputURL: outputURL
    )
    precondition(lifecycle.begin(session.id))
    activeSession = session

    do {
      try stream.addRecordingOutput(recordingOutput)
      configureStream(stream)
      try await stream.startCapture()
    } catch {
      await teardown(session, stoppingCapture: true)
      throw error
    }

    guard isActive(session), lifecycle.captureStarted(session.id) else {
      await teardown(session, stoppingCapture: true)
      throw ScreenCaptureRecorderError.startInterrupted(outputURL: outputURL)
    }
  }

  /// Stops and finalizes the active recording. Concurrent calls join the same bounded operation.
  public func stop() async throws -> URL {
    guard let session = activeSession else {
      throw ScreenCaptureRecorderError.noActiveRecording
    }
    if let stopTask = session.stopTask {
      return try await stopTask.value
    }

    switch lifecycle.requestStop(session.id) {
    case .begin:
      let task = Task { @MainActor [weak self] () throws -> URL in
        guard let self else { throw CancellationError() }
        return try await self.performStop(session)
      }
      session.stopTask = task
      return try await task.value
    case .join:
      if let teardownTask = session.teardownTask {
        await teardownTask.value
      }
      throw ScreenCaptureRecorderError.noActiveRecording
    case .unavailable:
      throw ScreenCaptureRecorderError.noActiveRecording
    }
  }

  /// Best-effort teardown for abandoned startup or recording work. It is safe to call repeatedly.
  public func cancel() async {
    guard let session = activeSession else { return }
    if let stopTask = session.stopTask {
      _ = try? await stopTask.value
      return
    }
    await teardown(session, stoppingCapture: true)
  }

  public nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
    let identity = ObjectIdentifier(recordingOutput)
    Task { @MainActor [weak self] in
      self?.handleOutputStarted(identity: identity)
    }
  }

  public nonisolated func recordingOutput(
    _ recordingOutput: SCRecordingOutput,
    didFailWithError error: any Error
  ) {
    let identity = ObjectIdentifier(recordingOutput)
    Task { @MainActor [weak self] in
      self?.handleOutputEvent(.failed(error), identity: identity)
    }
  }

  public nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
    let identity = ObjectIdentifier(recordingOutput)
    Task { @MainActor [weak self] in
      self?.handleOutputEvent(.finished, identity: identity)
    }
  }

  public nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
    let identity = ObjectIdentifier(stream)
    Task { @MainActor [weak self] in
      self?.handleStreamStopped(error: error, identity: identity)
    }
  }

  private func performStop(_ session: Session) async throws -> URL {
    let stopError: (any Error)?
    do {
      try await session.stream.stopCapture()
      stopError = nil
    } catch {
      stopError = error
    }

    let event: OutputEvent?
    if let outputEvent = session.outputEvent {
      event = outputEvent
    } else {
      event = await waitForOutputEvent(session)
    }
    let lastEvent = session.outputEvent ?? event
    await teardown(session, stoppingCapture: false)

    switch lastEvent {
    case .finished:
      return session.outputURL
    case .failed(let error):
      throw ScreenCaptureRecorderError.recordingOutputFailed(
        outputURL: session.outputURL,
        underlying: error
      )
    case nil:
      if let stopError {
        throw ScreenCaptureRecorderError.stopCaptureFailed(
          outputURL: session.outputURL,
          underlying: stopError
        )
      }
      throw ScreenCaptureRecorderError.finalizationTimedOut(outputURL: session.outputURL)
    }
  }

  private func waitForOutputEvent(_ session: Session) async -> OutputEvent? {
    guard isActive(session) else { return nil }
    if let outputEvent = session.outputEvent { return outputEvent }

    return await withCheckedContinuation { continuation in
      session.outputWaiter = continuation
      session.outputTimeoutTask = Task { @MainActor [weak self, weak session] in
        guard let self, let session else { return }
        try? await Task.sleep(for: finalizationTimeout)
        guard !Task.isCancelled, self.isActive(session) else { return }
        let waiter = session.outputWaiter
        session.outputWaiter = nil
        session.outputTimeoutTask = nil
        waiter?.resume(returning: nil)
      }
    }
  }

  private func handleOutputStarted(identity: ObjectIdentifier) {
    guard let session = activeSession, session.outputIdentity == identity,
      lifecycle.accepts(session.id)
    else { return }
  }

  private func handleOutputEvent(_ event: OutputEvent, identity: ObjectIdentifier) {
    guard let session = activeSession, session.outputIdentity == identity,
      lifecycle.accepts(session.id)
    else { return }

    session.streamStopFallback?.cancel()
    session.streamStopFallback = nil
    guard session.outputEvent == nil else { return }
    session.outputEvent = event
    session.outputTimeoutTask?.cancel()
    session.outputTimeoutTask = nil
    let waiter = session.outputWaiter
    session.outputWaiter = nil
    waiter?.resume(returning: event)

    switch lifecycle.phase {
    case .starting(session.id), .recording(session.id):
      finishUnexpectedly(event, session: session)
    default:
      break
    }
  }

  private func handleStreamStopped(error: any Error, identity: ObjectIdentifier) {
    guard let session = activeSession, session.streamIdentity == identity,
      lifecycle.accepts(session.id)
    else { return }

    switch lifecycle.phase {
    case .starting(session.id), .recording(session.id):
      session.streamStopFallback?.cancel()
      session.streamStopFallback = Task { @MainActor [weak self, weak session] in
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self, let session, self.isActive(session),
          session.outputEvent == nil
        else { return }
        self.finishUnexpectedly(
          .failed(
            ScreenCaptureRecorderError.streamStoppedUnexpectedly(
              outputURL: session.outputURL,
              underlying: error
            )
          ),
          session: session
        )
      }
    default:
      break
    }
  }

  private func finishUnexpectedly(_ event: OutputEvent, session: Session) {
    guard isActive(session), session.teardownTask == nil else { return }
    let result: Result<URL, Error>
    switch event {
    case .finished:
      result = .success(session.outputURL)
    case .failed(let error as ScreenCaptureRecorderError):
      result = .failure(error)
    case .failed(let error):
      result = .failure(
        ScreenCaptureRecorderError.recordingOutputFailed(
          outputURL: session.outputURL,
          underlying: error
        )
      )
    }
    let callback = onUnexpectedFinish
    let task = makeTeardownTask(session, stoppingCapture: true)
    Task { @MainActor in
      await task.value
      callback?(result)
    }
  }

  private func teardown(_ session: Session, stoppingCapture: Bool) async {
    let task = makeTeardownTask(session, stoppingCapture: stoppingCapture)
    await task.value
  }

  private func makeTeardownTask(
    _ session: Session,
    stoppingCapture: Bool
  ) -> Task<Void, Never> {
    if let teardownTask = session.teardownTask { return teardownTask }
    guard isActive(session), lifecycle.beginTeardown(session.id) else {
      return Task {}
    }

    session.streamStopFallback?.cancel()
    session.streamStopFallback = nil
    session.outputTimeoutTask?.cancel()
    session.outputTimeoutTask = nil
    let waiter = session.outputWaiter
    session.outputWaiter = nil
    waiter?.resume(returning: nil)

    let task = Task { @MainActor [weak self] in
      if stoppingCapture {
        try? await session.stream.stopCapture()
      }
      try? session.stream.removeRecordingOutput(session.recordingOutput)
      guard let self, self.isActive(session) else { return }
      session.stopTask = nil
      session.teardownTask = nil
      _ = self.lifecycle.finishTeardown(session.id)
      self.activeSession = nil
    }
    session.teardownTask = task
    return task
  }

  private func isActive(_ session: Session) -> Bool {
    activeSession === session && lifecycle.accepts(session.id)
  }

  private static func evenDimension(_ value: CGFloat) -> Int {
    let rounded = max(2, Int(value.rounded(.down)))
    return rounded.isMultiple(of: 2) ? rounded : rounded - 1
  }
}

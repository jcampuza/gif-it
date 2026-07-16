import Foundation

public enum CaptureFormat: String, Codable, CaseIterable, Sendable {
  case gif
  case mp4

  public var fileExtension: String { rawValue }
}

public enum GIFQuality: String, Codable, CaseIterable, Sendable {
  case low
  case standard
  case high

  public var displayName: String {
    switch self {
    case .low: "Low"
    case .standard: "Standard"
    case .high: "High"
    }
  }

  public var framesPerSecond: Double {
    switch self {
    case .low: 10
    case .standard: 15
    case .high: 20
    }
  }

  public var maximumPixelDimension: Double {
    switch self {
    case .low: 640
    case .standard: 960
    case .high: 1_440
    }
  }
}

public enum DestinationKind: String, Codable, CaseIterable, Sendable {
  case clipboard
  case folder
}

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let command = Self(rawValue: 1 << 0)
  public static let option = Self(rawValue: 1 << 1)
  public static let control = Self(rawValue: 1 << 2)
  public static let shift = Self(rawValue: 1 << 3)
}

public struct GlobalShortcut: Codable, Equatable, Sendable {
  public var keyCode: UInt32
  public var keyLabel: String
  public var modifiers: ShortcutModifiers

  public init(keyCode: UInt32, keyLabel: String, modifiers: ShortcutModifiers) {
    self.keyCode = keyCode
    self.keyLabel = keyLabel
    self.modifiers = modifiers
  }

  public static let defaultShortcut = GlobalShortcut(
    keyCode: 5,
    keyLabel: "G",
    modifiers: [.control, .option]
  )

  public var displayName: String {
    var value = ""
    if modifiers.contains(.control) { value += "⌃" }
    if modifiers.contains(.option) { value += "⌥" }
    if modifiers.contains(.shift) { value += "⇧" }
    if modifiers.contains(.command) { value += "⌘" }
    return value + keyLabel.uppercased()
  }
}

public struct CaptureSettings: Codable, Equatable, Sendable {
  public var format: CaptureFormat
  public var gifQuality: GIFQuality
  public var destination: DestinationKind
  public var folderPath: String?
  public var includesCursor: Bool
  public var showsMouseClicks: Bool
  public var shortcut: GlobalShortcut

  public init(
    format: CaptureFormat = .gif,
    gifQuality: GIFQuality = .standard,
    destination: DestinationKind = .clipboard,
    folderPath: String? = nil,
    includesCursor: Bool = true,
    showsMouseClicks: Bool = true,
    shortcut: GlobalShortcut = .defaultShortcut
  ) {
    self.format = format
    self.gifQuality = gifQuality
    self.destination = destination
    self.folderPath = folderPath
    self.includesCursor = includesCursor
    self.showsMouseClicks = showsMouseClicks
    self.shortcut = shortcut
  }

  private enum CodingKeys: String, CodingKey {
    case format
    case gifQuality
    case destination
    case folderPath
    case includesCursor
    case showsMouseClicks
    case shortcut
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    format = try container.decode(CaptureFormat.self, forKey: .format)
    gifQuality = try container.decodeIfPresent(GIFQuality.self, forKey: .gifQuality) ?? .standard
    destination = try container.decode(DestinationKind.self, forKey: .destination)
    folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath)
    includesCursor = try container.decode(Bool.self, forKey: .includesCursor)
    showsMouseClicks = try container.decode(Bool.self, forKey: .showsMouseClicks)
    shortcut = try container.decode(GlobalShortcut.self, forKey: .shortcut)
  }
}

public enum CaptureSource: Sendable {
  case window
  case region(displayID: UInt32, rect: CGRect)
}

public enum CapturePhase: Equatable, Sendable {
  case idle
  case picking
  case starting
  case recording
  case finalizing
  case converting(progress: Double)
  case delivering
  case failed(message: String)

  public var acceptsToggle: Bool {
    switch self {
    case .idle, .recording, .failed:
      true
    case .picking, .starting, .finalizing, .converting, .delivering:
      false
    }
  }

  public var isRecording: Bool {
    if case .recording = self { return true }
    return false
  }

  public var isStartingOrRecording: Bool {
    switch self {
    case .starting, .recording: true
    default: false
    }
  }
}

public enum CaptureEvent: Equatable, Sendable {
  case requestPicker
  case pickerCancelled
  case pickerSelected
  case recordingStarted
  case stopRequested
  case recordingFinalized
  case conversionProgress(Double)
  case conversionFinished
  case deliveryFinished
  case failed(String)
  case reset
}

public struct CaptureStateMachine: Sendable {
  public private(set) var phase: CapturePhase = .idle

  public init() {}

  @discardableResult
  public mutating func handle(_ event: CaptureEvent) -> Bool {
    let next: CapturePhase?
    switch (phase, event) {
    case (.idle, .requestPicker), (.failed, .requestPicker):
      next = .picking
    case (.picking, .pickerCancelled):
      next = .idle
    case (.picking, .pickerSelected):
      next = .starting
    case (.starting, .recordingStarted):
      next = .recording
    case (.starting, .pickerCancelled):
      next = .idle
    case (.starting, .stopRequested), (.recording, .stopRequested):
      next = .finalizing
    case (.finalizing, .recordingFinalized):
      next = .converting(progress: 0)
    case (.converting, .conversionProgress(let progress)):
      next = .converting(progress: min(max(progress, 0), 1))
    case (.converting, .conversionFinished):
      next = .delivering
    case (.delivering, .deliveryFinished):
      next = .idle
    case (_, .failed(let message)):
      next = .failed(message: message)
    case (_, .reset):
      next = .idle
    default:
      next = nil
    }

    guard let next else { return false }
    phase = next
    return true
  }
}

public struct ArtifactRecoveryPlan: Equatable, Sendable {
  public var preservedArtifact: URL?
  public var abandonedArtifacts: [URL]

  public init(preservedArtifact: URL?, abandonedArtifacts: [URL]) {
    self.preservedArtifact = preservedArtifact
    self.abandonedArtifacts = abandonedArtifacts
  }
}

public enum ArtifactRecoveryPolicy {
  /// Explicit recovery sources (for example, a failed GIF conversion's MP4) take
  /// precedence over recorder-provided output. Neither is kept unless it is usable.
  public static func plan(
    currentWorkingURL: URL?,
    existingLastArtifact: URL?,
    recorderOutputURL: URL?,
    explicitRecoveryURL: URL?,
    isPlausible: (URL) -> Bool
  ) -> ArtifactRecoveryPlan {
    let candidate = explicitRecoveryURL ?? recorderOutputURL
    let preserved = [candidate, existingLastArtifact]
      .compactMap { $0 }
      .first(where: isPlausible)
    let abandoned = [currentWorkingURL]
      .compactMap { $0 }
      .filter { $0 != preserved }
    return ArtifactRecoveryPlan(
      preservedArtifact: preserved,
      abandonedArtifacts: abandoned
    )
  }
}

public enum TerminationAction: Equatable, Sendable {
  case teardown
  case dismissPicker
  case cancelStartupAndRecover
  case finalizeRecording
  case awaitFinalization

  public init(phase: CapturePhase) {
    switch phase {
    case .idle, .failed:
      self = .teardown
    case .picking:
      self = .dismissPicker
    case .starting:
      self = .cancelStartupAndRecover
    case .recording:
      self = .finalizeRecording
    case .finalizing, .converting, .delivering:
      self = .awaitFinalization
    }
  }
}

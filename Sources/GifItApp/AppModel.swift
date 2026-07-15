import AppKit
import Combine
import GifItCore
import GifItMac
@preconcurrency import ScreenCaptureKit

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var phase: CapturePhase = .idle
  @Published private(set) var statusMessage = "Ready to capture a window"
  @Published private(set) var settings: CaptureSettings
  @Published private(set) var screenRecordingGranted = ScreenRecordingPermission.isGranted
  @Published private(set) var isRecordingShortcut = false

  private let persistence: SettingsPersistence
  private let picker: WindowPickerCoordinator
  private let recorder: any RecordingControlling
  private let exporter: any MediaExporting
  private let delivery: any ArtifactDelivering
  private let artifacts: any ArtifactStoring
  private let hotKey: GlobalShortcutRegistrar
  private let recordingPanel: RecordingPanelController
  private let fileManager: FileManager

  private var machine = CaptureStateMachine()
  private var activeSettings: CaptureSettings?
  private var recordingStartedAt: Date?
  private var currentWorkingURL: URL?
  private var workflowID: UInt64 = 0
  private var startTask: Task<Void, Never>?
  private var finalizationTask: Task<Void, Never>?
  private var autoStopTask: Task<Void, Never>?
  private var shortcutMonitor: Any?
  private var activationObserver: NSObjectProtocol?
  private var isTerminating = false
  private(set) var lastArtifact: URL?

  init(
    persistence: SettingsPersistence = SettingsPersistence(),
    picker: WindowPickerCoordinator = WindowPickerCoordinator(),
    recorder: any RecordingControlling = ScreenCaptureRecorder(),
    exporter: any MediaExporting = MediaExporter(),
    delivery: any ArtifactDelivering = ArtifactDelivery(),
    artifacts: any ArtifactStoring = ArtifactStore(),
    hotKey: GlobalShortcutRegistrar = GlobalShortcutRegistrar(),
    recordingPanel: RecordingPanelController = RecordingPanelController(),
    fileManager: FileManager = .default
  ) {
    self.persistence = persistence
    self.picker = picker
    self.recorder = recorder
    self.exporter = exporter
    self.delivery = delivery
    self.artifacts = artifacts
    self.hotKey = hotKey
    self.recordingPanel = recordingPanel
    self.fileManager = fileManager
    settings = persistence.load()

    picker.onSelection = { [weak self] filter in
      self?.launchRecording(filter: filter)
    }
    picker.onCancellation = { [weak self] _ in
      guard let self else { return }
      switch self.phase {
      case .starting:
        Task { @MainActor in await self.cancelStartup() }
      case .recording:
        Task { @MainActor in await self.stopRecording() }
      case .picking:
        self.picker.deactivate()
        self.transition(.pickerCancelled)
        self.statusMessage = "Capture cancelled"
      default:
        break
      }
    }
    picker.onFailure = { [weak self] error in
      Task { @MainActor in await self?.failWorkflow(error) }
    }
    recorder.onUnexpectedFinish = { [weak self] result in
      Task { @MainActor in self?.unexpectedFinish(result) }
    }
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.screenRecordingGranted = ScreenRecordingPermission.isGranted
      }
    }

    registerShortcut(settings.shortcut)
    Task { [artifacts] in try? await artifacts.prune() }
  }

  var menuBarSymbol: String {
    switch phase {
    case .recording: "record.circle.fill"
    case .starting, .converting, .delivering, .finalizing: "hourglass"
    case .failed: "exclamationmark.triangle"
    default: "viewfinder.rectangular"
    }
  }

  var canCapture: Bool {
    switch phase {
    case .idle, .failed: !isTerminating
    default: false
    }
  }

  var canStop: Bool { phase.isRecording && !isTerminating }
  var hasLastArtifact: Bool { lastArtifact.map(isPlausibleArtifact) == true }

  func toggleCapture() {
    switch phase {
    case .idle, .failed:
      requestCapture()
    case .recording:
      Task { await stopRecording() }
    default:
      NSSound.beep()
    }
  }

  func requestCapture() {
    guard canCapture else { return }
    screenRecordingGranted = ScreenRecordingPermission.isGranted
    if !screenRecordingGranted {
      screenRecordingGranted = ScreenRecordingPermission.request()
      guard screenRecordingGranted else {
        transition(.failed("Screen Recording permission is required"))
        statusMessage = "Allow Gif It in Privacy & Security > Screen Recording"
        return
      }
    }

    transition(.requestPicker)
    statusMessage = "Choose a window"
    picker.present()
  }

  func stopRecording() async {
    if let finalizationTask {
      await finalizationTask.value
      return
    }
    guard phase.isRecording else { return }
    stopCaptureUI()
    transition(.stopRequested)
    statusMessage = "Finishing recording…"
    let id = workflowID
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.stopAndFinalize(workflowID: id)
    }
    finalizationTask = task
    await task.value
  }

  func setFormat(_ format: CaptureFormat) {
    settings.format = format
    persistSettings()
  }

  func setDestination(_ destination: DestinationKind) {
    settings.destination = destination
    persistSettings()
  }

  func setIncludesCursor(_ includesCursor: Bool) {
    settings.includesCursor = includesCursor
    persistSettings()
  }

  func setShowsMouseClicks(_ showsMouseClicks: Bool) {
    settings.showsMouseClicks = showsMouseClicks
    persistSettings()
  }

  func chooseFolder() {
    let panel = NSOpenPanel()
    panel.title = "Choose Capture Destination"
    panel.prompt = "Choose"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      settings.folderPath = url.path
      settings.destination = .folder
      persistSettings()
    }
  }

  func revealDestinationFolder() {
    guard let path = settings.folderPath else { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
  }

  func beginShortcutRecording() {
    guard shortcutMonitor == nil, !isTerminating else { return }
    isRecordingShortcut = true
    statusMessage = "Press a shortcut, or Escape to cancel"
    shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      Task { @MainActor in self?.handleShortcutEvent(event) }
      return nil
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  func requestScreenRecordingAccess() {
    screenRecordingGranted = ScreenRecordingPermission.isGranted
    if !screenRecordingGranted {
      _ = ScreenRecordingPermission.request()
      screenRecordingGranted = ScreenRecordingPermission.isGranted
    }

    statusMessage =
      screenRecordingGranted
      ? "Screen Recording is allowed"
      : "Enable Gif It in Screen Recording, then relaunch"
    ScreenRecordingPermission.openSystemSettings()
  }

  func saveLastRecordingAs() {
    guard let source = lastArtifact, isPlausibleArtifact(source) else { return }
    let panel = NSSavePanel()
    panel.title = "Save Last Recording"
    panel.nameFieldStringValue = source.lastPathComponent
    if panel.runModal() == .OK, let destination = panel.url {
      do {
        try TransactionalFileReplacement.copy(source: source, replacing: destination)
        statusMessage = "Saved \(destination.lastPathComponent)"
      } catch {
        statusMessage = error.localizedDescription
      }
    }
  }

  /// Stops accepting UI work and gives an in-flight recording its normal finalization path.
  func prepareForTermination() async {
    guard !isTerminating else {
      if let finalizationTask { await finalizationTask.value }
      return
    }
    isTerminating = true
    finishShortcutRecording()
    picker.deactivate()
    recordingPanel.hide()
    autoStopTask?.cancel()
    autoStopTask = nil

    switch TerminationAction(phase: phase) {
    case .cancelStartupAndRecover:
      await cancelStartup(preserveRecovery: true)
    case .finalizeRecording:
      // `canStop` becomes false while terminating, but the workflow method deliberately
      // remains available so termination can preserve a complete recording.
      await stopRecording()
    case .awaitFinalization:
      if let finalizationTask { await finalizationTask.value }
    case .dismissPicker:
      transition(.pickerCancelled)
    case .teardown:
      break
    }
    await recorder.cancel()
    preserveOrRemoveWorkingArtifact()
  }

  /// Called by the application delegate after its grace period expires.
  func forceTerminationCleanup() async {
    isTerminating = true
    startTask?.cancel()
    finalizationTask?.cancel()
    autoStopTask?.cancel()
    finishShortcutRecording()
    picker.deactivate()
    recordingPanel.hide()
    await recorder.cancel()
    preserveOrRemoveWorkingArtifact()
  }

  private func launchRecording(filter: SCContentFilter) {
    guard phase == .picking, !isTerminating else { return }
    workflowID &+= 1
    let id = workflowID
    let snapshot = settings
    activeSettings = snapshot
    recordingStartedAt = nil
    transition(.pickerSelected)
    statusMessage = "Starting recording…"
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.startRecording(filter: filter, settings: snapshot, workflowID: id)
    }
    startTask = task
  }

  private func startRecording(
    filter: SCContentFilter,
    settings snapshot: CaptureSettings,
    workflowID id: UInt64
  ) async {
    do {
      let workingURL = try await artifacts.makeWorkingURL()
      guard ownsStartingWorkflow(id) else {
        await artifacts.remove(workingURL)
        return
      }
      currentWorkingURL = workingURL
      try await recorder.start(
        filter: filter,
        outputURL: workingURL,
        options: RecordingOptions(
          includesCursor: snapshot.includesCursor,
          showsMouseClicks: snapshot.showsMouseClicks
        ),
        configureStream: { [picker] stream in picker.configure(stream: stream) }
      )
      guard ownsStartingWorkflow(id) else {
        await recorder.cancel()
        return
      }

      let startedAt = Date()
      recordingStartedAt = startedAt
      transition(.recordingStarted)
      statusMessage = "Recording • 0:00 / 0:30"
      recordingPanel.show(startedAt: startedAt) { [weak self] in
        Task { @MainActor in await self?.stopRecording() }
      }
      autoStopTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled else { return }
        await self?.stopRecording()
      }
    } catch {
      guard ownsStartingWorkflow(id) else {
        await recorder.cancel()
        return
      }
      await failWorkflow(error)
    }
    if workflowID == id { startTask = nil }
  }

  private func cancelStartup(preserveRecovery: Bool = false) async {
    guard phase == .starting else { return }
    workflowID &+= 1
    startTask?.cancel()
    startTask = nil
    stopCaptureUI()
    await recorder.cancel()
    if preserveRecovery {
      preserveOrRemoveWorkingArtifact()
    } else {
      await removeCurrentWorkingArtifact()
    }
    activeSettings = nil
    recordingStartedAt = nil
    transition(.pickerCancelled)
    statusMessage = "Capture cancelled"
  }

  private func stopAndFinalize(workflowID id: UInt64) async {
    defer { finalizationTask = nil }
    do {
      let source = try await recorder.stop()
      guard id == workflowID else {
        await artifacts.remove(source)
        return
      }
      try await finalize(source: source, settings: activeSettings ?? settings)
    } catch {
      guard id == workflowID else { return }
      await failWorkflow(error)
    }
  }

  private func unexpectedFinish(_ result: Result<URL, Error>) {
    guard phase.isStartingOrRecording, finalizationTask == nil else { return }
    stopCaptureUI()
    transition(.stopRequested)
    let id = workflowID
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.finalizationTask = nil }
      switch result {
      case .success(let source):
        do {
          try await self.finalize(source: source, settings: self.activeSettings ?? self.settings)
        } catch {
          await self.failWorkflow(error)
        }
      case .failure(let error):
        await self.failWorkflow(error)
      }
      if id != self.workflowID { return }
    }
    finalizationTask = task
  }

  private func finalize(source: URL, settings: CaptureSettings) async throws {
    let elapsed = Date().timeIntervalSince(recordingStartedAt ?? Date())
    guard elapsed >= 0.5 else {
      await artifacts.remove(source)
      if currentWorkingURL == source { currentWorkingURL = nil }
      clearActiveWorkflow()
      transition(.reset)
      statusMessage = "Recording too short"
      return
    }
    statusMessage = "Finishing recording…"
    do {
      try await exportAndDeliver(source: source, settings: settings)
    } catch {
      await failWorkflow(error, recoveryCandidate: source)
    }
  }

  private func exportAndDeliver(source: URL, settings: CaptureSettings) async throws {
    transition(.recordingFinalized)
    let artifact: URL
    switch settings.format {
    case .mp4:
      statusMessage = "Preparing MP4…"
      artifact = try await artifacts.promoteMP4(source)
      if currentWorkingURL == source { currentWorkingURL = nil }
    case .gif:
      statusMessage = "Converting GIF… 0%"
      let destination = try await artifacts.makeFinalURL(for: .gif)
      do {
        artifact = try await exporter.makeGIF(from: source, to: destination) {
          [weak self] progress in
          Task { @MainActor in
            guard let self else { return }
            if case .failed = self.phase { return }
            self.transition(.conversionProgress(progress))
            self.statusMessage = "Converting GIF… \(Int(progress * 100))%"
          }
        }
        await artifacts.remove(source)
        if currentWorkingURL == source { currentWorkingURL = nil }
      } catch {
        await artifacts.remove(destination)
        throw error
      }
    }

    lastArtifact = artifact
    transition(.conversionFinished)
    statusMessage = settings.destination == .clipboard ? "Copying…" : "Saving…"
    let deliveredURL = try delivery.deliver(
      artifact: artifact,
      format: settings.format,
      settings: settings
    )
    transition(.deliveryFinished)
    statusMessage =
      settings.destination == .clipboard
      ? "Copied \(artifact.lastPathComponent)"
      : "Saved \(deliveredURL.lastPathComponent)"
    clearActiveWorkflow()
    try? await artifacts.prune()
  }

  private func failWorkflow(_ error: Error, recoveryCandidate: URL? = nil) async {
    stopCaptureUI()
    await recorder.cancel()

    let plan = ArtifactRecoveryPolicy.plan(
      currentWorkingURL: currentWorkingURL,
      existingLastArtifact: lastArtifact,
      recorderOutputURL: (error as? ScreenCaptureRecorderError)?.outputURL,
      explicitRecoveryURL: recoveryCandidate,
      isPlausible: isPlausibleArtifact
    )
    lastArtifact = plan.preservedArtifact
    for artifact in plan.abandonedArtifacts { await artifacts.remove(artifact) }
    currentWorkingURL = nil
    clearActiveWorkflow()
    transition(.failed(error.localizedDescription))
    statusMessage = error.localizedDescription
  }

  private func ownsStartingWorkflow(_ id: UInt64) -> Bool {
    id == workflowID && phase == .starting && !isTerminating
  }

  private func stopCaptureUI() {
    autoStopTask?.cancel()
    autoStopTask = nil
    recordingPanel.hide()
    picker.deactivate()
  }

  private func clearActiveWorkflow() {
    activeSettings = nil
    recordingStartedAt = nil
  }

  private func removeCurrentWorkingArtifact() async {
    guard let currentWorkingURL else { return }
    await artifacts.remove(currentWorkingURL)
    self.currentWorkingURL = nil
  }

  private func preserveOrRemoveWorkingArtifact() {
    guard let working = currentWorkingURL else { return }
    if isPlausibleArtifact(working) {
      lastArtifact = working
    } else {
      Task { [artifacts] in await artifacts.remove(working) }
    }
    currentWorkingURL = nil
  }

  private func isPlausibleArtifact(_ url: URL) -> Bool {
    guard url.isFileURL,
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    else { return false }
    return values.isRegularFile == true && (values.fileSize ?? 0) > 0
  }

  private func registerShortcut(_ shortcut: GlobalShortcut) {
    do {
      try hotKey.register(shortcut: shortcut) { [weak self] in self?.toggleCapture() }
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func handleShortcutEvent(_ event: NSEvent) {
    if event.keyCode == 53 {
      finishShortcutRecording()
      statusMessage = "Shortcut unchanged"
      return
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var modifiers: ShortcutModifiers = []
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    guard !modifiers.isEmpty else {
      statusMessage = "Include Command, Option, Control, or Shift"
      NSSound.beep()
      return
    }

    let shortcut = GlobalShortcut(
      keyCode: UInt32(event.keyCode),
      keyLabel: Self.keyLabel(for: event),
      modifiers: modifiers
    )
    do {
      try hotKey.register(shortcut: shortcut) { [weak self] in self?.toggleCapture() }
      settings.shortcut = shortcut
      persistSettings()
      finishShortcutRecording()
      statusMessage = "Shortcut set to \(shortcut.displayName)"
    } catch {
      statusMessage = error.localizedDescription
      NSSound.beep()
    }
  }

  private func finishShortcutRecording() {
    if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
    shortcutMonitor = nil
    isRecordingShortcut = false
  }

  private func persistSettings() {
    persistence.save(settings)
  }

  private func transition(_ event: CaptureEvent) {
    if machine.handle(event) { phase = machine.phase }
  }

  private static func keyLabel(for event: NSEvent) -> String {
    let special: [UInt16: String] = [
      36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
      123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    if let label = special[event.keyCode] { return label }
    let value = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.isEmpty == false ? value!.uppercased() : "Key \(event.keyCode)"
  }
}

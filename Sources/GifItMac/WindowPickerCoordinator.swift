import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
public final class WindowPickerCoordinator: NSObject, SCContentSharingPickerObserver {
  public var onSelection: ((SCContentFilter) -> Void)?
  public var onCancellation: ((Bool) -> Void)?
  public var onFailure: ((Error) -> Void)?

  private let picker = SCContentSharingPicker.shared

  public override init() {
    super.init()
    picker.add(self)
  }

  deinit {
    picker.remove(self)
  }

  public func present() {
    let configuration = makeConfiguration()
    picker.configuration = configuration
    picker.maximumStreamCount = 1
    picker.isActive = true
    picker.present(using: .window)
  }

  public func configure(stream: SCStream) {
    picker.setConfiguration(makeConfiguration(), for: stream)
  }

  public func deactivate() {
    picker.isActive = false
  }

  public nonisolated func contentSharingPicker(
    _ picker: SCContentSharingPicker,
    didCancelFor stream: SCStream?
  ) {
    let hasStream = stream != nil
    Task { @MainActor in onCancellation?(hasStream) }
  }

  public nonisolated func contentSharingPicker(
    _ picker: SCContentSharingPicker,
    didUpdateWith filter: SCContentFilter,
    for stream: SCStream?
  ) {
    Task { @MainActor in onSelection?(filter) }
  }

  public nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
    Task { @MainActor in
      deactivate()
      onFailure?(error)
    }
  }

  private func makeConfiguration() -> SCContentSharingPickerConfiguration {
    var configuration = SCContentSharingPickerConfiguration()
    configuration.allowedPickerModes = .singleWindow
    configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
    configuration.excludedWindowIDs = []
    configuration.allowsChangingSelectedContent = false
    return configuration
  }
}

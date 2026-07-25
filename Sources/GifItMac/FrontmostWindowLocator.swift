import CoreGraphics
import Foundation
import GifItCore
@preconcurrency import ScreenCaptureKit

public enum FrontmostWindowError: LocalizedError {
  case noEligibleWindow

  public var errorDescription: String? {
    switch self {
    case .noEligibleWindow:
      "Couldn’t find a window in front to record."
    }
  }
}

/// Resolves the window that is already frontmost, so the hotkey can start recording
/// without making the user re-focus and re-pick the window they were just using.
@MainActor
public struct FrontmostWindowLocator {
  public init() {}

  public func locate() async throws -> SCContentFilter {
    let content = try await SCShareableContent.excludingDesktopWindows(
      true,
      onScreenWindowsOnly: true
    )
    let windowsByID = Dictionary(
      content.windows.map { (UInt32($0.windowID), $0) },
      uniquingKeysWith: { first, _ in first }
    )

    // `SCShareableContent` does not promise front-to-back ordering, so take the order from
    // the window server and fall back to the shareable list if that lookup comes up empty.
    let orderedIDs = Self.onScreenWindowIDsFrontToBack()
    let ordered =
      orderedIDs.isEmpty
      ? content.windows
      : orderedIDs.compactMap { windowsByID[$0] }

    let excluded = Set([Bundle.main.bundleIdentifier].compactMap { $0 })
    guard
      let selection = FrontmostWindowPolicy.select(
        from: ordered.map(Self.makeCandidate),
        excludingBundleIDs: excluded
      ),
      let window = windowsByID[selection.id]
    else {
      throw FrontmostWindowError.noEligibleWindow
    }

    return SCContentFilter(desktopIndependentWindow: window)
  }

  private static func makeCandidate(_ window: SCWindow) -> WindowCandidate {
    WindowCandidate(
      id: UInt32(window.windowID),
      layer: window.windowLayer,
      width: window.frame.width,
      height: window.frame.height,
      title: window.title,
      bundleIdentifier: window.owningApplication?.bundleIdentifier
    )
  }

  private static func onScreenWindowIDsFrontToBack() -> [UInt32] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard
      let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return [] }
    return info.compactMap { $0[kCGWindowNumber as String] as? UInt32 }
  }
}

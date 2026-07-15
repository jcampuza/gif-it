import AppKit
import CoreGraphics

public enum ScreenRecordingPermission {
  public static var isGranted: Bool {
    CGPreflightScreenCaptureAccess()
  }

  @discardableResult
  public static func request() -> Bool {
    CGRequestScreenCaptureAccess()
  }

  public static func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }
}

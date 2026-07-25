import Foundation

/// A framework-free description of an on-screen window, ordered front to back by the caller.
public struct WindowCandidate: Equatable, Sendable {
  public var id: UInt32
  /// Window server level. Normal application windows sit at layer 0; floating overlays,
  /// HUDs, and menu bar items sit above it.
  public var layer: Int
  public var width: Double
  public var height: Double
  public var title: String?
  public var bundleIdentifier: String?

  public init(
    id: UInt32,
    layer: Int,
    width: Double,
    height: Double,
    title: String? = nil,
    bundleIdentifier: String? = nil
  ) {
    self.id = id
    self.layer = layer
    self.width = width
    self.height = height
    self.title = title
    self.bundleIdentifier = bundleIdentifier
  }
}

/// Picks the window a capture should target when the user does not want to choose one.
///
/// The system window picker orders by raw window server order, which puts floating
/// overlays (dictation HUDs, notification banners) ahead of the document window the user
/// is actually looking at. This policy skips those so the hotkey records the window that
/// was already in front.
public enum FrontmostWindowPolicy {
  /// Windows smaller than this in either dimension are treated as chrome, not content.
  public static let minimumDimension: Double = 120

  public static func select(
    from candidates: [WindowCandidate],
    excludingBundleIDs excluded: Set<String> = []
  ) -> WindowCandidate? {
    candidates.first { candidate in
      candidate.layer == 0
        && candidate.width >= minimumDimension
        && candidate.height >= minimumDimension
        && !excluded.contains(candidate.bundleIdentifier ?? "")
    }
  }
}

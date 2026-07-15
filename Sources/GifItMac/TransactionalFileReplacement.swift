import Foundation

public enum TransactionalFileReplacement {
  /// Copies `source` into the destination directory, then atomically installs the staged copy.
  /// An existing destination is not touched unless staging succeeds.
  public static func copy(source: URL, replacing destination: URL) throws {
    let fileManager = FileManager.default
    let parent = destination.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    let staged = parent.appendingPathComponent(".GifIt-\(UUID().uuidString).staged")

    do {
      try fileManager.copyItem(at: source, to: staged)
      if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(
          destination,
          withItemAt: staged,
          backupItemName: nil,
          options: []
        )
      } else {
        try fileManager.moveItem(at: staged, to: destination)
      }
    } catch {
      try? fileManager.removeItem(at: staged)
      throw error
    }
  }
}

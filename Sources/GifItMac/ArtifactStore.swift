import Foundation
import GifItCore

public actor ArtifactStore {
  public let rootURL: URL
  private let fileManager: FileManager

  public init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    if let rootURL {
      self.rootURL = rootURL
    } else {
      let cache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      let bundleID = Bundle.main.bundleIdentifier ?? "com.josephcampuzano.gif-it"
      self.rootURL =
        cache
        .appendingPathComponent(bundleID, isDirectory: true)
        .appendingPathComponent("Captures", isDirectory: true)
    }
  }

  public func makeWorkingURL() throws -> URL {
    try ensureRoot()
    return rootURL.appendingPathComponent("Working-\(UUID().uuidString).mp4")
  }

  public func makeFinalURL(for format: CaptureFormat, date: Date = Date()) throws -> URL {
    try ensureRoot()
    return ArtifactNaming.uniqueURL(in: rootURL, format: format, date: date) { name in
      fileManager.fileExists(atPath: rootURL.appendingPathComponent(name).path)
    }
  }

  public func promoteMP4(_ source: URL, date: Date = Date()) throws -> URL {
    let destination = try makeFinalURL(for: .mp4, date: date)
    try fileManager.moveItem(at: source, to: destination)
    return destination
  }

  public func remove(_ url: URL) {
    try? fileManager.removeItem(at: url)
  }

  public func prune(now: Date = Date(), maximumAge: TimeInterval = 86_400, limit: Int = 10) throws {
    try ensureRoot()
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
    let entries = try fileManager.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles]
    )
    let files = entries.compactMap { url -> (URL, Date)? in
      guard
        let values = try? url.resourceValues(forKeys: keys),
        values.isRegularFile == true
      else { return nil }
      return (url, values.contentModificationDate ?? .distantPast)
    }
    .sorted { $0.1 > $1.1 }

    for (index, entry) in files.enumerated() {
      if index >= limit || now.timeIntervalSince(entry.1) > maximumAge {
        try? fileManager.removeItem(at: entry.0)
      }
    }
  }

  private func ensureRoot() throws {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
  }
}

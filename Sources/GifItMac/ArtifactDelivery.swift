import AppKit
import Foundation
import GifItCore
import UniformTypeIdentifiers

public enum ArtifactDeliveryError: LocalizedError {
  case missingFolder
  case couldNotPrepareClipboardFileURL
  case couldNotPrepareClipboardGIFData
  case couldNotWriteToClipboard

  public var errorDescription: String? {
    switch self {
    case .missingFolder:
      "Choose a destination folder in Settings before recording."
    case .couldNotPrepareClipboardFileURL:
      "Couldn’t prepare the recording’s file URL for the clipboard."
    case .couldNotPrepareClipboardGIFData:
      "Couldn’t prepare the GIF data for the clipboard."
    case .couldNotWriteToClipboard:
      "Couldn’t write the recording to the clipboard."
    }
  }
}

@MainActor
protocol ArtifactPasteboardWriting: AnyObject {
  @discardableResult
  func clearContents() -> Int

  func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: ArtifactPasteboardWriting {}

@MainActor
protocol ArtifactPasteboardItemBuilding: AnyObject {
  func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
  func setData(_ data: Data, forType dataType: NSPasteboard.PasteboardType) -> Bool

  var pasteboardWriting: any NSPasteboardWriting { get }
}

extension NSPasteboardItem: ArtifactPasteboardItemBuilding {
  var pasteboardWriting: any NSPasteboardWriting { self }
}

@MainActor
public final class ArtifactDelivery {
  private let fileManager: FileManager
  private let pasteboard: any ArtifactPasteboardWriting
  private let makePasteboardItem: () -> any ArtifactPasteboardItemBuilding

  public init(
    fileManager: FileManager = .default,
    pasteboard: NSPasteboard = .general
  ) {
    self.fileManager = fileManager
    self.pasteboard = pasteboard
    self.makePasteboardItem = { NSPasteboardItem() }
  }

  init(
    fileManager: FileManager = .default,
    pasteboardWriter: any ArtifactPasteboardWriting,
    makePasteboardItem: @escaping () -> any ArtifactPasteboardItemBuilding
  ) {
    self.fileManager = fileManager
    self.pasteboard = pasteboardWriter
    self.makePasteboardItem = makePasteboardItem
  }

  @discardableResult
  public func deliver(
    artifact: URL,
    format: CaptureFormat,
    settings: CaptureSettings
  ) throws -> URL {
    switch settings.destination {
    case .clipboard:
      try copyToClipboard(artifact: artifact, format: format)
      return artifact
    case .folder:
      guard let folderPath = settings.folderPath, !folderPath.isEmpty else {
        throw ArtifactDeliveryError.missingFolder
      }
      let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
      let destination = ArtifactNaming.uniqueURL(in: folder, format: format) { name in
        fileManager.fileExists(atPath: folder.appendingPathComponent(name).path)
      }
      try fileManager.copyItem(at: artifact, to: destination)
      return destination
    }
  }

  public func copyToClipboard(artifact: URL, format: CaptureFormat) throws {
    let item = makePasteboardItem()
    guard item.setString(artifact.absoluteString, forType: .fileURL) else {
      throw ArtifactDeliveryError.couldNotPrepareClipboardFileURL
    }

    if format == .gif {
      let data = try Data(contentsOf: artifact)
      guard
        item.setData(
          data,
          forType: NSPasteboard.PasteboardType(UTType.gif.identifier)
        )
      else {
        throw ArtifactDeliveryError.couldNotPrepareClipboardGIFData
      }
    }

    // AppKit requires clearing before writing a new set of pasteboard objects. Build the
    // complete item first so preparation failures do not disturb the user's clipboard.
    pasteboard.clearContents()
    guard pasteboard.writeObjects([item.pasteboardWriting]) else {
      throw ArtifactDeliveryError.couldNotWriteToClipboard
    }
  }
}

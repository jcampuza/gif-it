import AppKit
import Foundation
import GifItCore
import Testing
import UniformTypeIdentifiers
@testable import GifItMac

@MainActor
private final class PasteboardSpy: ArtifactPasteboardWriting {
  var clearContentsCallCount = 0
  var writtenObjects: [any NSPasteboardWriting] = []
  var writeResult = true

  func clearContents() -> Int {
    clearContentsCallCount += 1
    return clearContentsCallCount
  }

  func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
    writtenObjects = objects
    return writeResult
  }
}

@MainActor
private final class PasteboardItemStub: ArtifactPasteboardItemBuilding {
  let item = NSPasteboardItem()
  var setStringResult = true
  var setDataResult = true
  var setStringCallCount = 0
  var setDataCallCount = 0

  func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
    setStringCallCount += 1
    guard setStringResult else { return false }
    return item.setString(string, forType: dataType)
  }

  func setData(_ data: Data, forType dataType: NSPasteboard.PasteboardType) -> Bool {
    setDataCallCount += 1
    guard setDataResult else { return false }
    return item.setData(data, forType: dataType)
  }

  var pasteboardWriting: any NSPasteboardWriting { item }
}

@Test func artifactStoreCreatesUniqueFinalURLs() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = ArtifactStore(rootURL: root)
  let first = try await store.makeFinalURL(for: .gif, date: Date(timeIntervalSince1970: 0))
  try Data().write(to: first)
  let second = try await store.makeFinalURL(for: .gif, date: Date(timeIntervalSince1970: 0))

  #expect(first != second)
  #expect(second.deletingPathExtension().lastPathComponent.hasSuffix(" 2"))
}

@Test func settingsPersistenceRoundTrips() {
  let suiteName = "GifItTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let persistence = SettingsPersistence(defaults: defaults)
  var settings = CaptureSettings()
  settings.format = .mp4
  settings.gifQuality = .high
  settings.destination = .folder
  settings.folderPath = "/tmp/Exports"

  persistence.save(settings)

  #expect(persistence.load() == settings)
}

@Test func artifactStorePrunesOldAndExcessFiles() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let now = Date()
  for index in 0..<12 {
    let url = root.appendingPathComponent("\(index).mp4")
    try Data([UInt8(index)]).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(TimeInterval(-index))],
      ofItemAtPath: url.path
    )
  }
  let stale = root.appendingPathComponent("stale.mp4")
  try Data().write(to: stale)
  try FileManager.default.setAttributes(
    [.modificationDate: now.addingTimeInterval(-90_000)],
    ofItemAtPath: stale.path
  )
  let store = ArtifactStore(rootURL: root)

  try await store.prune(now: now, limit: 10)

  let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
  #expect(remaining.count == 10)
  #expect(!remaining.contains("stale.mp4"))
}

@Test func transactionalReplacementPreservesExistingDestinationWhenStagingFails() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let missingSource = root.appendingPathComponent("missing.mp4")
  let destination = root.appendingPathComponent("Capture.mp4")
  try Data([1, 2, 3]).write(to: destination)

  #expect(throws: (any Error).self) {
    try TransactionalFileReplacement.copy(source: missingSource, replacing: destination)
  }
  #expect(try Data(contentsOf: destination) == Data([1, 2, 3]))
}

@Test func transactionalReplacementInstallsStagedCopy() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source.mp4")
  let destination = root.appendingPathComponent("Capture.mp4")
  try Data([4, 5, 6]).write(to: source)
  try Data([1, 2, 3]).write(to: destination)

  try TransactionalFileReplacement.copy(source: source, replacing: destination)

  #expect(try Data(contentsOf: destination) == Data([4, 5, 6]))
  #expect(try Data(contentsOf: source) == Data([4, 5, 6]))
  let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
  #expect(!entries.contains { $0.hasSuffix(".staged") })
}

@Test @MainActor func gifClipboardPublishesDataAndFileURL() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let artifact = root.appendingPathComponent("Capture.gif")
  try Data([0x47, 0x49, 0x46]).write(to: artifact)
  let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
  let delivery = ArtifactDelivery(pasteboard: pasteboard)

  try delivery.copyToClipboard(artifact: artifact, format: .gif)

  #expect(pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.gif.identifier)) != nil)
  #expect(pasteboard.string(forType: .fileURL) == artifact.absoluteString)
}

@Test @MainActor func mp4ClipboardPublishesFileURL() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let artifact = root.appendingPathComponent("Capture.mp4")
  try Data([0, 1, 2]).write(to: artifact)
  let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
  let delivery = ArtifactDelivery(pasteboard: pasteboard)

  try delivery.copyToClipboard(artifact: artifact, format: .mp4)

  #expect(pasteboard.string(forType: .fileURL) == artifact.absoluteString)
  #expect(pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.gif.identifier)) == nil)
}

@Test @MainActor func clipboardFileURLPreparationFailureDoesNotClearPasteboard() throws {
  let pasteboard = PasteboardSpy()
  let item = PasteboardItemStub()
  item.setStringResult = false
  let delivery = ArtifactDelivery(
    pasteboardWriter: pasteboard,
    makePasteboardItem: { item }
  )

  #expect(throws: ArtifactDeliveryError.couldNotPrepareClipboardFileURL) {
    try delivery.copyToClipboard(artifact: URL(fileURLWithPath: "/tmp/Capture.mp4"), format: .mp4)
  }
  #expect(item.setDataCallCount == 0)
  #expect(pasteboard.clearContentsCallCount == 0)
  #expect(pasteboard.writtenObjects.isEmpty)
}

@Test @MainActor func clipboardGIFPreparationFailureDoesNotClearPasteboard() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let artifact = root.appendingPathComponent("Capture.gif")
  try Data([0x47, 0x49, 0x46]).write(to: artifact)
  let pasteboard = PasteboardSpy()
  let item = PasteboardItemStub()
  item.setDataResult = false
  let delivery = ArtifactDelivery(
    pasteboardWriter: pasteboard,
    makePasteboardItem: { item }
  )

  #expect(throws: ArtifactDeliveryError.couldNotPrepareClipboardGIFData) {
    try delivery.copyToClipboard(artifact: artifact, format: .gif)
  }
  #expect(item.setStringCallCount == 1)
  #expect(item.setDataCallCount == 1)
  #expect(pasteboard.clearContentsCallCount == 0)
  #expect(pasteboard.writtenObjects.isEmpty)
}

@Test @MainActor func clipboardWriteFailureThrowsAfterAttemptingPublication() throws {
  let pasteboard = PasteboardSpy()
  pasteboard.writeResult = false
  let item = PasteboardItemStub()
  let delivery = ArtifactDelivery(
    pasteboardWriter: pasteboard,
    makePasteboardItem: { item }
  )

  #expect(throws: ArtifactDeliveryError.couldNotWriteToClipboard) {
    try delivery.copyToClipboard(artifact: URL(fileURLWithPath: "/tmp/Capture.mp4"), format: .mp4)
  }
  #expect(pasteboard.clearContentsCallCount == 1)
  #expect(pasteboard.writtenObjects.count == 1)
}

@Test @MainActor func folderDeliveryCopiesWithFriendlyName() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let destination = root.appendingPathComponent("Exports", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let artifact = root.appendingPathComponent("source.mp4")
  try Data([1, 2, 3]).write(to: artifact)
  var settings = CaptureSettings(format: .mp4, destination: .folder)
  settings.folderPath = destination.path
  let delivery = ArtifactDelivery()

  let delivered = try delivery.deliver(artifact: artifact, format: .mp4, settings: settings)

  #expect(delivered.deletingLastPathComponent() == destination)
  #expect(FileManager.default.fileExists(atPath: delivered.path))
}

@Test @MainActor func folderDeliveryPropagatesDestinationCreationFailure() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let artifact = root.appendingPathComponent("source.mp4")
  let occupiedDestination = root.appendingPathComponent("Exports")
  try Data([1, 2, 3]).write(to: artifact)
  try Data([4, 5, 6]).write(to: occupiedDestination)
  var settings = CaptureSettings(format: .mp4, destination: .folder)
  settings.folderPath = occupiedDestination.path
  let delivery = ArtifactDelivery()

  #expect(throws: (any Error).self) {
    try delivery.deliver(artifact: artifact, format: .mp4, settings: settings)
  }
  #expect(try Data(contentsOf: artifact) == Data([1, 2, 3]))
  #expect(try Data(contentsOf: occupiedDestination) == Data([4, 5, 6]))
}

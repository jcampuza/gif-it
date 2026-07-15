import AppKit
import GifItCore
import SwiftUI

struct MenuBarContent: View {
  @ObservedObject var model: AppModel
  let requestQuit: () -> Void
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button("Capture Window…") {
      model.requestCapture()
    }
    .keyboardShortcut("g", modifiers: [.control, .option])
    .disabled(!model.canCapture)

    Button("Stop Recording") {
      Task { await model.stopRecording() }
    }
    .disabled(!model.canStop)

    Divider()

    if case .converting(let progress) = model.phase {
      Text("Converting GIF… \(Int(progress * 100))%")
    } else {
      Text(model.statusMessage)
    }

    Button("Save Last Recording As…") {
      model.saveLastRecordingAs()
    }
    .disabled(!model.hasLastArtifact)

    Divider()

    Button("Settings…") {
      NSApp.activate(ignoringOtherApps: true)
      openSettings()
    }
    .keyboardShortcut(",")

    Button("Quit Gif It") {
      requestQuit()
    }
    .keyboardShortcut("q")
  }
}

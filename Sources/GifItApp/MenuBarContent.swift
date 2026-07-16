import AppKit
import GifItCore
import SwiftUI

struct MenuBarContent: View {
  @ObservedObject var model: AppModel
  let requestQuit: () -> Void
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    if let keyEquivalent = model.settings.shortcut.menuKeyEquivalent {
      Button("Capture Window…") {
        model.requestCapture()
      }
      .keyboardShortcut(
        keyEquivalent,
        modifiers: model.settings.shortcut.menuEventModifiers
      )
      .disabled(!model.canCapture)
    } else {
      Button("Capture Window…  \(model.settings.shortcut.displayName)") {
        model.requestCapture()
      }
      .disabled(!model.canCapture)
    }

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

private extension GlobalShortcut {
  var menuKeyEquivalent: KeyEquivalent? {
    switch keyLabel {
    case "↩": .return
    case "⇥": .tab
    case "Space": .space
    case "⌫": .delete
    case "←": .leftArrow
    case "→": .rightArrow
    case "↓": .downArrow
    case "↑": .upArrow
    default:
      keyLabel.count == 1
        ? keyLabel.lowercased().first.map { KeyEquivalent($0) }
        : nil
    }
  }

  var menuEventModifiers: EventModifiers {
    var value: EventModifiers = []
    if modifiers.contains(.command) { value.insert(.command) }
    if modifiers.contains(.option) { value.insert(.option) }
    if modifiers.contains(.control) { value.insert(.control) }
    if modifiers.contains(.shift) { value.insert(.shift) }
    return value
  }
}

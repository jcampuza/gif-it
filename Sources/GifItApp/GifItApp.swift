import AppKit
import SwiftUI

@MainActor
final class GifItApplicationDelegate: NSObject, NSApplicationDelegate {
  weak var model: AppModel?

  private var preparationTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var didReplyToTermination = false

  func requestTermination() {
    NSApp.terminate(nil)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !didReplyToTermination else { return .terminateNow }
    guard preparationTask == nil else { return .terminateLater }
    guard let model else { return .terminateNow }

    preparationTask = Task { @MainActor [weak self, weak model] in
      await model?.prepareForTermination()
      self?.finishTermination()
    }
    timeoutTask = Task { @MainActor [weak self, weak model] in
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled, let self else { return }
      await model?.forceTerminationCleanup()
      self.finishTermination()
    }
    return .terminateLater
  }

  private func finishTermination() {
    guard !didReplyToTermination else { return }
    didReplyToTermination = true
    preparationTask?.cancel()
    timeoutTask?.cancel()
    preparationTask = nil
    timeoutTask = nil
    NSApp.reply(toApplicationShouldTerminate: true)
  }
}

@main
struct GifItApp: App {
  @NSApplicationDelegateAdaptor(GifItApplicationDelegate.self) private var appDelegate
  @StateObject private var model: AppModel

  init() {
    let model = AppModel()
    _model = StateObject(wrappedValue: model)
    appDelegate.model = model
    NSApplication.shared.setActivationPolicy(.accessory)
  }

  var body: some Scene {
    MenuBarExtra("Gif It", systemImage: model.menuBarSymbol) {
      MenuBarContent(model: model, requestQuit: appDelegate.requestTermination)
    }

    Settings {
      SettingsView(model: model)
    }
  }
}

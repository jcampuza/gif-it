import AppKit
import SwiftUI

@MainActor
public final class RecordingPanelController {
  private var panel: NSPanel?

  public init() {}

  public func show(startedAt: Date, stop: @escaping () -> Void) {
    hide()
    let content = RecordingIndicatorView(startedAt: startedAt, stop: stop)
    let hosting = NSHostingView(rootView: content)
    let size = NSSize(width: 176, height: 46)
    hosting.frame = NSRect(origin: .zero, size: size)

    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.contentView = hosting
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = true

    let screen = NSScreen.main ?? NSScreen.screens.first
    if let frame = screen?.visibleFrame {
      panel.setFrameOrigin(
        NSPoint(
          x: frame.midX - size.width / 2,
          y: frame.maxY - size.height - 12
        ))
    }
    panel.orderFrontRegardless()
    self.panel = panel
  }

  public func hide() {
    panel?.orderOut(nil)
    panel = nil
  }
}

private struct RecordingIndicatorView: View {
  let startedAt: Date
  let stop: () -> Void

  var body: some View {
    TimelineView(.periodic(from: startedAt, by: 1)) { context in
      HStack(spacing: 10) {
        Circle()
          .fill(.red)
          .frame(width: 10, height: 10)
        Text(elapsed(at: context.date))
          .monospacedDigit()
          .font(.system(size: 13, weight: .semibold))
        Button("Stop", action: stop)
          .buttonStyle(.borderedProminent)
          .tint(.red)
          .controlSize(.small)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.regularMaterial, in: Capsule())
      .overlay(Capsule().stroke(.white.opacity(0.14)))
    }
  }

  private func elapsed(at date: Date) -> String {
    let seconds = min(30, max(0, Int(date.timeIntervalSince(startedAt))))
    return String(format: "0:%02d", seconds)
  }
}

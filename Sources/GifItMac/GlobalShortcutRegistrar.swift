import Carbon.HIToolbox
import Foundation
import GifItCore

public enum GlobalShortcutError: LocalizedError {
  case missingModifier
  case registrationFailed(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .missingModifier:
      "A global shortcut must include at least one modifier key."
    case .registrationFailed:
      "That shortcut is already in use. Choose another shortcut."
    }
  }
}

@MainActor
public final class GlobalShortcutRegistrar {
  private static let signature: OSType = 0x4749_4649  // GIFI

  private var eventHandler: EventHandlerRef?
  private var hotKey: EventHotKeyRef?
  private var nextID: UInt32 = 1
  private var action: (() -> Void)?

  public init() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return noErr }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == GlobalShortcutRegistrar.signature else {
          return status
        }
        let registrar = Unmanaged<GlobalShortcutRegistrar>.fromOpaque(userData)
          .takeUnretainedValue()
        MainActor.assumeIsolated {
          registrar.action?()
        }
        return noErr
      },
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
  }

  public func register(shortcut: GlobalShortcut, action: @escaping () -> Void) throws {
    guard !shortcut.modifiers.isEmpty else { throw GlobalShortcutError.missingModifier }

    var candidate: EventHotKeyRef?
    let identifier = EventHotKeyID(signature: Self.signature, id: nextID)
    nextID &+= 1
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      carbonModifiers(shortcut.modifiers),
      identifier,
      GetApplicationEventTarget(),
      0,
      &candidate
    )
    guard status == noErr, let candidate else {
      throw GlobalShortcutError.registrationFailed(status)
    }

    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = candidate
    self.action = action
  }

  private func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
    var value: UInt32 = 0
    if modifiers.contains(.command) { value |= UInt32(cmdKey) }
    if modifiers.contains(.option) { value |= UInt32(optionKey) }
    if modifiers.contains(.control) { value |= UInt32(controlKey) }
    if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
    return value
  }
}

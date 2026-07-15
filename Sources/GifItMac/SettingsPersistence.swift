import Foundation
import GifItCore

public struct SettingsPersistence {
  private let defaults: UserDefaults
  private let key = "captureSettings.v1"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func load() -> CaptureSettings {
    guard
      let data = defaults.data(forKey: key),
      let settings = try? JSONDecoder().decode(CaptureSettings.self, from: data)
    else {
      return CaptureSettings()
    }
    return settings
  }

  public func save(_ settings: CaptureSettings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: key)
  }
}

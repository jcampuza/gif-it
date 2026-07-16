import Foundation
import GifItCore
import Testing

@Test func defaultSettingsMatchPrimaryWorkflow() {
  let settings = CaptureSettings()
  #expect(settings.format == .gif)
  #expect(settings.gifQuality == .standard)
  #expect(settings.destination == .clipboard)
  #expect(settings.includesCursor)
  #expect(settings.showsMouseClicks)
  #expect(settings.shortcut.displayName == "⌃⌥G")
}

@Test func gifQualityPresetsTradeSizeForDetail() {
  #expect(GIFQuality.low.framesPerSecond < GIFQuality.standard.framesPerSecond)
  #expect(GIFQuality.standard.framesPerSecond < GIFQuality.high.framesPerSecond)
  #expect(GIFQuality.low.maximumPixelDimension < GIFQuality.standard.maximumPixelDimension)
  #expect(GIFQuality.standard.maximumPixelDimension < GIFQuality.high.maximumPixelDimension)
}

@Test func captureSettingsDecodeLegacyDataWithStandardGIFQuality() throws {
  let legacyJSON = #"""
    {
      "format": "gif",
      "destination": "clipboard",
      "includesCursor": true,
      "showsMouseClicks": true,
      "shortcut": {
        "keyCode": 5,
        "keyLabel": "G",
        "modifiers": 6
      }
    }
    """#

  let settings = try JSONDecoder().decode(
    CaptureSettings.self,
    from: Data(legacyJSON.utf8)
  )

  #expect(settings.gifQuality == .standard)
}

@Test func artifactNamesAreStableAndAvoidCollisions() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let date = calendar.date(
    from: DateComponents(
      year: 2026,
      month: 7,
      day: 14,
      hour: 15,
      minute: 42,
      second: 17
    ))!
  let directory = URL(fileURLWithPath: "/tmp")
  let occupied = Set(["Gif It 2026-07-14 at 15.42.17.gif"])

  let url = ArtifactNaming.uniqueURL(
    in: directory,
    format: .gif,
    date: date,
    calendar: calendar
  ) {
    occupied.contains($0)
  }

  #expect(url.lastPathComponent == "Gif It 2026-07-14 at 15.42.17 2.gif")
}

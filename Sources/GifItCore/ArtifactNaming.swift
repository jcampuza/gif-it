import Foundation

public enum ArtifactNaming {
  public static func baseName(for date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: date
    )
    return String(
      format: "Gif It %04d-%02d-%02d at %02d.%02d.%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0,
      components.hour ?? 0,
      components.minute ?? 0,
      components.second ?? 0
    )
  }

  public static func uniqueURL(
    in directory: URL,
    format: CaptureFormat,
    date: Date = Date(),
    calendar: Calendar = .current,
    fileExists: (String) -> Bool
  ) -> URL {
    let base = baseName(for: date, calendar: calendar)
    var candidate = "\(base).\(format.fileExtension)"
    var suffix = 2
    while fileExists(candidate) {
      candidate = "\(base) \(suffix).\(format.fileExtension)"
      suffix += 1
    }
    return directory.appendingPathComponent(candidate)
  }
}

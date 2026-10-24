internal import Foundation

/// The target's position for plate solves, from the lights' own pointing (`targetQueryFor` +
/// `skycat.ParseRA`/`ParseDec`).
///
/// `"ra,dec"` in decimal degrees, five decimals. A lookup by object name is `SkyCatalogue`'s
/// (card 0129), offered next to the header's position, never set in its place (R2).
package enum TargetCoordinates {
  /// The first light carrying a parseable OBJCTRA/OBJCTDEC pair; nil when none does.
  package static func from(_ inventory: Inventory) -> String? {
    for set in inventory.sets where set.key.type == .light {
      for frame in set.frames {
        if let ra = rightAscension(frame.objectRA), let dec = declination(frame.objectDec) {
          return String(format: "%.5f,%.5f", ra, dec)
        }
      }
    }
    return nil
  }

  /// Hours ("00 42 44.3", "00:42:44") to degrees; a single number is already degrees.
  package static func rightAscension(_ text: String) -> Double? {
    guard let (parts, sexagesimal) = fields(text) else { return nil }
    return sexagesimal ? (parts[0] + parts[1] / 60 + parts[2] / 3600) * 15 : parts[0]
  }

  /// Degrees ("+41 16 09", "-05:23:00"); the sign of the text applies to the whole value.
  package static func declination(_ text: String) -> Double? {
    guard let (parts, sexagesimal) = fields(text) else { return nil }
    guard sexagesimal else { return parts[0] }
    let magnitude = abs(parts[0]) + parts[1] / 60 + parts[2] / 3600
    return text.trimmingCharacters(in: .whitespaces).hasPrefix("-") ? -magnitude : magnitude
  }

  /// One number (decimal) or two to three (sexagesimal), space or colon separated.
  static func fields(_ text: String) -> ([Double], Bool)? {
    let tokens = text.split { $0 == " " || $0 == ":" }.map(String.init)
    let numbers = tokens.compactMap(Double.init)
    guard (1...3).contains(tokens.count), numbers.count == tokens.count else { return nil }
    return (numbers + Array(repeating: 0, count: 3 - numbers.count), tokens.count > 1)
  }
}

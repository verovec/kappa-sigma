internal import Foundation
internal import ImageKit

/// Header cards read the way the legacy `fits.Header` accessors read them: values trimmed, `D`
/// exponents accepted, integers falling back to a truncated float.
struct LegacyCards {
  let header: FITSHeader

  func string(_ key: String) -> String? {
    header.string(key)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func double(_ key: String) -> Double? {
    string(key).flatMap {
      LegacyNumber.finite($0.replacingOccurrences(of: "D", with: "E", options: .caseInsensitive))
    }
  }

  func int(_ key: String) -> Int? {
    guard let text = string(key) else { return nil }
    if let value = Int(text) { return value }
    return double(key).flatMap(LegacyNumber.truncated)
  }

  /// EXPTIME, else EXPOSURE, else ASICAP's EXPOINUS in microseconds.
  var exposureSeconds: Double? {
    double("EXPTIME") ?? double("EXPOSURE") ?? double("EXPOINUS").map { $0 / 1e6 }
  }
}

internal import Foundation

/// Which clip filter a ONE-SHOT-COLOUR session was shot through (`internal/filters/filterset.go`).
///
/// A colour camera has no wheel and no FILTER card; only the pixels say whether a night was
/// broadband or dual-band, and the two must never be stacked or flat-matched together.
package enum FilterSet: String, CaseIterable, Codable, Sendable {
  /// Not measured, or the signals disagreed: every consumer keeps today's behaviour.
  case unknown
  /// Unfiltered (or UV/IR-cut): full continuum, bright sky.
  case broadband
  /// A dual-narrowband clip (Ha + OIII): two narrow windows, near-black sky.
  case dualband

  /// Whether the verdict carries information (neither empty nor unknown).
  package var isKnown: Bool { self != .unknown }

  /// Validates a wire value; the empty string is `unknown`.
  package init(parsing raw: String) throws {
    let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
    guard let set = value.isEmpty ? .unknown : Self(rawValue: value) else {
      throw InspectError.unknownFilterSet(raw)
    }
    self = set
  }
}

/// A verdict keys a JSON object by its wire value (`{"dualband": …}`), not a list of pairs.
extension FilterSet: CodingKeyRepresentable {}

internal import Foundation

/// Which clip filter a ONE-SHOT-COLOUR session was shot through (`internal/filters/filterset.go`).
///
/// A colour camera has no wheel and no FILTER card; the pixels say whether a night was broadband
/// or dual-band (the user asserts the other clips), and two clips must never be stacked or
/// flat-matched together. The `rawValue` is on the wire: lane names, `lane_knobs`, overrides.
package enum FilterSet: String, CaseIterable, Codable, Sendable {
  /// Not measured, or the signals disagreed: every consumer keeps today's behaviour.
  case unknown
  /// Unfiltered (or UV/IR-cut): full continuum, bright sky.
  case broadband
  /// A dual-narrowband clip (Hα + OIII): two narrow windows, near-black sky.
  case dualband
  /// A dual-narrowband clip passing [SII] and [OIII] instead.
  case dualbandSII = "dualband-sii"
  /// A tri- or quad-band clip: Hα (with [SII]) on the red plane, [OIII] (with Hβ) on green/blue.
  case multiband

  /// Whether the verdict carries information (neither empty nor unknown).
  package var isKnown: Bool { self != .unknown }

  /// Validates a wire value; the empty string is `unknown`.
  package init(parsing raw: String) throws {
    let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
    guard let set = value.isEmpty ? .unknown : Self(rawValue: value) else {
      throw ParseError.unknownFilterSet(raw)
    }
    self = set
  }

  /// A wire value naming no filter set.
  package enum ParseError: Error, Equatable, Sendable {
    case unknownFilterSet(String)
  }

  /// The line each of a one-shot-colour sensor's planes carries: the red one, the green/blue pair.
  package typealias Lines = (red: Filter, greenBlue: Filter)

  /// The emission lines a clip filter's planes carry on a one-shot-colour sensor.
  ///
  /// The red plane and the green/blue pair, one line each (`nil` for broadband or unknown):
  /// what the dual-band split writes as synthetic layers.
  package var lines: Lines? {
    switch self {
    case .unknown, .broadband: nil
    case .dualband, .multiband: (.hydrogenAlpha, .oxygenIII)
    case .dualbandSII: (.sulfurII, .oxygenIII)
    }
  }

  /// Whether each plane also carries a second line the sensor cannot separate (a multi-band
  /// clip: [SII] under Hα, Hβ under [OIII]) — what the run's note says about its layers.
  package var mixesLines: Bool { self == .multiband }
}

/// A verdict keys a JSON object by its wire value (`{"dualband": …}`), not a list of pairs.
extension FilterSet: CodingKeyRepresentable {}

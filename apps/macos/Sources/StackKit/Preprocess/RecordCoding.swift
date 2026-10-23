internal import Foundation

/// The JSON coding of a run's records (`grades.json`, `lanes/<lane>.json`).
///
/// Keys sorted, pretty, and NaN / ±∞ written as strings — real measurements hold them (a frame Siril could not
/// measure) and JSON has no number for them, so a record never fails on the data it keeps.
/// Finite values encode exactly as a plain encoder does.
enum RecordCoding {
  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
      positiveInfinity: positiveInfinity, negativeInfinity: negativeInfinity, nan: nan)
    return encoder
  }

  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: positiveInfinity, negativeInfinity: negativeInfinity, nan: nan)
    return decoder
  }

  private static let (positiveInfinity, negativeInfinity, nan) = ("+inf", "-inf", "nan")
}

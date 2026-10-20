internal import Foundation

/// The `<frame>.txt` capture settings SharpCap/ASICAP write beside each FITS
/// (`internal/inspect/sidecar.go`).
///
/// `EFW Slot` is ground-truth filter identity for mono captures with no FILTER card; `Brightness`
/// is ZWO's offset. Only the keys inspect uses are read.
package struct SharpcapSidecar: Equatable, Sendable {
  package var slot: Int
  /// Canonical filter from `(Alias: L)`; `""` when absent or not a filter name.
  package var slotAlias: String
  package var gain: Int
  package var hasGain: Bool
  package var offset: Int
  package var hasOffset: Bool
  package var exposureMs: Int
  package var tempMilliC: Int
  package var hasTemp: Bool

  /// A value with the given fields, the rest at zero.
  package init(
    slot: Int = 0, slotAlias: String = "", gain: Int = 0, hasGain: Bool = false, offset: Int = 0,
    hasOffset: Bool = false, exposureMs: Int = 0, tempMilliC: Int = 0, hasTemp: Bool = false
  ) {
    self.slot = slot
    self.slotAlias = slotAlias
    self.gain = gain
    self.hasGain = hasGain
    self.offset = offset
    self.hasOffset = hasOffset
    self.exposureMs = exposureMs
    self.tempMilliC = tempMilliC
    self.hasTemp = hasTemp
  }

  /// The sidecar of the frame at `path` (`x.FIT` → `x.FIT.txt`), or `nil` when there is none or
  /// it holds nothing useful.
  package static func read(beside path: String) -> Self? {
    guard let data = FileManager.default.contents(atPath: path + ".txt") else { return nil }
    guard let text = String(bytes: data, encoding: .utf8) else { return nil }
    let sidecar = Self(parsing: text)
    let useful =
      sidecar.slot > 0 || sidecar.hasGain || sidecar.hasOffset || sidecar.exposureMs > 0
      || sidecar.hasTemp
    return useful ? sidecar : nil
  }

  /// Parses the `Key = Value` lines of a sidecar body.
  package init(parsing text: String) {
    self.init()
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      guard let equals = line.firstIndex(of: "=") else { continue }
      let key = Self.trim(line[..<equals]).lowercased()
      read(key: key, value: Self.trim(line[line.index(after: equals)...]))
    }
  }

  private mutating func read(key: String, value: String) {
    switch key {
    case "efw slot":
      slot = Int(value.prefix(while: \.isASCIIDigit)) ?? 0
      if let match = value.firstMatch(of: /\(Alias:\s*([^)]+)\)/),
        let filter = Filter.token(String(match.1))
      {
        slotAlias = filter.rawValue
      }
    case "gain":
      if let value = Int(value) {
        gain = value
        hasGain = true
      }
    // "Auto Exp Target Brightness" does not match: the whole key is compared.
    case "brightness", "offset":
      if let value = Int(value) {
        offset = value
        hasOffset = true
      }
    case "exposure":
      let milliseconds = Self.exposureMs(value)
      if milliseconds > 0 { exposureMs = milliseconds }
    case "temperature":
      var number = value
      if number.hasSuffix("C") || number.hasSuffix("c") { number.removeLast() }
      if let celsius = LegacyNumber.finite(Self.trim(number[...])),
        let milli = LegacyNumber.rounded(celsius, scale: 1000)
      {
        tempMilliC = milli
        hasTemp = true
      }
    default:
      break
    }
  }

  /// `30s`, `1.5s`, `30ms`, `500us` → milliseconds; 0 when unreadable.
  private static func exposureMs(_ raw: String) -> Int {
    let value = raw.lowercased()
    let units: [(suffix: String, scale: Double)] = [("ms", 1), ("us", 0.001), ("s", 1000)]
    guard let unit = units.first(where: { value.hasSuffix($0.suffix) }),
      let number = LegacyNumber.finite(trim(value.dropLast(unit.suffix.count))),
      let milliseconds = LegacyNumber.rounded(number, scale: unit.scale)
    else { return 0 }
    return milliseconds
  }

  private static func trim(_ text: Substring) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

extension Character {
  /// `0`…`9` only (Go's byte test), not every Unicode digit.
  var isASCIIDigit: Bool { isASCII && isNumber }
}

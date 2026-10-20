/// The line-by-line state of a manifest parse.
struct ManifestLines {
  struct Sequence {
    var filters: [String]
    var gain: Int?
    var exposureMs = 0
  }

  var sequences: [Sequence] = []
  var gainByFilter: [String: Int] = [:]
  var exposureByFilter: [String: Int] = [:]
  var globalGain: Int?
  var globalExposureMs = 0
  /// Whether the last line read was understood.
  var recognized = true

  /// Reads one line; returns a temperature in m°C when the line is one.
  mutating func read(_ line: String) -> Int? {
    recognized = true
    let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
    if readArrowExposure(line) { return nil }
    if line.lowercased().hasPrefix("gain"), Self.isGainMap(fields) {
      for (filter, gain) in Self.gainMap(fields.dropFirst()) { gainByFilter[filter] = gain }
      return nil
    }
    if let match = line.wholeMatch(of: /(?i)(-?\d+(?:\.\d+)?)\s*(?:°|º|deg|degc)/),
      let celsius = LegacyNumber.finite(match.1),
      let milli = LegacyNumber.rounded(celsius, scale: 1000)
    {
      return milli
    }
    if let sequence = Self.sequence(fields) {
      sequences.append(sequence)
    } else if Self.isBareGain(fields) {
      globalGain = fields.lazy.compactMap { Int($0) }.first
    } else if let exposure = Self.exposureMs(fields.joined()) {
      globalExposureMs = exposure
    } else {
      recognized = false
    }
    return nil
  }

  /// `L -> 2s`: a per-filter exposure.
  private mutating func readArrowExposure(_ line: String) -> Bool {
    guard let match = line.wholeMatch(of: /(?i)([A-Za-z]+)\s*->\s*(\d*\.?\d+)\s*s/),
      let seconds = LegacyNumber.finite(match.2),
      let milliseconds = LegacyNumber.rounded(seconds, scale: 1000),
      let filters = CaptureManifest.expandFilterWord(String(match.1))
    else { return false }
    for filter in filters { exposureByFilter[filter] = milliseconds }
    return true
  }

  /// A filter-sequence line with an optional inline `N gain` and `Ns`; `nil` without a filter.
  private static func sequence(_ fields: [String]) -> Sequence? {
    var sequence = Sequence(filters: [])
    var index = 0
    while index < fields.count {
      let token = fields[index]
      index += 1
      if let number = Int(token) {
        if index < fields.count, fields[index].lowercased() == "gain" {
          sequence.gain = number
          index += 1
        }
        continue
      }
      if let exposure = exposureMs(token) {
        sequence.exposureMs = exposure
      } else if token.lowercased() != "gain", let filters = CaptureManifest.expandFilterWord(token)
      {
        sequence.filters += filters
      }
    }
    return sequence.filters.isEmpty ? nil : sequence
  }

  /// `120s` → 120 000 ms.
  static func exposureMs(_ token: String) -> Int? {
    guard let match = token.lowercased().wholeMatch(of: /(\d*\.?\d+)s/),
      let seconds = LegacyNumber.finite(match.1)
    else { return nil }
    return LegacyNumber.rounded(seconds, scale: 1000)
  }

  /// `gain L200 RGB250`: every token after `gain` is letters then digits.
  private static func isGainMap(_ fields: [String]) -> Bool {
    fields.count >= 2 && fields.dropFirst().allSatisfy { $0.wholeMatch(of: /[A-Za-z]+\d+/) != nil }
  }

  private static func gainMap(_ tokens: ArraySlice<String>) -> [(String, Int)] {
    tokens.flatMap { token -> [(String, Int)] in
      guard let match = token.wholeMatch(of: /([A-Za-z]+)(\d+)/), let gain = Int(match.2),
        let filters = CaptureManifest.expandFilterWord(String(match.1))
      else { return [] }
      return filters.map { ($0, gain) }
    }
  }

  /// Only a number and the word `gain`, in any order (`300 gain`).
  private static func isBareGain(_ fields: [String]) -> Bool {
    var number = false
    var gain = false
    for field in fields {
      if field.lowercased() == "gain" {
        gain = true
      } else if Int(field) != nil {
        number = true
      } else {
        return false
      }
    }
    return number && gain
  }

  /// Expands the sequences into slots, resolving gain and exposure by precedence.
  func slots() -> [CaptureManifest.Slot] {
    sequences.flatMap { sequence in
      sequence.filters.map { filter in
        var slot = CaptureManifest.Slot(filter: filter)
        if let gain = sequence.gain ?? gainByFilter[filter] ?? globalGain {
          slot.gain = gain
          slot.hasGain = true
        }
        let perFilter = exposureByFilter[filter] ?? 0
        slot.exposureMs =
          sequence.exposureMs > 0
          ? sequence.exposureMs : perFilter > 0 ? perFilter : globalExposureMs
        return slot
      }
    }
  }
}

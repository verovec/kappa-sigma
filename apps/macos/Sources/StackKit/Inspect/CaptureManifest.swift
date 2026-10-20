internal import Foundation

/// A hand-written `info.txt` beside bare-named legacy captures (`internal/inspect/manifest.go`):
/// the capture order, one filter token per sub-run, plus gain, exposure and temperature, e.g.
///
/// `LLL RR GG BB Ha Ha` / `gain L200 RGB250 Ha300`. A metadata FALLBACK: it only fills blanks.
package struct CaptureManifest: Equatable, Sendable {
  /// One capture sub-run, in capture order (`LLL` is three slots).
  package struct Slot: Equatable, Sendable {
    package var filter: String
    package var gain = 0
    package var hasGain = false
    package var exposureMs = 0
  }

  package var slots: [Slot] = []
  package var tempMilliC = 0
  package var hasTemp = false
  /// Lines the parser could not read, quoted.
  package var warnings: [String] = []

  /// Matched longest-first so `Ha`/`OIII` win over single letters; aliases normalized after.
  private static let knownFilters = ["OIII", "O3", "SII", "S2", "Ha", "L", "R", "G", "B", "V"]

  /// The distinct filters in capture order, which a legacy legend maps to slots 1, 2, 3…; the
  /// canonical wheel when the manifest names none.
  package var legend: [String] {
    var seen: Set<String> = []
    let names = slots.map(\.filter).filter { !$0.isEmpty && seen.insert($0).inserted }
    return names.isEmpty ? WheelSlots.defaultLegend : names
  }

  /// A glued filter word split into normalized tokens (`LLLRGBHaHa`); `nil` if any character is
  /// not a filter, so metadata words (`gain`, `moon`) are never mistaken for filters.
  package static func expandFilterWord(_ word: String) -> [String]? {
    var out: [String] = []
    var rest = Substring(word.lowercased())
    while !rest.isEmpty {
      guard let match = knownFilters.first(where: { rest.hasPrefix($0.lowercased()) }) else {
        return nil
      }
      out.append(Filter.normalize(match))
      rest = rest.dropFirst(match.count)
    }
    return out.isEmpty ? nil : out
  }

  /// Parses an `info.txt` body; gain and exposure resolve per inline line, then per filter, then
  /// globally.
  package init(parsing text: String) {
    var lines = ManifestLines()
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      if let celsius = lines.read(line) {
        tempMilliC = celsius
        hasTemp = true
      } else if !lines.recognized {
        warnings.append("ignored line \"\(line)\"")
      }
    }
    slots = lines.slots()
  }
}

/// The line-by-line state of a manifest parse.
private struct ManifestLines {
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
      let celsius = Double(match.1)
    {
      return Int((celsius * 1000).rounded())
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
      let seconds = Double(match.2),
      let filters = CaptureManifest.expandFilterWord(String(match.1))
    else { return false }
    for filter in filters { exposureByFilter[filter] = Int((seconds * 1000).rounded()) }
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
      let seconds = Double(match.1)
    else { return nil }
    return Int((seconds * 1000).rounded())
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

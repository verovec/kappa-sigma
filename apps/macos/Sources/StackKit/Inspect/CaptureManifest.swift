internal import FilterKit
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
  private static let knownFilters = [
    "OIII", "NII", "O3", "SII", "S2", "Ha", "Hb", "L", "R", "G", "B", "V",
  ]

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

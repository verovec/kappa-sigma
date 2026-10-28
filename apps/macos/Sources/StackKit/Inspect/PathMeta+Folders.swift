internal import FilterKit

extension PathMeta {
  /// The frame type the nearest explicitly-typed ancestor folder names, matched per word so
  /// `darks_0gain_300s` types and `darkstar` does not.
  ///
  /// SharpCap's `CapObj` folder (written under both light and calibration trees) names a light only
  /// when no ancestor states a type.
  package static func typeFromFolders(_ path: String) -> FrameType {
    let folders = parentFolders(path)
    if let type = folders.lazy.map(typeFromFolderName).first(where: { $0 != .unknown }) {
      return type
    }
    return folders.contains { words($0).contains("capobj") } ? .light : .unknown
  }

  /// A filter folder: the FIRST word of an ordinary folder (`Ha_300s`, `Red`, `V`), or ANY word of
  /// a calibration folder (`flats_0gain_Ha`).
  ///
  /// Nearest parent wins; `""` when none.
  package static func filterFromFolders(_ path: String) -> String {
    for folder in parentFolders(path) {
      let words = folder.split(whereSeparator: isSeparator).map(String.init)
      guard let first = words.first else { continue }
      if typeFromFolderName(folder).isCalibration {
        if let filter = words.lazy.compactMap(Filter.token).first { return filter.rawValue }
        continue
      }
      // A filter word then a bare number is a catalogue designation (`Hb 5`, `Hb_12`: Hubble's
      // planetary nebulae, card 0141), not a filter folder; `Ha_300s` keeps its unit.
      if words.count > 1, words[1].allSatisfy(\.isASCIIDigit) { continue }
      if let filter = Filter.token(first) { return filter.rawValue }
    }
    return ""
  }

  /// The gain a parent folder encodes (`darks_0gain_300s` → 0, `offset_-15_250gain` → 250); 0.
  package static func gainFromFolders(_ path: String) -> Int {
    parentFolders(path).lazy.compactMap { gain(inName: $0.lowercased()) }.first ?? 0
  }

  /// A gain read per word, in three forms: `0gain` (suffix, wins first), `gain300` and `gain 300`.
  static func gain(inName low: String) -> Int? {
    let words = low.split(whereSeparator: isSeparator).map(String.init)
    for (index, word) in words.enumerated() {
      if let match = word.firstMatch(of: /(\d+)gain/), let gain = Int(match.1) { return gain }
      if let match = word.firstMatch(of: /(?i)gain[-_]?(\d+)/), let gain = Int(match.1) {
        return gain
      }
      if word.lowercased() == "gain", index + 1 < words.count, let gain = Int(words[index + 1]) {
        return gain
      }
    }
    return nil
  }

  private static func typeFromFolderName(_ folder: String) -> FrameType {
    let set = words(folder)
    let dark = !set.isDisjoint(with: ["dark", "darks"])
    let flat = !set.isDisjoint(with: ["flat", "flats", "flatfield", "flatfields"])
    let darkFlat = !set.isDisjoint(with: ["darkflat", "darkflats", "flatdark", "flatdarks"])
    if darkFlat || (dark && flat) { return .darkFlat }
    if flat { return .flat }
    if !set.isDisjoint(with: ["bias", "biases", "offset", "offsets", "zero"]) { return .bias }
    if dark { return .dark }
    if !set.isDisjoint(with: ["light", "lights", "science", "object"]) { return .light }
    return .unknown
  }

  /// Lowercased words of a name, split on `_ - . space`.
  static func words(_ name: String) -> Set<String> {
    Set(name.lowercased().split(whereSeparator: isSeparator).map(String.init))
  }

  static func isSeparator(_ character: Character) -> Bool {
    character == "_" || character == "-" || character == "." || character == " "
  }

  /// The last path component.
  static func baseName(_ path: String) -> String {
    path.split(separator: "/").last.map(String.init) ?? path
  }

  /// Ancestor folder names, nearest first, at most six (a far match must not beat a near one).
  static func parentFolders(_ path: String) -> [String] {
    Array(path.split(separator: "/").dropLast().reversed().prefix(6).map(String.init))
  }
}

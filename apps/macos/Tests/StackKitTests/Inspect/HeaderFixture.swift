import Foundation
import StackKit

/// The pixel-free half of a synthetic oracle case's `in/` folder: every FITS file's relative path
/// and its 80-character header cards (`Fixtures/inspect/<case>.headers.json`). Inspect reads only
/// headers for these all-labeled mono cases, so frames rebuilt from it with blank data classify
/// exactly like the recorded ones. Re-record: `RECORD=1 just test-live --filter LiveInventoryOracle`.
struct HeaderFixture: Codable, Equatable {
  struct File: Codable, Equatable {
    var path: String
    var cards: [String]
  }

  var files: [File]

  static func url(_ name: String) -> URL? {
    Bundle.module.url(forResource: "\(name).headers", withExtension: "json", subdirectory: "Fixtures/inspect")
  }

  /// Where `RECORD=1` writes: the source tree, next to this file.
  static func sourceURL(_ name: String, file: String = #filePath) -> URL {
    URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/inspect/\(name).headers.json")
  }

  static func load(_ name: String) throws -> Self {
    let url = try url(name).unwrapped("Fixtures/inspect/\(name).headers.json missing")
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }

  /// Reads the headers of every FITS file under `root`, in walk order.
  static func read(root: URL) throws -> Self {
    let paths = try FileManager.default.subpathsOfDirectory(atPath: root.path)
      .filter { ["fits", "fit", "fts"].contains(($0 as NSString).pathExtension.lowercased()) }
      .sorted()
    return Self(
      files: try paths.map { path in
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        var cards: [String] = []
        var offset = 0
        while offset + 80 <= data.count {
          let card = String(decoding: data[offset..<offset + 80], as: UTF8.self)
          offset += 80
          if card.hasPrefix("END ") || card == "END".padding(toLength: 80, withPad: " ", startingAt: 0) { break }
          cards.append(card)
        }
        return File(path: path, cards: cards)
      })
  }

  func write(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (encoder.encode(self) + Data("\n".utf8)).write(to: url)
  }

  /// Rebuilds the frames under `root`: the recorded cards, a zero-filled data unit of the size
  /// they declare.
  func materialize(under root: URL) throws {
    for file in files {
      let url = root.appendingPathComponent(file.path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      var text = file.cards.joined() + "END".padding(toLength: 80, withPad: " ", startingAt: 0)
      while text.utf8.count % 2880 != 0 { text += " " }
      var size = abs(Self.value(file.cards, "BITPIX")) / 8
      for axis in 1...max(Self.value(file.cards, "NAXIS"), 1) { size *= Self.value(file.cards, "NAXIS\(axis)") }
      let padded = (size + 2879) / 2880 * 2880
      try (Data(text.utf8) + Data(count: padded)).write(to: url)
    }
  }

  private static func value(_ cards: [String], _ key: String) -> Int {
    let card = cards.first { $0.prefix(8).trimmingCharacters(in: .whitespaces) == key } ?? ""
    let raw = card.dropFirst(10).split(separator: "/").first ?? ""
    return Int(raw.trimmingCharacters(in: .whitespaces)) ?? 0
  }
}

extension Optional {
  func unwrapped(_ message: String) throws -> Wrapped {
    guard let self else { throw FixtureMissing(message: message) }
    return self
  }
}

struct FixtureMissing: Error, CustomStringConvertible {
  let message: String
  var description: String { message }
}

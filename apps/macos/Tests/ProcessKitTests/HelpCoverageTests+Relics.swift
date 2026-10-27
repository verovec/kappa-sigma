import Foundation
import HelpKit
import StringCatalog
import TestSupport
import Testing

/// Dev relics in user-facing text (card 0132): no help entry, profile why or title, suggestion
/// reason or app string names a development run, the PO, a legacy tool, the PO's camera or a
/// validation date — a value's reason is physical, an example is an object name.
extension HelpCoverageTests {
  /// A pattern no user-facing text may carry, as a regex: stems where a word inflects (« v9 »,
  /// « validé·e·s »), both initials where a sentence may start with it, case-sensitive where the
  /// lowercase word is common (« po », the parameter id `starDesat`).
  struct Relic: CustomTestStringConvertible, Sendable {
    let name: String
    let pattern: String
    var testDescription: String { name }

    init(_ name: String, _ pattern: String) {
      self.name = name
      self.pattern = pattern
    }
  }

  static let relics = [
    Relic("v9", #"\bv9"#), Relic("the PO", #"\b[Tt]he PO\b"#), Relic("PO's", #"\bPO's"#),
    Relic("du PO", #"\b[Dd]u PO\b"#), Relic("le PO", #"\b[Ll]e PO\b"#),
    Relic("legacy", #"(?i)\blegacy\b"#), Relic("ancien moteur", #"(?i)\bancien moteur\b"#),
    Relic("anciens runs", #"(?i)\banciens runs\b"#),
    Relic("réglage historique", #"(?i)\bréglage historique\b"#),
    Relic("astrocomp", #"(?i)\bastrocomp\b"#), Relic("hdrcomp", #"(?i)\bhdrcomp\b"#),
    Relic("stardesat", #"\bstardesat\b"#), Relic("run #", #"(?i)\brun #"#),
    Relic("E18", #"\bE18\b"#), Relic("validated", #"(?i)\bvalidated\b"#),
    Relic("validé", #"(?i)\bvalidée?s?\b"#), Relic("HaPlus", #"(?i)\bHaPlus\b"#),
    Relic("IMX571", #"(?i)\bIMX571\b"#), Relic("ASI2600", #"(?i)\bASI2600\b"#),
    Relic("reference runs", #"(?i)\breference runs?\b"#),
    Relic("runs de référence", #"(?i)\bruns? de référence\b"#),
    Relic("date", #"\b(\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}(/\d{2,4})?)\b"#),
  ]

  /// Every user-facing text, by source: the locale folders' help JSON and cards, profile whys
  /// and titles, every value of every shipped string catalog (plural variants included). Read
  /// once; a load failure is reported as itself.
  static let userTexts = Result { try readUserTexts() }

  @Test("no user-facing text carries a dev relic", arguments: relics)
  func testNoDevRelicsInUserText(relic: Relic) throws {
    let texts = try Self.userTexts.get()
    try #require(texts.count > 3, "help, profiles and catalogs must all load")
    let pattern = try Regex(relic.pattern)
    for (source, lines) in texts {
      let hits = lines.filter { $0.contains(pattern) }
      #expect(hits.isEmpty, "\(source) carries « \(relic.name) »: \(hits.prefix(2))")
    }
  }

  private static func readUserTexts() throws -> [(source: String, lines: [String])] {
    let root = URL(fileURLWithPath: try ModuleBoundary.packageRoot(from: #filePath))
    let sources = root.appendingPathComponent("Sources")
    var texts: [(String, [String])] = []
    for locale in HelpIndex.locales {
      let help = sources.appendingPathComponent("HelpKit/Help/\(locale)")
      let files = try files(under: help, extensions: ["json", "md"])
      guard !files.isEmpty else { throw CorpusError.emptyFolder(help.path) }
      for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        texts.append(
          (
            file.path.replacingOccurrences(of: sources.path, with: ""),
            text.split(separator: "\n").map(String.init)
          ))
      }
    }
    let profiles = sources.appendingPathComponent("ProcessKit/Profiles")
    let profileFiles = try files(under: profiles, extensions: ["json"])
    guard !profileFiles.isEmpty else { throw CorpusError.emptyFolder(profiles.path) }
    for file in profileFiles {
      texts.append((file.lastPathComponent, try localizedTexts(in: file)))
    }
    for target in ShippedCatalogs.targets {
      let catalog = try StringCatalog(
        contentsOf: sources.appendingPathComponent("\(target)/Localizable.xcstrings"))
      texts.append((target + " catalog", values(of: catalog)))
    }
    return texts
  }

  /// A corpus folder that holds nothing: the guard would pass for want of text.
  enum CorpusError: Error {
    case emptyFolder(String)
  }

  private static func files(under folder: URL, extensions: Set<String>) throws -> [URL] {
    let listed = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    return (listed?.allObjects as? [URL] ?? [])
      .filter { extensions.contains($0.pathExtension) }
      .sorted { $0.path < $1.path }
  }

  /// The texts a profile shows: every string under a `why` or `title` key, both locales.
  private static func localizedTexts(in file: URL) throws -> [String] {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
    var found: [String] = []
    func walk(_ node: Any, shown: Bool) {
      if let dictionary = node as? [String: Any] {
        for (key, value) in dictionary {
          walk(value, shown: shown || key == "why" || key == "title")
        }
      } else if let array = node as? [Any] {
        for value in array { walk(value, shown: shown) }
      } else if shown, let text = node as? String {
        found.append(text)
      }
    }
    walk(json, shown: false)
    return found
  }

  /// Every localized value of `catalog`, plural variants included.
  private static func values(of catalog: StringCatalog) -> [String] {
    catalog.strings.values.flatMap { entry in
      (entry.localizations ?? [:]).values.flatMap { localization -> [String] in
        [localization.stringUnit?.value].compactMap(\.self)
          + (localization.variations?.plural ?? [:]).values.map(\.stringUnit.value)
      }
    }
  }
}

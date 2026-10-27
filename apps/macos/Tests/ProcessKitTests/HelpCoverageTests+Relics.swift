import Foundation
import HelpKit
import StringCatalog
import TestSupport
import Testing

/// Dev relics in user-facing text (card 0132): no help entry, profile why or title, suggestion
/// reason or app string names a development run, the PO, a legacy tool, the PO's camera or a
/// validation date — a value's reason is physical, an example is an object name.
extension HelpCoverageTests {
  /// A pattern no user-facing text may carry, as a regex: a bare substring where the token is
  /// unique (« v9 », « HaPlus », a camera), a whole word where the lowercase word is common
  /// (« PO », the parameter id `starDesat`), a stem where a word inflects (« validé·e·s »); a
  /// date is a day/month pair in range or ISO, so a ratio like 2/3 or 50/50 is not one.
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
    Relic("v9", #"(?i)(^|[^a-z0-9])v9"#), Relic("PO", #"\bPO\b"#),
    Relic("legacy", #"(?i)\blegacy\b"#),
    Relic("ancien moteur", #"(?i)\bancien moteur\b"#),
    Relic("anciens runs", #"(?i)\banciens runs\b"#),
    Relic("réglage historique", #"(?i)\bréglage historique\b"#),
    Relic("astrocomp", #"(?i)\bastrocomp\b"#), Relic("hdrcomp", #"(?i)\bhdrcomp\b"#),
    Relic("stardesat", #"\b[Ss]tardesat\b"#), Relic("run #", #"(?i)\brun #"#),
    Relic("E18", #"\bE18\b"#), Relic("validated", #"(?i)\bvalidated\b"#),
    Relic("validé", #"(?i)\bvalidée?s?\b"#), Relic("HaPlus", #"(?i)haplus"#),
    Relic("IMX571", #"(?i)imx571"#), Relic("ASI2600", #"(?i)asi2600"#),
    Relic("reference runs", #"(?i)\breference runs?\b"#),
    Relic("runs de référence", #"(?i)\bruns? de référence\b"#),
    Relic("date", #"\b(\d{4}-\d{2}-\d{2}|(0[1-9]|[12]\d|3[01])/(0[1-9]|1[0-2])(/\d{2,4})?)\b"#),
  ]

  /// Every user-facing text, by source: the locale folders' help JSON and cards, profile whys
  /// and titles, every value of every shipped string catalog (plural variants included). Read
  /// once; a load failure is reported as itself.
  static let userTexts = Result { try readUserTexts() }

  /// Where a text comes from; every kind must bring text or the guard would pass for want of it.
  enum Kind: CaseIterable { case helpEN, helpFR, profile, catalog }

  @Test("no user-facing text carries a dev relic", arguments: relics)
  func testNoDevRelicsInUserText(relic: Relic) throws {
    let pattern = try Regex(relic.pattern)
    for (source, lines) in try Self.userTexts.get() {
      let hits = lines.filter { $0.contains(pattern) }
      #expect(hits.isEmpty, "\(source) carries « \(relic.name) »: \(hits.prefix(2))")
    }
  }

  private static func readUserTexts() throws -> [(source: String, lines: [String])] {
    let root = URL(fileURLWithPath: try ModuleBoundary.packageRoot(from: #filePath))
    let sources = root.appendingPathComponent("Sources")
    var texts: [(kind: Kind, source: String, lines: [String])] = []
    for locale in HelpIndex.locales {
      let help = sources.appendingPathComponent("HelpKit/Help/\(locale)")
      for file in try files(under: help, extensions: ["json", "md"]) {
        let text = try String(contentsOf: file, encoding: .utf8)
        texts.append(
          (
            locale == "fr" ? .helpFR : .helpEN,
            file.path.replacingOccurrences(of: sources.path, with: ""),
            text.split(separator: "\n").map(String.init)
          ))
      }
    }
    let profiles = sources.appendingPathComponent("ProcessKit/Profiles")
    for file in try files(under: profiles, extensions: ["json"]) {
      texts.append((.profile, file.lastPathComponent, try localizedTexts(in: file)))
    }
    for target in ShippedCatalogs.targets {
      let catalog = try StringCatalog(
        contentsOf: sources.appendingPathComponent("\(target)/Localizable.xcstrings"))
      texts.append((.catalog, target + " catalog", values(of: catalog)))
    }
    for kind in Kind.allCases where !texts.contains(where: { $0.kind == kind && !$0.lines.isEmpty })
    {
      throw CorpusError.emptyKind(kind)
    }
    return texts.map { (source: $0.source, lines: $0.lines) }
  }

  /// A source kind that brought no text at all.
  enum CorpusError: Error {
    case emptyKind(Kind)
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

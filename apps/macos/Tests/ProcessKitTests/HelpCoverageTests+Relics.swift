import Foundation
import StringCatalog
import TestSupport
import Testing

/// Dev relics in user-facing text (card 0132): no help entry, profile why or title, suggestion
/// reason or app string names a development run, the PO, a legacy tool or a validation date — a
/// value's reason is physical, an example is an object name.
extension HelpCoverageTests {
  /// A fragment no user-facing text may carry: matched on lowercased text, except the PO
  /// fragments (« po » starts too many words) and the tool name `stardesat` (the parameter id
  /// `starDesat` is not a text).
  struct Relic: CustomTestStringConvertible, Sendable {
    let fragment: String
    var caseSensitive = false
    var testDescription: String { fragment }

    func found(in text: String) -> Bool {
      caseSensitive ? text.contains(fragment) : text.lowercased().contains(fragment.lowercased())
    }
  }

  static let relics = [
    Relic(fragment: "v9"), Relic(fragment: "the PO", caseSensitive: true),
    Relic(fragment: "PO's", caseSensitive: true), Relic(fragment: "du PO", caseSensitive: true),
    Relic(fragment: "legacy"), Relic(fragment: "ancien moteur"), Relic(fragment: "anciens runs"),
    Relic(fragment: "réglage historique"), Relic(fragment: "astrocomp"),
    Relic(fragment: "hdrcomp"), Relic(fragment: "stardesat", caseSensitive: true),
    Relic(fragment: "run #"),
    Relic(fragment: "E18", caseSensitive: true), Relic(fragment: "validated"),
    Relic(fragment: "validé"), Relic(fragment: "HaPlus"),
  ]

  /// Every user-facing text, by source: help JSON and cards, profile whys and titles, every
  /// value of every shipped string catalog (plural variants included). Read once.
  static let userTexts: [(source: String, lines: [String])] = (try? readUserTexts()) ?? []

  @Test("no user-facing text carries a dev relic", arguments: relics)
  func testNoDevRelicsInUserText(relic: Relic) throws {
    try #require(!Self.userTexts.isEmpty, "the corpus must load")
    for (source, lines) in Self.userTexts {
      let hits = lines.filter { relic.found(in: $0) }
      #expect(hits.isEmpty, "\(source) carries « \(relic.fragment) »: \(hits.prefix(2))")
    }
  }

  private static func readUserTexts() throws -> [(source: String, lines: [String])] {
    let root = URL(fileURLWithPath: try ModuleBoundary.packageRoot(from: #filePath))
    let sources = root.appendingPathComponent("Sources")
    var texts: [(String, [String])] = []
    let help = sources.appendingPathComponent("HelpKit/Help")
    for file in try files(under: help, extensions: ["json", "md"]) {
      let text = try String(contentsOf: file, encoding: .utf8)
      texts.append(
        (
          file.path.replacingOccurrences(of: sources.path, with: ""),
          text.split(separator: "\n").map(String.init)
        ))
    }
    let profiles = sources.appendingPathComponent("ProcessKit/Profiles")
    for file in try files(under: profiles, extensions: ["json"]) {
      texts.append((file.lastPathComponent, try localizedTexts(in: file)))
    }
    for target in ShippedCatalogs.targets {
      let catalog = try StringCatalog(
        contentsOf: sources.appendingPathComponent("\(target)/Localizable.xcstrings"))
      texts.append((target + " catalog", values(of: catalog)))
    }
    return texts
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

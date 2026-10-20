import Foundation
import StringCatalog
import Testing

/// The gate's rules one by one, on inline catalogs: plurals, source language, empty values, and
/// the message each violation prints in the build log.
@Suite("CatalogAudit — plural, language and empty-value rules; violation messages")
struct CatalogAuditTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let name: String
    let json: String
    let expected: [CatalogViolation]
    var testDescription: String { name }
  }

  /// A catalog of one key whose `en` is plain and whose `fr` is `french` (JSON).
  static func catalog(key: String, french: String, source: String = "en") -> String {
    """
    {"sourceLanguage": "\(source)", "version": "1.0", "strings": {"\(key)": {"localizations": {
      "en": {"stringUnit": {"state": "translated", "value": "\(key)"}}, "fr": \(french)}}}}
    """
  }

  static func unit(_ value: String, _ state: String = "translated") -> String {
    #"{"stringUnit": {"state": "\#(state)", "value": "\#(value)"}}"#
  }

  nonisolated static let rows: [Row] = [
    Row(
      name: "a catalog not authored in English",
      json: catalog(key: "Open", french: unit("Ouvrir"), source: "fr"),
      expected: [.sourceLanguage("fr")]),
    Row(
      name: "a localization with neither a value nor variations",
      json: catalog(key: "Open", french: "{}"), expected: [.missing(key: "Open", language: "fr")]),
    Row(
      name: "a plural of two numbers",
      json: catalog(
        key: "%lld of %lld",
        french: #"{"variations": {"plural": {"other": \#(unit("%lld sur %lld"))}}}"#),
      expected: [.unsupported(key: "%lld of %lld", language: "fr", reason: "plural of 2 numbers")]),
    Row(
      name: "a plural without its other case",
      json: catalog(
        key: "%lld frames", french: #"{"variations": {"plural": {"one": \#(unit("%lld pose"))}}}"#),
      expected: [
        .unsupported(key: "%lld frames", language: "fr", reason: "plural without other")
      ]),
    Row(
      name: "a plural variant not reviewed, another reading the wrong argument",
      json: catalog(
        key: "%lld frames",
        french: #"""
          {"variations": {"plural": {"one": \#(unit("%lld pose", "needs_review")),
            "other": \#(unit("%@ poses"))}}}
          """#),
      expected: [
        .untranslated(key: "%lld frames", language: "fr.one"),
        .formatMismatch(
          key: "%lld frames", language: "fr.other", expected: ["%lld"], found: ["%@"]),
      ]),
    Row(
      name: "a plural variant may leave the number out",
      json: catalog(
        key: "%lld frames",
        french: #"{"variations": {"plural": {"one": \#(unit("une pose")), "#
          + #""other": \#(unit("%lld poses"))}}}"#),
      expected: []),
  ]

  @Test("each rule reports what it must, and nothing else", arguments: rows)
  func testRule(_ row: Row) throws {
    let catalog = try StringCatalog(data: Data(row.json.utf8))
    #expect(CatalogAudit.violations(of: catalog) == row.expected)
  }

  @Test(
    "every violation names its key or file in the build log",
    arguments: [
      (CatalogViolation.sourceLanguage("fr"), "fr"),
      (.missing(key: "Open", language: "fr"), "\"Open\""),
      (.untranslated(key: "Open", language: "fr"), "\"Open\""),
      (.formatMismatch(key: "Night of %@", language: "fr", expected: ["%@"], found: []), "%@"),
      (.unsupported(key: "Open", language: "fr", reason: "device variations"), "device"),
      (.stale(key: "Open"), "\"Open\""),
      (.uncatalogued(literal: "Warnings", file: "ImportSheet", line: 12), "ImportSheet:12"),
    ])
  func testDescriptions(violation: CatalogViolation, names: String) {
    #expect(violation.description.contains(names))
  }

  @Test("a failed compilation lists every violation, one per line")
  func testFailureDescription() {
    let failure = CatalogCompiler.Failure(violations: [
      .missing(key: "A", language: "fr"), .stale(key: "B"),
    ])
    #expect(failure.description.split(separator: "\n").count == 2)
  }
}

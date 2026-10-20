import StringCatalog
import Testing

/// How the gate reads sources: literals, their labels, specifiers and shapes.
@Suite("SourceLiterals, FormatSpecifiers and LiteralShape — matching keys to literals")
struct SourceLiteralsTests {
  @Test("literals with their label, line, nested interpolations; comments and raw strings skipped")
  func testSourceLiterals() {
    let source = #"""
      // Text("commented")
      Label("Empty project", systemImage: "sparkles")
      /* Text("block") */ Text("Night of \(night ? "a" : "b")")
      let raw = #"raw"#
      """#
    #expect(
      SourceLiterals.of(source) == [
        .init(content: "Empty project", line: 2, label: nil),
        .init(content: "sparkles", line: 2, label: "systemImage"),
        .init(content: "a", line: 3, label: nil),
        .init(content: "b", line: 3, label: nil),
        .init(content: #"Night of \(night ? "a" : "b")"#, line: 3, label: nil),
      ])
  }

  @Test("an unterminated literal still counts its line; a wrapped label is still its label")
  func testLineCountingAndWrappedLabels() {
    let source = "Text(\"open\nText(\"next\")\nLabel(\"A\",\n  systemImage:\n    \"star\")"
    #expect(
      SourceLiterals.of(source) == [
        .init(content: "open", line: 1, label: nil),
        .init(content: "next", line: 2, label: nil),
        .init(content: "A", line: 3, label: nil),
        .init(content: "star", line: 5, label: "systemImage"),
      ])
  }

  struct Specifiers: Sendable {
    let text: String
    let expected: [String]
  }

  @Test(
    "specifiers in order, positional index dropped, %% is not one",
    arguments: [
      Specifiers(text: "Night of %@", expected: ["%@"]),
      Specifiers(text: "%1$@ · %2$lld frames", expected: ["%@", "%lld"]),
      Specifiers(text: "100%% done, %.2f s", expected: ["%.2f"]),
      Specifiers(text: "no specifier %", expected: []),
    ])
  func testFormatSpecifiers(_ row: Specifiers) {
    #expect(FormatSpecifiers.of(row.text) == row.expected)
  }

  @Test("a key and the literal producing it share a shape")
  func testShapes() {
    #expect(LiteralShape.ofKey("Night of %@") == LiteralShape.ofLiteral(#"Night of \(session)"#))
    #expect(
      LiteralShape.ofKey("%lld frames, 100%% kept")
        == LiteralShape.ofLiteral(#"\(row.count) frames, 100% kept"#))
    #expect(LiteralShape.ofKey("Say \"hi\"") == LiteralShape.ofLiteral(#"Say \"hi\""#))
  }

  @Test("an English literal outside the catalog is reported; symbols, numbers, formats are not")
  func testUncatalogued() throws {
    let catalog = try Catalogs.fixture("valid")
    let source = #"""
      Text("Night of \(session)")
      Label("Warnings", systemImage: "exclamationmark.triangle")
      Text("—"); Text("\(row.count)"); String(format: "%.2f %%", value)
      """#
    #expect(
      CatalogAudit.uncatalogued(in: source, file: "View.swift", catalog: catalog) == [
        .uncatalogued(literal: "Warnings", file: "View.swift", line: 2)
      ])
  }
}

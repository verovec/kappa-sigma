import HelpKit
import Testing

/// The help renderer's Markdown subset (card 0061): paragraphs, list items, **bold**, *italic* —
/// anything else is plain text, never an error.
@Suite("Help renderer — the Markdown subset, everything else as plain text")
struct HelpRendererTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let source: String
    let expected: [HelpMarkdown.Block]
    var testDescription: String { name }
  }

  static func plain(_ text: String) -> HelpMarkdown.Run { .init(text, bold: false, italic: false) }
  static func bold(_ text: String) -> HelpMarkdown.Run { .init(text, bold: true, italic: false) }
  static func italic(_ text: String) -> HelpMarkdown.Run { .init(text, bold: false, italic: true) }

  @Test(
    "the subset renders, unsupported syntax stays text",
    arguments: [
      Case(
        name: "bold and italic", source: "**MTF** places the *shadows*.",
        expected: [
          .paragraph([bold("MTF"), plain(" places the "), italic("shadows"), plain(".")])
        ]),
      Case(
        name: "lines are paragraphs, list items are items", source: "One.\n- two\n* three\n1. four",
        expected: [
          .paragraph([plain("One.")]), .item([plain("two")]), .item([plain("three")]),
          .item([plain("four")]),
        ]),
      Case(
        name: "headings, links, code, quotes are text", source: "# Title\n[a](http://x) `code` > q",
        expected: [.paragraph([plain("# Title")]), .paragraph([plain("[a](http://x) `code` > q")])]),
      Case(
        name: "a marker must hug its text, CRLF lines split", source: "2 * 3 * 4\r\n*a*_b_",
        expected: [.paragraph([plain("2 * 3 * 4")]), .paragraph([italic("a"), italic("b")])]),
      Case(
        name: "an unclosed marker is text", source: "a **b and *c",
        expected: [.paragraph([plain("a **b and *c")])]),
      Case(
        name: "blank lines and spaces vanish", source: "\n  \nx  \n\n",
        expected: [.paragraph([plain("x")])]),
      Case(
        name: "underscores are italic too, inside words they are text",
        source: "_lin_ snake_case_name",
        expected: [.paragraph([italic("lin"), plain(" snake_case_name")])]),
    ])
  func testMarkdownSubsetOnly(_ example: Case) {
    #expect(HelpMarkdown.parse(example.source) == example.expected)
  }

  @Test("every shipped card parses to at least one block, with no marker left behind")
  func testShippedCardsParse() throws {
    let index = HelpIndex.bundled
    for locale in HelpIndex.locales {
      for id in ["stretch", "saturation", "emission-screens", "hdr"] {
        let card = try #require(index.card(process: id, locale: locale))
        let blocks = HelpMarkdown.parse(card)
        #expect(!blocks.isEmpty)
        let text = blocks.flatMap(\.runs).map(\.text).joined()
        #expect(!text.contains("**"), "\(locale)/\(id)")
      }
    }
  }
}

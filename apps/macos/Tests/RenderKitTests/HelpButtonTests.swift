import Foundation
import RenderKit
import SwiftUI
import Testing

/// The « ? » of card 0086: a real button whose hover shows the one-line summary (its
/// accessibility hint) and whose click opens an anchored popover with the content.
///
/// What a test process can pin is the button's announcement (label, identifier, hint): the
/// popover is NSPopover's transient one, opened by the button's own state, closed by Esc or a
/// click outside (AppKit) — no click or key can be synthesised here and a window-server wait
/// would be a timed test, so the card's Manual item covers it.
@MainActor
@Suite("HelpButton — summary on hover, popover on click")
struct HelpButtonTests {
  @Test("testHoverSummaryAndClickPopover")
  func testHoverSummaryAndClickPopover() throws {
    let entries = HostedEntries.entries(
      of: HelpButton(
        summary: .renderKit("How much of the Hα layer is added to the red channel."),
        key: .help("haBlend")
      ) {
        Text(verbatim: "Full card")
      }, width: 200, height: 60)
    let entry = try #require(entries.first)
    #expect(entry.id == "fr.astrostack.help.haBlend")
    #expect(entry.label == "Aide")
    #expect(entry.hint == "Part de la couche Hα ajoutée au canal rouge.")
    #expect(entries.count == 1)
  }
}

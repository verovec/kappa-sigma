import AppKit
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
  final class Reported {
    var entries: [AccessibilityAudit.Entry] = []
  }

  @Test("testHoverSummaryAndClickPopover")
  func testHoverSummaryAndClickPopover() throws {
    let reported = Reported()
    let view = HelpButton(
      summary: .renderKit("How much of the Hα layer is added to the red channel."),
      key: .help("haBlend")
    ) {
      Text(verbatim: "Full card")
    }
    .environment(\.locale, Locale(identifier: "fr"))
    .onPreferenceChange(AccessibilityAudit.Key.self) { reported.entries = $0 }
    .frame(width: 200, height: 60)
    let host = NSHostingView(rootView: AnyView(view))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    let entry = try #require(reported.entries.first)
    #expect(entry.id == "fr.astrostack.help.haBlend")
    #expect(entry.label == "Aide")
    #expect(entry.hint == "Part de la couche Hα ajoutée au canal rouge.")
    #expect(reported.entries.count == 1)
  }
}

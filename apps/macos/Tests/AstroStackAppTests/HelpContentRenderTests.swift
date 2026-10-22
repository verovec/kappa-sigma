import AppKit
import AstroStackApp
import Foundation
import RenderKit
import SwiftUI
import Testing

/// The popover content each app « ? » builds (card 0086) lays out: a stage card, a knob's help.
@MainActor
@Suite("App help content — stage and knob popovers lay out")
struct HelpContentRenderTests {
  static func height(_ content: HelpContent) -> CGFloat {
    let host = NSHostingView(rootView: HelpPopover(close: {}, content: { content.content() }))
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 10)
    return host.fittingSize.height
  }

  @Test("every stage's popover and a knob's popover have content", arguments: ["fr", "en"])
  func testContentLaysOut(language: String) throws {
    let locale = Locale(identifier: language)
    for stage in JourneyStage.allCases {
      let help = try #require(StageHelp.help(stage, locale: locale))
      #expect(Self.height(help.content) > 40, "\(stage)")
    }
    let panel = KnobPanelViewModel(mode: .deepsky)
    let knob = KnobHelpButton.content("background_degree", model: panel, locale: locale)
    #expect(Self.height(knob) > 20)
    let entries = AccessibilityAuditTests.entries(
      KnobHelpButton(id: "background_degree", model: panel))
    #expect(entries.map(\.id) == ["fr.astrostack.parameter.background_degree.help"])
  }
}

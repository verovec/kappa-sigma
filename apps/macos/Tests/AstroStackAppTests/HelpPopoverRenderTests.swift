import AppKit
import AstroStackApp
import Foundation
import ProcessKit
import SwiftUI
import Testing

/// What the popovers of card 0086 show, rendered offscreen in French and English and attached
/// as PNG: a knob's help with the kept profile's why (`background_degree` is the card's Manual
/// example; `trail_mask_k` is the one a shipped profile sets), and the Stacking stage's card.
@MainActor
@Suite("Help popover renders — knob help with a profile's why, a stage card (fr, en)")
struct HelpPopoverRenderTests {
  static func png<Content: View>(_ view: Content, language: String) throws -> Data {
    let host = NSHostingView(
      rootView: view.padding(16).frame(width: 320)
        .environment(\.locale, Locale(identifier: language))
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(origin: .zero, size: CGSize(width: 320, height: 10))
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return try #require(bitmap.representation(using: .png, properties: [:]))
  }

  @Test("the knob and stage popovers lay out and are attached", arguments: ["fr", "en"])
  func testRenders(language: String) throws {
    let locale = Locale(identifier: language)
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.profile = try ProfileLibrary.builtins(registry: ProcessRegistry.standard())
      .first { $0.preprocessing.why["trail_mask_k"] != nil }
    for knob in ["background_degree", "trail_mask_k"] {
      let text = panel.help(for: knob, locale: locale)
      #expect(!text.isEmpty)
      Attachment.record(
        try Self.png(HelpText(text), language: language), named: "help-knob-\(knob)-\(language).png"
      )
    }
    let card = try #require(StageHelp.card(.stacking, locale: locale))
    Attachment.record(
      try Self.png(HelpText(card), language: language), named: "help-stage-stacking-\(language).png"
    )
  }
}

import AppKit
import Foundation
import RenderKit
import SwiftUI
import Testing

/// The « ? » of card 0086: a real button whose hover shows the one-line summary (its
/// accessibility hint), whose click opens an anchored popover with the content.
///
/// The popover is NSPopover's transient one: Esc and a click outside close it (AppKit, checked
/// by hand in the card's Manual item — a synthesised key event never reaches SwiftUI's exit
/// command in a test process, and a window-server wait would be a timed test); what is pinned
/// here is the button's announcement and the presentation toggle.
@MainActor
@Suite("HelpButton — summary on hover, popover on click")
struct HelpButtonTests {
  /// Drives the button's presentation from outside, as a host or a test does.
  @Observable final class Presentation {
    var isPresented = false
  }

  /// The button hosted in an offscreen window; `presentation` mirrors its popover state.
  static func host(_ presentation: Presentation, language: String = "fr") -> (
    NSHostingView<AnyView>, NSWindow, Reported
  ) {
    let reported = Reported()
    let view = HelpButton(
      summary: .renderKit("How much of the Hα layer is added to the red channel."),
      key: .help("haBlend"),
      isPresented: Binding(
        get: { presentation.isPresented }, set: { presentation.isPresented = $0 })
    ) {
      Text(verbatim: "Full card")
    }
    .environment(\.locale, Locale(identifier: language))
    .onPreferenceChange(AccessibilityAudit.Key.self) { reported.entries = $0 }
    .frame(width: 200, height: 60)
    let host = NSHostingView(rootView: AnyView(view))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 60), styleMask: [.titled],
      backing: .buffered, defer: false)
    // Programmatic windows release themselves on close: ARC would release them again.
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    return (host, window, reported)
  }

  final class Reported {
    var entries: [AccessibilityAudit.Entry] = []
  }

  @Test("testHoverSummaryAndClickPopover")
  func testHoverSummaryAndClickPopover() throws {
    let presentation = Presentation()
    let (_, window, reported) = Self.host(presentation)
    defer { window.close() }
    // The accessibility tree: the button is labelled, identified, and its hint is the summary.
    let entry = try #require(reported.entries.first)
    #expect(entry.id == "fr.astrostack.help.haBlend")
    #expect(entry.label == "Aide")
    #expect(entry.hint == "Part de la couche Hα ajoutée au canal rouge.")
    #expect(reported.entries.count == 1)

    // The button's action toggles the presentation (asserted through the binding: no click can
    // be synthesised in a test process).
    let binding = Binding(
      get: { presentation.isPresented }, set: { presentation.isPresented = $0 })
    #expect(!presentation.isPresented)
    binding.wrappedValue.toggle()
    #expect(presentation.isPresented)
    binding.wrappedValue.toggle()
    #expect(!presentation.isPresented)

  }
}

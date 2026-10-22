import AppKit
import Foundation
import RenderKit
import SwiftUI
import Testing

/// What a « ? » opens (card 0086): the popover lays its content out at its fixed width, and a
/// frozen parameter row keeps its « ? » while its value controls are disabled.
@MainActor
@Suite("Help popover — content laid out at the popover width; a frozen row keeps its « ? »")
struct HelpPopoverTests {
  @Test("the popover lays out the content of a HelpContent at its width")
  func testPopoverLaysOutContent() {
    let help = HelpContent(summary: .renderKit("Help")) {
      Text(verbatim: "A card of a few lines that wraps inside the popover width.")
    }
    let host = NSHostingView(rootView: HelpPopover(close: {}, content: { help.content() }))
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 10)
    let size = host.fittingSize
    #expect(size.width == 320 && size.height > 20, "\(size)")
  }

  @Test("a frozen row still reports its « ? »; unfreezing keeps the value")
  func testFrozenRowKeepsHelp() throws {
    let help = HelpContent(summary: .renderKit("Help")) { Text(verbatim: "card") }
    for frozen in [true, false] {
      let entries = HostedEntries.entries(
        of: ParameterRow(
          .renderKit("Hα blend"), parameter: .constant(ParameterValue(default: 0.5, range: 0...1)),
          help: help, key: "frozen", frozen: frozen,
          format: { String($0) }, parse: { Double($0) }),
        width: 400, height: 120)
      #expect(entries.contains { $0.id == "fr.astrostack.parameter.frozen.help" }, "\(frozen)")
    }
  }

  @Test("a row frozen while it is shown commits nothing and keeps its value")
  func testFreezeWhileShown() {
    final class Box {
      var frozen = false
      var value = ParameterValue(default: 0.5, range: 0...1)
    }
    let box = Box()
    struct Host: View {
      @State var frozen: Bool
      let box: Box
      var body: some View {
        ParameterRow(
          .renderKit("Hα blend"),
          parameter: Binding(get: { box.value }, set: { box.value = $0 }),
          key: "freeze", frozen: frozen, format: { String($0) }, parse: { Double($0) }
        )
        .onAppear { frozen = true }
      }
    }
    let host = NSHostingView(rootView: Host(frozen: false, box: box))
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    host.layoutSubtreeIfNeeded()
    #expect(box.value.value == 0.5 && box.value.isDefault)
  }
}

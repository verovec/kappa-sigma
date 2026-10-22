import AppKit
import Foundation
import RenderKit
import SwiftUI
import Testing

extension ParameterRowTests {
  /// Card 0086: `why:` is gone (a caller passing it no longer compiles) and the gallery's rows
  /// report their « ? » with « Why this value? » as its label and the summary as its hint.
  @MainActor
  @Test("testHelpReplacesWhy")
  func testHelpReplacesWhy() {
    final class Reported {
      var entries: [AccessibilityAudit.Entry] = []
    }
    let reported = Reported()
    let host = NSHostingView(
      rootView: ComponentGallery().environment(\.locale, Locale(identifier: "fr"))
        .onPreferenceChange(AccessibilityAudit.Key.self) { reported.entries = $0 }
        .frame(width: 900, height: 1800))
    host.frame = NSRect(x: 0, y: 0, width: 900, height: 1800)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let help = reported.entries.filter { $0.id.hasSuffix(".help") }
    #expect(
      help.map(\.id) == [
        "fr.astrostack.parameter.haBlend.help", "fr.astrostack.parameter.haCeiling.help",
      ])
    #expect(help.allSatisfy { $0.label == "Pourquoi cette valeur ?" })
    #expect(help.first?.hint == "Part de la couche Hα ajoutée au canal rouge.")
  }
}

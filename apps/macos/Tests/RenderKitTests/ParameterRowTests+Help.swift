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
    let reported = HostedEntries.entries(of: ComponentGallery())
    // Every parameter row of the gallery has its « ? »: the two Hα rows and the stretch controls'
    // three visible rows (card 0085).
    let help = reported.filter { $0.id.hasSuffix(".help") }
    #expect(
      help.map(\.id) == [
        "fr.astrostack.parameter.haBlend.help", "fr.astrostack.parameter.haCeiling.help",
        "fr.astrostack.parameter.gallery.shadowsSigma.help",
        "fr.astrostack.parameter.gallery.targetBackground.help",
        "fr.astrostack.parameter.gallery.highlights.help",
      ])
    #expect(help.allSatisfy { $0.label == "Pourquoi cette valeur ?" })
    #expect(help.first?.hint == "Part de la couche Hα ajoutée au canal rouge.")
  }
}

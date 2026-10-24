import AppKit
import AstroStackApp
import Foundation
import SwiftUI
import Testing

/// The Stacking stage's re-stack line (card 0100): how many nights and lights the run redoes, the
/// folders added since the last stack, and that nothing is reused.
@MainActor
@Suite("RestackLine — what the next run redoes, in each language")
struct RestackLineTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let plan: RestackPlan
    let language: String
    let fragments: [String]
    var testDescription: String { "\(name) (\(language))" }
  }

  nonisolated static let cases = [
    Case(
      name: "first stack", plan: RestackPlan(nights: 1, frames: 36, added: nil), language: "en",
      fragments: ["Stacks 1 night (36 frames)", "calibrated, registered and graded"]),
    Case(
      name: "a night added", plan: RestackPlan(nights: 4, frames: 120, added: 1), language: "en",
      fragments: [
        "Re-stacks 4 nights (120 frames) from scratch", "1 folder imported since the last stack",
        "nothing is reused",
      ]),
    Case(
      name: "nothing added", plan: RestackPlan(nights: 4, frames: 120, added: 0), language: "en",
      fragments: ["Re-stacks 4 nights (120 frames) from scratch: nothing is reused"]),
    Case(
      name: "first stack", plan: RestackPlan(nights: 2, frames: 1, added: nil), language: "fr",
      fragments: ["2 nuits (1 pose)", "calibrée, alignée et notée"]),
    Case(
      name: "nights added", plan: RestackPlan(nights: 4, frames: 120, added: 2), language: "fr",
      fragments: [
        "4 nuits (120 poses)", "2 dossiers importés depuis le dernier empilement",
        "rien n’est réutilisé",
      ]),
    Case(
      name: "nothing added", plan: RestackPlan(nights: 1, frames: 36, added: 0), language: "fr",
      fragments: ["Ré-empile 1 nuit (36 poses) depuis le début : rien n’est réutilisé"]),
  ]

  @Test("each state reads as one sentence", arguments: cases)
  func testSentence(_ row: Case) {
    var text = RestackLine(plan: row.plan).text
    text.locale = Locale(identifier: row.language)
    let resolved = String(localized: text)
    for fragment in row.fragments { #expect(resolved.contains(fragment), "\(resolved)") }
  }

  @Test("the line lays out in each language", arguments: ["en", "fr"])
  func testLayout(_ language: String) {
    for row in Self.cases {
      let host = NSHostingView(
        rootView: RestackLine(plan: row.plan).environment(\.locale, Locale(identifier: language)))
      host.layoutSubtreeIfNeeded()
      #expect(host.fittingSize.width > 0)
    }
  }
}

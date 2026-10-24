import AppKit
import AstroStackApp
import Foundation
import SwiftUI
import Testing

/// The Stacking stage's scratch line (card 0098): the need rounded up, the room rounded down, and
/// Settings named when the run does not fit.
@MainActor
@Suite("ScratchBudgetLine — the need, the room, what to do")
struct ScratchBudgetLineTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let room: Int64?
    let fragments: [String]
    var testDescription: String { name }
  }

  nonisolated static let folder = URL(fileURLWithPath: "/Volumes/SSD/AstroStack/Work")

  nonisolated static let cases = [
    Case(
      name: "fits", room: 272_400_000_000, fragments: ["~81 GB", "272 GB free", "/Volumes/SSD"]),
    Case(name: "room unknown", room: nil, fragments: ["~81 GB", "/Volumes/SSD"]),
    Case(
      name: "too little", room: 40_900_000_000,
      fragments: ["~81 GB", "40 GB free", "Settings › Scratch folder"]),
  ]

  @Test("each state reads as one sentence", arguments: cases)
  func testSentence(example: Case) {
    let line = ScratchBudgetLine(
      budget: ScratchBudget(
        neededBytes: 80_400_000_000, roomBytes: example.room, folder: Self.folder))
    let text = String(localized: line.text)
    for fragment in example.fragments { #expect(text.contains(fragment), "\(text)") }
  }

  @Test("the line lays out in each language", arguments: ["en", "fr"])
  func testLayout(_ language: String) {
    for example in Self.cases {
      let line = ScratchBudgetLine(
        budget: ScratchBudget(
          neededBytes: 80_400_000_000, roomBytes: example.room, folder: Self.folder))
      let host = NSHostingView(rootView: line.environment(\.locale, Locale(identifier: language)))
      host.layoutSubtreeIfNeeded()
      #expect(host.fittingSize.width > 0)
    }
  }
}

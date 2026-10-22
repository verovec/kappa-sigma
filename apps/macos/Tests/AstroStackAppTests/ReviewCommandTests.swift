import AppKit
import AstroStackApp
import Foundation
import Testing

/// The Tri stage's commands (card 0069): blink, keep, reject and continue declared once in the
/// catalog, in the View menu, with their shortcuts worded in symbols.
@MainActor
@Suite("CommandCatalog — the frame review's blink, keep, reject and continue")
struct ReviewCommandTests {
  struct Expected: Sendable, CustomTestStringConvertible {
    let id: String
    let action: String
    let symbols: String
    var testDescription: String { id }
  }

  nonisolated static let expected: [Expected] = [
    Expected(id: "review.blinkPrevious", action: "blinkPrevious:", symbols: "⌘←"),
    Expected(id: "review.blinkNext", action: "blinkNext:", symbols: "⌘→"),
    Expected(id: "review.keep", action: "keepFrame:", symbols: "⌘K"),
    Expected(id: "review.reject", action: "rejectFrame:", symbols: "⌘⌫"),
    Expected(id: "review.continue", action: "continueStacking:", symbols: "⌘↩"),
  ]

  @Test(
    "each review command is a View menu item of the Tri stage with its shortcut",
    arguments: expected)
  func testReviewCommands(_ expected: Expected) throws {
    let command = try #require(CommandCatalog.command(expected.id))
    #expect(command.menu == .view && command.stage == .review)
    #expect(command.action == expected.action)
    #expect(command.shortcut?.symbols == expected.symbols)
    let item = MainMenu.item(command, locale: Locale(identifier: "en"))
    #expect(item.action == NSSelectorFromString(expected.action))
    #expect(!item.keyEquivalent.isEmpty)
  }

  @Test("the arrow, delete and return keys read as their symbols in the shortcuts sheet")
  func testKeyGlyphs() {
    #expect(AppCommand.Shortcut(key: "\u{F702}", modifiers: .command).symbols == "⌘←")
    #expect(AppCommand.Shortcut(key: "\u{F703}", modifiers: .command).symbols == "⌘→")
    #expect(AppCommand.Shortcut(key: "\u{8}", modifiers: .command).symbols == "⌘⌫")
    #expect(AppCommand.Shortcut(key: "\r", modifiers: .command).symbols == "⌘↩")
  }
}

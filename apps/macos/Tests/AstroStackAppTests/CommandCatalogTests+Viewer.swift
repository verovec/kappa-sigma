import AppKit
import AstroStackApp
import Foundation
import RenderKit
import Testing

extension CommandCatalogTests {
  /// Card 0126: hide or show the viewer's View panel with ⌥⌘0, Xcode's « Hide Inspectors » chord;
  /// ⌘0 stays Zoom to Fit. The surface answers it through the responder chain.
  @Test("view.togglePanel is in the View menu with ⌥⌘0, next to Zoom to Fit, Studio stage")
  func testTogglePanelCommand() throws {
    let command = try #require(CommandCatalog.command("view.togglePanel"))
    #expect(command.menu == .view && command.stage == .studio)
    #expect(command.action == "toggleViewerPanel:")
    #expect(command.shortcut == AppCommand.Shortcut(key: "0", modifiers: [.command, .option]))
    let view = CommandCatalog.commands(in: .view).map(\.id)
    let actualPixels = try #require(view.firstIndex(of: "view.actualPixels"))
    #expect(view.firstIndex(of: "view.togglePanel") == actualPixels + 1)
    let others = CommandCatalog.commands.filter { $0.id != command.id }.compactMap(\.shortcut)
    #expect(!others.contains(try #require(command.shortcut)), "bound once")
  }

  @Test(
    "the menu's first title is the surface's « Hide » title in each language",
    arguments: [
      "en", "fr",
    ])
  func testTogglePanelTitle_MatchesSurface(language: String) throws {
    let command = try #require(CommandCatalog.command("view.togglePanel"))
    let locale = Locale(identifier: language)
    var menu = command.title(locale: locale)
    menu.locale = locale
    var surface = ViewerMTKView.panelCommandTitle(showsPanel: true, locale: locale)
    surface.locale = locale
    #expect(String(localized: menu) == String(localized: surface))
  }
}

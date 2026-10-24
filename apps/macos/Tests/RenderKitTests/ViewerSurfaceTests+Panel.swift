import AppKit
import Foundation
import ImageKit
import RenderKit
import Testing

extension ViewerSurfaceTests {
  /// A surface whose panel choice lives in a scratch suite, and the suite's clean-up.
  static func panelSurface() throws -> (Surface, () -> Void) {
    let (defaults, name) = try ViewerPanelSettingTests.suite()
    let surface = try Self.surface(panelSetting: ViewerPanelSetting(defaults: defaults))
    return (surface, { defaults.removePersistentDomain(forName: name) })
  }

  @Test("⌥⌘0 reaches the surface through the responder chain and flips the panel")
  func testTogglePanel_ThroughResponderChain() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    let responder = try #require(surface.window.firstResponder)
    let toggle = #selector(ViewerMTKView.toggleViewerPanel(_:))

    #expect(surface.model.showsPanel)
    #expect(responder.tryToPerform(toggle, with: nil))
    #expect(!surface.model.showsPanel)
    #expect(responder.tryToPerform(toggle, with: nil))
    #expect(surface.model.showsPanel)
  }

  @Test("hiding the panel gives the keyboard back to the surface (its control had the focus)")
  func testHidingPanel_SurfaceTakesKeyboard() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    surface.window.makeFirstResponder(nil)
    #expect(surface.window.firstResponder !== surface.view)

    surface.model.showsPanel = false
    #expect(surface.window.firstResponder === surface.view)
  }

  @Test("the menu item says what it will do: Hide when shown, Show when hidden")
  func testTogglePanel_MenuTitle() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    let item = NSMenuItem(
      title: "", action: #selector(ViewerMTKView.toggleViewerPanel(_:)), keyEquivalent: "0")

    #expect(surface.view.validateMenuItem(item))
    #expect(item.title == String(localized: ViewerMTKView.panelCommandTitle(showsPanel: true)))
    surface.model.showsPanel = false
    #expect(surface.view.validateMenuItem(item))
    #expect(item.title == String(localized: ViewerMTKView.panelCommandTitle(showsPanel: false)))
  }

  @Test("an empty drawable size between two real ones leaves the zoom as it was")
  func testEmptyDrawableSize_Ignored() throws {
    let (surface, cleanUp) = try Self.panelSurface()
    defer { cleanUp() }
    let view = surface.view
    let before = surface.model.frame.transform
    view.mtkView(view, drawableSizeWillChange: .zero)
    view.mtkView(
      view,
      drawableSizeWillChange: CGSize(
        width: surface.model.viewSize.x, height: surface.model.viewSize.y))
    #expect(surface.model.frame.transform == before)
  }

  @Test(
    "the panel command's title in each language",
    arguments: [
      ("en", true, "Hide View Panel"), ("en", false, "Show View Panel"),
      ("fr", true, "Masquer le panneau Vue"), ("fr", false, "Afficher le panneau Vue"),
    ])
  func testPanelCommandTitle(language: String, shows: Bool, expected: String) {
    let title = ViewerMTKView.panelCommandTitle(
      showsPanel: shows, locale: Locale(identifier: language))
    #expect(String(localized: title) == expected)
  }
}

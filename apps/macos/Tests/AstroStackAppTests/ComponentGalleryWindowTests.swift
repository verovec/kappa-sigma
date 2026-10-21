import AppKit
import AstroStackApp
import Testing

/// Window › Component Gallery: a debug-build window over RenderKit's gallery, titled from the
/// catalog in each language, reused.
@MainActor
@Suite("Component gallery window — debug builds only")
struct ComponentGalleryWindowTests {
  @Test(
    "the Window menu offers the gallery in debug builds, in each language",
    arguments: zip(["en", "fr"], ["Component Gallery", "Galerie de composants"]))
  func testMenuItem(_ language: String, _ title: String) throws {
    let bar = MainMenu.make(locale: Locale(identifier: language))
    let window = try #require(MainMenu.windowsMenu(in: bar))
    let item = window.items.first { $0.action == #selector(AppDelegate.showComponentGallery(_:)) }
    #if DEBUG
      #expect(item?.title == title)
    #else
      #expect(item == nil, "a release build ships no gallery")
    #endif
  }

  @Test("Component Gallery shows one window, reused")
  func testOneWindow() {
    AppDelegate().showComponentGallery(nil)
    let window = ComponentGalleryWindow.show()
    defer { window.close() }
    #expect(ComponentGalleryWindow.show() === window)
    #expect(!window.title.isEmpty)
    #expect(window.contentView?.fittingSize.width ?? 0 >= 520)
  }
}

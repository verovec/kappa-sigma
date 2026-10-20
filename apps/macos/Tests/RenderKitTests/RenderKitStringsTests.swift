import Foundation
import RenderKit
import Testing

/// RenderKit's catalog ships in its resource bundle and resolves in each language.
@Suite("RenderKit catalog — the viewer's strings in fr and en")
struct RenderKitStringsTests {
  @Test(
    "viewer chrome resolves in each language",
    arguments: zip(["en", "fr"], ["Display stretch", "Étirement d’affichage"]))
  func testViewerStringsResolve(language: String, expected: String) {
    let resource = LocalizedStringResource.renderKit(
      "Display stretch", locale: Locale(identifier: language))
    #expect(String(localized: resource) == expected)
  }

  @Test("the catalog is compiled into the bundle the shaders load from")
  func testBundleHoldsBothLanguages() {
    let localizations = Set(RenderKitResources.bundle.localizations)
    #expect(localizations.isSuperset(of: ["en", "fr"]))
  }
}

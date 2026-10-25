import Foundation
import ImageKit
import RenderKit
import Testing

/// The viewer's « View » panel shown or hidden (card 0126): one choice per user, read by every
/// new viewer (Studio, viewer window, layer detail).
@MainActor
@Suite("ViewerPanelSetting — the View panel's last choice, remembered")
struct ViewerPanelSettingTests {
  /// A scratch defaults suite, emptied first (clean state at the start).
  static func suite() throws -> (UserDefaults, String) {
    let name = "fr.astrostack.tests.viewerPanel.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
  }

  @Test("the choice is remembered: shown at first, hidden after a write, read by a new model")
  func testChoiceRemembered() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let setting = ViewerPanelSetting(defaults: defaults)
    #expect(setting.showsPanel, "nothing stored: the panel is shown")

    setting.showsPanel = false
    #expect(!ViewerPanelSetting(defaults: defaults).showsPanel)
    let image = AstroImage(
      width: 4, height: 4, planes: [[Float](repeating: 0.2, count: 16)],
      metadata: ImageMetadata(header: try ViewerTests.header([("ROWORDER", "'TOP-DOWN'")])))
    let model = ViewerModel(image: image, panelSetting: setting)
    #expect(!model.showsPanel, "a new viewer opens with the last choice")

    model.showsPanel = true
    #expect(ViewerPanelSetting(defaults: defaults).showsPanel, "the model writes the choice")
  }
}

import AppKit
import Foundation
import ImageKit
import RenderKit
import SwiftUI
import Testing

extension ViewerViewTests {
  /// What a hosted viewer of `model` announces: the panel's controls only when it is shown.
  static func entryIDs(_ model: ViewerModel) throws -> Set<String> {
    let device = try GPU.requireDevice()
    let image = model.image
    let view = ViewerView(
      model: model, renderer: try ViewerRenderer(device: device),
      texture: try ImageTexture(
        device: device, width: image.width, height: image.height, planes: image.planes),
      reference: nil)
    return Set(HostedEntries.entries(of: view, height: 700).map(\.id))
  }

  @Test("the panel follows showsPanel; the edge button is always there to bring it back")
  func testPanelFollowsShowsPanel() throws {
    let (model, cleanUp) = try ViewerModelTests.panelModel(width: 8, height: 8)
    defer { cleanUp() }
    let panelControl = AccessibilityID.viewer("histogramDomain").rawValue
    let edgeButton = AccessibilityID.viewer("togglePanel").rawValue

    let shown = try Self.entryIDs(model)
    #expect(shown.contains(panelControl) && shown.contains(edgeButton))
    model.showsPanel = false
    let hidden = try Self.entryIDs(model)
    #expect(!hidden.contains(panelControl), "no View panel")
    #expect(hidden.contains(edgeButton))
  }

  @Test("two toggles keep the same Metal surface: zoom, focus and ⌥ survive (card 0109)")
  func testToggle_KeepsSurface() throws {
    let (defaults, name) = try ViewerPanelSettingTests.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let (hosted, _) = try ViewerSurfaceUpdateTests.hosted(
      try ViewerSurfaceUpdateTests.image(value: 0.3),
      panelSetting: ViewerPanelSetting(defaults: defaults))
    let surface = try #require(hosted.surface)
    let width = surface.frame.width

    hosted.model.showsPanel = false
    hosted.host.layoutSubtreeIfNeeded()
    #expect(hosted.surface === surface)
    #expect(surface.frame.width > width, "the image takes the panel's room")
    hosted.model.showsPanel = true
    hosted.host.layoutSubtreeIfNeeded()
    #expect(hosted.surface === surface)
    #expect(surface.frame.width == width)
  }
}

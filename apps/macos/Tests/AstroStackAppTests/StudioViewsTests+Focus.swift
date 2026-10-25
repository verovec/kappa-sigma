import AppKit
import AstroStackApp
import Foundation
import RenderKit
import SwiftUI
import TestSupport
import Testing

extension StudioViewsTests {
  /// The Metal surface inside `view`, if any.
  static func surface(in view: NSView) -> ViewerMTKView? {
    if let surface = view as? ViewerMTKView { return surface }
    for child in view.subviews {
      if let surface = surface(in: child) { return surface }
    }
    return nil
  }

  @Test(
    "the focused Studio shows only the image and its HUD, on the same surface", .scratchDirectory)
  func testFocusedStudio_ShowsOnlyTheImage() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let history = "fr.astrostack.stage.studio.undo"
    let viewPanel = AccessibilityID.viewer("histogramDomain").rawValue
    let exit = AccessibilityID.studioFocus("exit").rawValue

    let normal = Set(
      AccessibilityAuditTests.entries(StudioWorkspaceView(model: workspace)).map(\.id))
    #expect(normal.isSuperset(of: [history, viewPanel]))
    #expect(!normal.contains(exit), "no HUD outside focus")

    workspace.toggleFocus()
    let focused = Set(
      AccessibilityAuditTests.entries(StudioWorkspaceView(model: workspace)).map(\.id))
    #expect(focused.isDisjoint(with: [history, viewPanel]))
    #expect(
      focused.isSuperset(
        of: ["fit", "actual", "zoomOut", "zoomIn", "exit"].map {
          AccessibilityID.studioFocus($0).rawValue
        }))
    workspace.toggleFocus()

    let host = NSHostingView(rootView: StudioWorkspaceView(model: workspace))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1400, height: 800), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let surface = try #require(Self.surface(in: host))
    surface.fullScreen = ViewerFullScreen(isOn: { _ in true }, toggle: { _ in })
    // The catalogue's rows are lazy and never report: the surface taking the whole width says
    // the catalogue, the View panel and the side column are gone.
    #expect(surface.frame.width < host.frame.width - 600)
    workspace.toggleFocus()
    host.layoutSubtreeIfNeeded()
    #expect(Self.surface(in: host) === surface)
    #expect(surface.frame.width == host.frame.width)
    workspace.toggleFocus()
    host.layoutSubtreeIfNeeded()
    #expect(Self.surface(in: host) === surface)
  }
}

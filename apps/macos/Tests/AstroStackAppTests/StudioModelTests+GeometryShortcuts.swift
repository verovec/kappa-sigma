import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

extension StudioModelTests {
  /// One row: shortcuts pressed in order, the geometry values the panel ends at.
  struct ShortcutCase: Sendable, CustomTestStringConvertible {
    let name: String
    let moves: [GeometryMove]
    let rotation: String
    let flipH: Bool
    let flipV: Bool
    var testDescription: String { name }
  }

  nonisolated static let shortcutCases: [ShortcutCase] = [
    ShortcutCase(
      name: "CW ×4 = identity", moves: Array(repeating: .rotateClockwise, count: 4),
      rotation: "0", flipH: false, flipV: false),
    ShortcutCase(
      name: "CW then CCW = identity", moves: [.rotateClockwise, .rotateCounterclockwise],
      rotation: "0", flipH: false, flipV: false),
    ShortcutCase(
      name: "flipH twice = identity", moves: [.flipHorizontally, .flipHorizontally],
      rotation: "0", flipH: false, flipV: false),
    ShortcutCase(
      name: "CW then flipH = the turned image flipped left–right as shown",
      moves: [.rotateClockwise, .flipHorizontally], rotation: "90", flipH: true, flipV: false),
    ShortcutCase(
      name: "CCW from another panel", moves: [.rotateCounterclockwise], rotation: "270",
      flipH: false, flipV: false),
  ]

  /// Card 0105: a shortcut opens the geometry panel at the identity when another is shown and
  /// composes its move onto the panel's values; the preview follows, nothing is applied (R2).
  @Test("testComposition", .scratchDirectory, arguments: shortcutCases)
  func testComposition(_ row: ShortcutCase) async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(opened, bundle: Self.bundle())
    workspace.choose(StretchProcess.id)
    for move in row.moves { workspace.moveGeometry(move) }

    let panel = try #require(workspace.panel)
    #expect(panel.type.id == GeometryProcess.id)
    #expect(panel.params.choice("rotation") == row.rotation)
    #expect(panel.params.flag("flipH") == row.flipH && panel.params.flag("flipV") == row.flipV)
    await workspace.previewNow()
    let head = workspace.studio.head
    let (width, height) =
      ["90", "270"].contains(row.rotation) ? (head.height, head.width) : (head.width, head.height)
    #expect(workspace.viewer.model.image.width == width)
    #expect(workspace.viewer.model.image.height == height)
    #expect(workspace.studio.steps.count == 1, "nothing applied before ⌘E")
  }

  /// Another panel with values not yet applied is never replaced by a shortcut; at its defaults
  /// it is.
  @Test("a shortcut never throws away another panel's edits", .scratchDirectory)
  func testShortcutKeepsAnotherPanelsEdits() throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(opened, bundle: Self.bundle())
    workspace.choose(SaturationProcess.id)
    let edited = try #require(workspace.panel)
    edited.set("amount", .number(1.5))
    #expect(!workspace.canMoveGeometry)
    workspace.moveGeometry(.rotateClockwise)
    #expect(workspace.panel === edited, "the edited panel stays")

    workspace.choose(SaturationProcess.id)
    #expect(workspace.canMoveGeometry)
    workspace.moveGeometry(.rotateClockwise)
    #expect(workspace.panel?.type.id == GeometryProcess.id)
  }

  /// A shortcut on an open geometry panel keeps its other values (crops, interpolation).
  @Test("a shortcut keeps the geometry panel's other values", .scratchDirectory)
  func testShortcutKeepsValues() throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(opened, bundle: Self.bundle())
    workspace.choose(GeometryProcess.id)
    let panel = try #require(workspace.panel)
    panel.set("cropLeft", .number(2))
    workspace.moveGeometry(.rotateClockwise)
    #expect(workspace.panel === panel, "the same panel")
    #expect(panel.params.number("cropLeft") == 2 && panel.params.choice("rotation") == "90")
  }
}

import AstroStackApp
import Foundation
import Metal
import ProcessKit
import TestSupport
import Testing

/// The panel's slider ranges (card 0104): a process sizes a slider from the head (the crops), the
/// schema bounds stay the validation bounds, and a typed value is never clamped to the slider.
@MainActor
@Suite("ProcessPanelModel — slider ranges from the head")
struct ProcessPanelModelTests {
  static func spec(_ type: any ImageProcess.Type, _ id: String) throws -> ParamSpec {
    try #require(type.schema.specs.first { $0.id == id })
  }

  @Test(
    "testRangeFollowsTheHead: the crop sliders span the head, a crop applied shrinks them",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testRangeFollowsTheHead() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let left = try Self.spec(GeometryProcess.self, "cropLeft")
    let top = try Self.spec(GeometryProcess.self, "cropTop")
    workspace.choose(GeometryProcess.id)
    let panel = try #require(workspace.panel)
    #expect(panel.range(for: left) == 0...7)
    #expect(panel.range(for: top) == 0...7)

    panel.set("cropLeft", .number(3))
    panel.set("cropBottom", .number(2))
    await workspace.previewNow()
    try workspace.apply()

    #expect(workspace.studio.head.width == 5 && workspace.studio.head.height == 6)
    #expect(panel.range(for: left) == 0...4)
    #expect(panel.range(for: top) == 0...5)
  }

  @Test(
    "a process without display ranges keeps its schema bounds on any head",
    arguments: try ProcessRegistry.standard().ids)
  func testSchemaBoundsWithoutDisplayRange(processID: String) throws {
    let type = try #require(try ProcessRegistry.standard().type(id: processID))
    let model = ProcessPanelModel(type: type, params: ParamSet(schema: type.schema))
    model.headSize = (width: 8, height: 8)
    let displayed = type.displayRanges(width: 8, height: 8)

    for spec in type.schema.specs where displayed[spec.id] == nil {
      guard case .number(_, let bounds) = spec.kind else {
        #expect(model.range(for: spec) == nil, "\(spec.id) has no slider")
        continue
      }
      #expect(model.range(for: spec) == bounds, "\(spec.id)")
    }
  }

  @Test("testTypedValueWidensTheRange: a crop typed past the image is kept and the slider holds it")
  func testTypedValueWidensTheRange() throws {
    let model = ProcessPanelModel(
      type: GeometryProcess.self, params: ParamSet(schema: GeometryProcess.schema))
    model.headSize = (width: 8, height: 6)
    let left = try Self.spec(GeometryProcess.self, "cropLeft")

    model.set("cropLeft", .number(20))

    #expect(model.params.number("cropLeft") == 20, "kept as typed, never clamped to the image")
    #expect(model.range(for: left) == 0...20)
  }

  @Test("a 1-pixel side leaves the crop slider no travel: it keeps the schema bounds")
  func testOnePixelSideKeepsSchemaBounds() throws {
    let model = ProcessPanelModel(
      type: GeometryProcess.self, params: ParamSet(schema: GeometryProcess.schema))
    model.headSize = (width: 1, height: 6)

    #expect(model.range(for: try Self.spec(GeometryProcess.self, "cropLeft")) == 0...100_000)
    #expect(model.range(for: try Self.spec(GeometryProcess.self, "cropTop")) == 0...5)
  }
}

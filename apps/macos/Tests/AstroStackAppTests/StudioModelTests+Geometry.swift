import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import RenderKit
import TestSupport
import Testing

extension StudioModelTests {
  /// One table row: the viewer's zoom, a drag in view pixels, and the crop it gives.
  struct RegionCase: Sendable, CustomTestStringConvertible {
    let name: String
    let transform: ViewTransform
    let from: SIMD2<Double>
    let to: SIMD2<Double>
    /// Left, top, right, bottom on the 8 × 8 head.
    let crop: [Double]
    var testDescription: String { name }
  }

  nonisolated static let regionCases: [RegionCase] = [
    RegionCase(
      name: "zoomed in 2×", transform: ViewTransform(scale: 0.5, origin: [0, 0]), from: [2, 4],
      to: [8, 10], crop: [1, 2, 4, 3]),
    RegionCase(
      name: "zoomed out 2×, panned", transform: ViewTransform(scale: 2, origin: [-4, -4]),
      from: [3, 4], to: [5, 6], crop: [2, 4, 2, 0]),
  ]

  /// Card 0090: the viewer's region becomes the four crops in image pixels at any zoom; the
  /// region is consumed, the preview shows the crop, nothing is applied until Apply — which
  /// moves the bundle layers with the image.
  @Test("testUseRegionFillsCrop", .scratchDirectory, arguments: regionCases)
  func testUseRegionFillsCrop(_ row: RegionCase) async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(opened, bundle: Self.bundle())
    workspace.choose(GeometryProcess.id)
    #expect(workspace.regionUnavailable == .noRegion)

    let viewer = workspace.viewer.model
    viewer.frame.transform = row.transform
    viewer.drag(from: row.from, to: row.to, tool: .region)
    #expect(workspace.regionUnavailable == nil)
    workspace.useRegion()

    let panel = try #require(workspace.panel)
    let crops = ["cropLeft", "cropTop", "cropRight", "cropBottom"].map(panel.params.number)
    #expect(crops == row.crop)
    #expect(viewer.frame.region == nil, "the region is consumed")
    #expect(workspace.studio.steps.count == 1, "nothing applied before Apply")
    await workspace.previewNow()
    let (width, height) = (8 - Int(row.crop[0] + row.crop[2]), 8 - Int(row.crop[1] + row.crop[3]))
    #expect(viewer.image.width == width && viewer.image.height == height)
    #expect(workspace.geometryOutput == GeometryOutput(width: width, height: height, wcs: .none))

    try workspace.apply()
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination", "geometry"])
    #expect(workspace.studio.head.width == width && workspace.studio.head.height == height)
    let rgb = try #require(try workspace.studio.session.history.bundleLayers()["RGB"])
    #expect(rgb.width == width && rgb.height == height, "the bundle layer follows")
  }

  @Test(
    "Use region needs the geometry panel, a region, and the head's frame on screen",
    .scratchDirectory)
  func testUseRegionAvailability() async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(opened, bundle: Self.bundle())
    workspace.choose(StretchProcess.id)
    #expect(workspace.regionUnavailable == .notGeometry && workspace.geometryOutput == nil)

    workspace.choose(GeometryProcess.id)
    let panel = try #require(workspace.panel)
    panel.set("cropLeft", .number(2))
    panel.set("angle", .number(5))
    await workspace.previewNow()
    workspace.viewer.model.frame.transform = ViewTransform(scale: 1, origin: [0, 0])
    workspace.viewer.model.drag(from: [0, 0], to: [3, 3], tool: .region)
    // The preview (6 × 8) is on screen: a region drawn on it is not in the head's pixels.
    #expect(workspace.regionUnavailable == .previewMoved)
    #expect(workspace.geometryOutput == GeometryOutput(width: 6, height: 8, wcs: .none))
    #expect(GeometryProcess.removesWCS(panel.params))
  }
}

extension StudioModelTests {
  /// Review of card 0090: a same-size move (a flip) is still a moved preview for « Use region »;
  /// applying or undoing a geometric step drops the region (another process keeps it); compare
  /// refuses a step of another size and stops when a crop makes the compared step misfit.
  @Test("same-size moves: Use region refused, region dropped, compare refused", .scratchDirectory)
  func testSameSizeMovesAndCompare() async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(opened, bundle: Self.bundle())
    let viewer = workspace.viewer.model
    viewer.frame.transform = ViewTransform(scale: 1, origin: [0, 0])

    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    viewer.drag(from: [1, 1], to: [4, 4], tool: .region)
    try workspace.apply()
    #expect(viewer.frame.region != nil, "a process that moves nothing keeps the region")

    workspace.choose(GeometryProcess.id)
    try #require(workspace.panel).set("flipV", .flag(true))
    await workspace.previewNow()
    #expect(viewer.frame.region == nil, "the flipped preview drops the head's region")
    viewer.drag(from: [1, 1], to: [4, 4], tool: .region)
    #expect(workspace.regionUnavailable == .previewMoved, "a flip moves pixels at the same size")
    try workspace.apply()
    #expect(viewer.frame.region == nil, "the flip's head drops the region")
    viewer.drag(from: [1, 1], to: [4, 4], tool: .region)
    try workspace.undo()
    #expect(viewer.frame.region == nil, "undoing the flip drops it too")
    try workspace.redo()

    try workspace.compare(toStep: 1)
    let panel = try #require(workspace.panel)
    panel.set("flipV", .flag(false))
    panel.set("cropLeft", .number(2))
    await workspace.previewNow()
    try workspace.apply()
    #expect(workspace.comparing == nil, "the compared step no longer fits the head")
    #expect(throws: StudioError.otherSize(step: 1)) { try workspace.compare(toStep: 1) }
  }
}

extension StudioModelTests {
  /// Second review of card 0090: a region drawn on the head survives opening geometry (its
  /// identity preview); one drawn on a moved preview is dropped when the grid changes back; a
  /// compare stops when a geometry preview changes the size shown.
  @Test("previews that move the grid drop the region and stop a misfit compare", .scratchDirectory)
  func testPreviewMovesDropRegionAndCompare() async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(opened, bundle: Self.bundle())
    let viewer = workspace.viewer.model
    viewer.frame.transform = ViewTransform(scale: 1, origin: [0, 0])
    viewer.drag(from: [1, 1], to: [4, 4], tool: .region)
    workspace.choose(GeometryProcess.id)
    await workspace.previewNow()
    #expect(viewer.frame.region != nil, "the identity preview keeps the head's region")

    let panel = try #require(workspace.panel)
    panel.set("flipH", .flag(true))
    await workspace.previewNow()
    #expect(viewer.frame.region == nil, "the flipped preview moved the pixels under it")
    viewer.drag(from: [1, 1], to: [4, 4], tool: .region)
    panel.set("flipH", .flag(false))
    await workspace.previewNow()
    #expect(viewer.frame.region == nil, "back to the head's grid: the flipped region goes")

    try workspace.compare(toStep: 0)
    panel.set("cropTop", .number(3))
    await workspace.previewNow()
    #expect(workspace.comparing == nil, "a cropped preview no longer fits step 1")
  }
}

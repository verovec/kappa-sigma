import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// The Studio's base layer and roles on any bundle (card 0137): `RGB`, else `L`, else the first
/// filter in the canonical order; a single mono layer combined into three planes is a colour image.
@Suite("StudioSession — the base layer and the roles of a mono bundle")
struct StudioSessionTests {
  @Test(
    "the base layer: RGB, else L, else the first filter in the canonical order",
    arguments: [
      (["Ha", "RGB"], "RGB"), (["B", "G", "L", "R"], "L"), (["B", "G", "R"], "R"),
      (["OIII", "Ha"], "Ha"), (["Ha", "L"], "L"), (["NII-custom", "Ha"], "Ha"),
      (["Zed", "Alpha"], "Alpha"),
    ] as [([String], String)])
  func testBaseLayerID(ids: [String], expected: String) {
    #expect(StudioSession.baseLayerID(ids) == expected)
    #expect(StudioSession.baseLayerID(ids.reversed()) == expected)
  }

  @Test("an empty bundle has no base layer")
  func testBaseLayerID_empty() {
    #expect(StudioSession.baseLayerID([String]()) == nil)
  }

  @Test(
    "a mono layer combined into three planes offers the colour processes",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil), .scratchDirectory)
  func testPresentRoles_colourAfterReplacingStep() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let lum = AstroImage(
      width: 4, height: 2, planes: [[Float](repeating: 0.2, count: 8)],
      metadata: ImageMetadata(rowOrder: .topDown))
    let stats = StudioSession.stats(of: lum)
    let bundle = PipelineBundle(stats: stats, layers: ["L": lum], layerStats: ["L": stats])
    let history = try History(directory: try ScratchDirectory.url, original: lum)
    let session = try StudioSession(
      history: history, bundle: bundle,
      registry: ProcessRegistry([ChannelCombinationProcess.self]), device: device)
    #expect(session.presentRoles(base: [.luminance]) == [.luminance])

    var grey = ParamSet(schema: ChannelCombinationProcess.schema)
    for slot in ["rSource", "gSource", "bSource"] { try grey.set(slot, .choice("L")) }
    try session.apply(ChannelCombinationProcess.id, params: grey)

    #expect(history.current.planes.count == 3)
    #expect(session.presentRoles(base: [.luminance]) == [.luminance, .color])
  }
}

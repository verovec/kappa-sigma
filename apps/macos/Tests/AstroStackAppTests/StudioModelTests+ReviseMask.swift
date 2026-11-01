import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Card 0160: a step applied under a mask keeps its mask, so a revise replays it under the same
/// pixels — the head equals the chain applied by hand with that mask (R2: values applied = shown).
extension StudioModelTests {
  /// A mask over `image`: the left half let through, the right half held back.
  static func halfMask(over image: AstroImage) -> AstroImage {
    let plane = (0..<(image.width * image.height)).map {
      Float($0 % image.width < image.width / 2 ? 1 : 0)
    }
    return AstroImage(
      width: image.width, height: image.height, planes: [plane], metadata: image.metadata)
  }

  @Test("testReviseStep_ReplaysMaskedStepWithItsMask", .scratchDirectory)
  func testReviseStep_ReplaysMaskedStepWithItsMask() async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let studio = try Self.model(opened)
    let mask = Self.halfMask(over: studio.head)
    let masked = try Self.stretch(target: 0.35)
    let saturation = ParamSet(schema: SaturationProcess.schema)
    try studio.apply(StretchProcess.id, params: try Self.stretch(target: 0.2))
    try studio.apply(StretchProcess.id, params: masked, mask: mask)
    try studio.apply(SaturationProcess.id, params: saturation)
    let revised = try Self.stretch(target: 0.3)

    try await studio.reviseStep(1, params: revised)

    #expect(studio.steps[2].mask != nil, "the replayed step keeps its mask")
    #expect(try studio.session.history.mask(ofStep: 2)?.planes == mask.planes)
    let head = studio.head.planes

    // The same chain by hand: under the mask it matches, unmasked it does not.
    try studio.undo(steps: 3)
    try studio.apply(StretchProcess.id, params: revised)
    try studio.apply(StretchProcess.id, params: masked, mask: mask)
    try studio.apply(SaturationProcess.id, params: saturation)
    #expect(studio.head.planes == head)
    try studio.undo(steps: 2)
    try studio.apply(StretchProcess.id, params: masked)
    try studio.apply(SaturationProcess.id, params: saturation)
    #expect(studio.head.planes != head, "the mask changes the pixels: the test can tell")
  }

  @Test(
    "revising a crop, turn or flip before a masked step is refused before anything moves",
    .scratchDirectory)
  func testReviseStep_GeometryBeforeMaskedStep_Refused() async throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let studio = try Self.model(opened)
    var flipped = ParamSet(schema: GeometryProcess.schema)
    try flipped.set("flipH", .flag(true))
    try studio.apply(GeometryProcess.id, params: flipped)
    try studio.apply(StretchProcess.id, params: try Self.stretch(target: 0.3))
    try studio.apply(
      StretchProcess.id, params: try Self.stretch(target: 0.35),
      mask: Self.halfMask(over: studio.head))
    let before = studio.steps

    await #expect(throws: PipelineError.maskMoved(step: 3)) {
      try await studio.reviseStep(1, params: ParamSet(schema: GeometryProcess.schema))
    }
    #expect(studio.steps == before && studio.session.history.versions.isEmpty)

    // A step after the geometry moves nothing under the mask: revised as usual.
    try await studio.reviseStep(2, params: try Self.stretch(target: 0.25))
    #expect(studio.steps[3].mask != nil)
  }
}

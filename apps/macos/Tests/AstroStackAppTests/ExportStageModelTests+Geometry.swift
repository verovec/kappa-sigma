import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

extension ExportStageModelTests {
  /// Card 0090: a geometry step moves the starless with the image — it is neither a new
  /// starless nor a step the starless lacks.
  @Test("a geometry step after StarNet is not counted after the starless", .scratchDirectory)
  func testGeometryIsNotAfterStarless() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try Self.separated(opened)
    let model = try Self.model(opened, studio: studio, services: try Self.services())
    try studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    var crop = ParamSet(schema: GeometryProcess.schema)
    try crop.set("cropLeft", .number(1))
    try studio.apply(GeometryProcess.id, params: crop)
    #expect(studio.steps.last?.outputs[.starless] != nil, "the crop moved the starless")
    #expect(model.stepsAfterStarless == 1, "only the stretch is missing from the starless")
  }
}

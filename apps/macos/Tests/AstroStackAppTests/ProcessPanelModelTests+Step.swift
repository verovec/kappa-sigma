import AstroStackApp
import ProcessKit
import RenderKit
import Testing

/// A process row's arrow step (card 0179): whole numbers by one, ⇧ too; a declared step as
/// declared; none, and the row takes a decade of its range.
extension ProcessPanelModelTests {
  @Test(
    "the panel gives each parameter the step its process declares",
    arguments: [
      ("geometry", "cropLeft", ParameterStep.wholeNumber),
      ("geometry", "angle", ParameterStep(0.1)),
      ("hdr", "kneeAboveSky", ParameterStep(0.0001)),
      ("hdr", "openRadius", ParameterStep.wholeNumber),
      ("sky-desat", "coreGuardPx", ParameterStep.wholeNumber),
      ("background-extraction", "samples", ParameterStep.wholeNumber),
    ] as [(String, String, ParameterStep)])
  func testStepFollowsTheProcess(process: String, id: String, step: ParameterStep) throws {
    let type = try #require(try ProcessRegistry.standard().type(id: process))
    let panel = ProcessPanelModel(type: type, params: ParamSet(schema: type.schema))
    #expect(panel.step(for: id) == step)
  }

  @Test("a parameter its process gives no step leaves the row to its range's decade")
  func testUndeclaredStepIsNil() throws {
    let type = try #require(try ProcessRegistry.standard().type(id: "hdr"))
    let panel = ProcessPanelModel(type: type, params: ParamSet(schema: type.schema))
    #expect(panel.step(for: "sigma") == nil)
  }
}

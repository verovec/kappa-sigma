import AstroStackApp
import RenderKit
import Testing

/// The mask rows' arrow steps (card 0179): the pixel radii are whole pixels, as `MaskBuilder`
/// reads them; the others take their range's decade.
@Suite("StudioMaskRow steps — pixel radii by whole pixels")
struct StudioMaskRowStepTests {
  @Test(
    "radius and feather step by whole pixels; the others take the row default",
    arguments: StudioMaskRow.Field.allCases)
  func testSteps(field: StudioMaskRow.Field) {
    let whole = field == .radius || field == .feather
    #expect(StudioMaskRow.step(field) == (whole ? .wholeNumber : nil))
  }
}

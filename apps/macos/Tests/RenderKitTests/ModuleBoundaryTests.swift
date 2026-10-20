import TestSupport
import Testing

@Suite("RenderKit stays inside its module boundary")
struct ModuleBoundaryTests {
  @Test("RenderKit dependencies and imports match the allow-list")
  func testModuleBoundary() throws {
    let violations = try ModuleBoundary.check(module: "RenderKit")
    #expect(violations == [])
  }
}

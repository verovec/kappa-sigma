import TestSupport
import Testing

@Suite("AstroStackApp stays inside its module boundary")
struct ModuleBoundaryTests {
  @Test("AstroStackApp dependencies and imports match the allow-list")
  func testModuleBoundary() throws {
    let violations = try ModuleBoundary.check(module: "AstroStackApp")
    #expect(violations == [])
  }
}

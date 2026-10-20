import TestSupport
import Testing

@Suite("ProjectKit stays inside its module boundary")
struct ModuleBoundaryTests {
  @Test("ProjectKit dependencies and imports match the allow-list")
  func testModuleBoundary() throws {
    let violations = try ModuleBoundary.check(module: "ProjectKit")
    #expect(violations == [])
  }
}

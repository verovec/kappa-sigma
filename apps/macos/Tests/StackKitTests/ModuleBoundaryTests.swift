import TestSupport
import Testing

@Suite("StackKit stays inside its module boundary")
struct ModuleBoundaryTests {
  @Test("StackKit dependencies and imports match the allow-list")
  func testModuleBoundary() throws {
    let violations = try ModuleBoundary.check(module: "StackKit")
    #expect(violations == [])
  }
}

import TestSupport
import Testing

@Suite("ProcessKit stays inside its module boundary")
struct ModuleBoundaryTests {
  @Test("ProcessKit dependencies and imports match the allow-list")
  func testModuleBoundary() throws {
    let violations = try ModuleBoundary.check(module: "ProcessKit")
    #expect(violations == [])
  }
}

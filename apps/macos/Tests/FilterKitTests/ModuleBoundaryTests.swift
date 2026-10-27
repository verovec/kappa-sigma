import TestSupport
import Testing

@Suite("FilterKit stays inside its module boundary")
struct ModuleBoundaryTests {
  @Test("FilterKit dependencies and imports match the allow-list")
  func testModuleBoundary() throws {
    let violations = try ModuleBoundary.check(module: "FilterKit")
    #expect(violations == [])
  }
}

import TestSupport
import Testing

@Suite("ImageKit stays inside its module boundary")
struct ModuleBoundaryTests {
  @Test("ImageKit dependencies and imports match the allow-list")
  func testModuleBoundary() throws {
    let violations = try ModuleBoundary.check(module: "ImageKit")
    #expect(violations == [])
  }
}

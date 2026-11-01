import TestSupport
import Testing

@Suite("RemoteKit stays inside its module boundary")
struct ModuleBoundaryTests {
  @Test("RemoteKit dependencies and imports match the allow-list")
  func testModuleBoundary() throws {
    let violations = try ModuleBoundary.check(module: "RemoteKit")
    #expect(violations == [])
  }
}

import TestSupport
import Testing

@Suite("StringCatalog stays inside its module boundary")
struct ModuleBoundaryTests {
  @Test("StringCatalog dependencies and imports match the allow-list")
  func testModuleBoundary() throws {
    let violations = try ModuleBoundary.check(module: "StringCatalog")
    #expect(violations == [])
  }
}

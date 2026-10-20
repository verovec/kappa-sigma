import Foundation
import ImageKit
import TestSupport
import Testing

@Suite("KitBundle: a kit's resources in the packaged app first, Bundle.module otherwise")
struct KitBundleTests {
  @Test(
    "a bundle present in Contents/Resources wins, without touching the fallback",
    .scratchDirectory)
  func testKitBundle_resolve_packaged() throws {
    let resources = try ScratchDirectory.url
    let name = "AstroStack_Test.bundle"
    try FileManager.default.createDirectory(
      at: resources.appendingPathComponent(name), withIntermediateDirectories: true)
    let bundle = KitBundle.resolve(named: name, resources: resources) {
      Issue.record("fallback evaluated although the packaged bundle exists")
      return Bundle.main
    }
    #expect(bundle.bundleURL.lastPathComponent == name)
  }

  @Test("without a packaged bundle the fallback is used", .scratchDirectory)
  func testKitBundle_resolve_fallback() throws {
    let resources = try ScratchDirectory.url
    let bundle = KitBundle.resolve(named: "AstroStack_Missing.bundle", resources: resources) {
      Bundle.main
    }
    #expect(bundle == Bundle.main)
    #expect(KitBundle.resolve(named: "x", resources: nil) { Bundle.main } == Bundle.main)
  }
}

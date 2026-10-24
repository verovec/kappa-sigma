import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0101: a project package saved in a capture folder held a run's stacks (no OBJECT); the
/// scan read them as lights and the run was refused as « mixed objects ». A package is never
/// captures: the scan skips it and says so.
extension InventoryBuilderTests {
  @Test(
    "a .astrostack package or any other package is skipped, its FITS absent, listed as skipped",
    .scratchDirectory)
  func testSkipsPackages() throws {
    let dir = try InventoryBuilderFallbackTests.folder("IC1848")
    let light = Self.asi("'Light Frame'", filter: "'L'", exptime: "120.0")
    try TestFITS.write("lights/l_1.fits", in: dir, pixel: 900, cards: light)
    try TestFITS.write("lights/l_2.fits", in: dir, pixel: 950, cards: light)
    // A run's stack: no IMAGETYP, no OBJECT — what 0058 found in captures/IC1848.
    try TestFITS.write(
      "test-build.astrostack/stacks/20261021/combined.fits", in: dir, pixel: 1200,
      cards: ["EXPTIME": "120.0"])
    try TestFITS.write(
      "Viewer.app/Contents/Resources/sample.fits", in: dir, pixel: 1200, cards: light)

    let inventory = try Self.scan(dir)

    #expect(inventory.frames.map { InventoryBuilderTests.name($0) } == ["l_1.fits", "l_2.fits"])
    #expect(Set(inventory.frames.map(\.object)) == ["M31"], "one object: the run can start")
    #expect(
      Self.skipWarnings(inventory)
        == ["Viewer.app", "test-build.astrostack"].map(Inventory.skipWarning))
  }

  @Test(
    "a package picked as the root is skipped too; nested roots name a package once",
    .scratchDirectory)
  func testSkipsPackageRootsOnce() throws {
    let dir = try InventoryBuilderFallbackTests.folder("IC1848")
    let light = Self.asi("'Light Frame'", filter: "'L'", exptime: "120.0")
    try TestFITS.write("lights/l_1.fits", in: dir, pixel: 900, cards: light)
    try TestFITS.write(
      "lights/old.astrostack/stacks/1/combined.fits", in: dir, pixel: 1200,
      cards: ["EXPTIME": "120.0"])
    let package = dir.appendingPathComponent("lights/old.astrostack")

    let alone = try Self.builder.scan(paths: [package.path])
    let nested = try Self.builder.scan(
      paths: [dir.path, dir.appendingPathComponent("lights").path])

    #expect(alone.frames.isEmpty, "a project's stacks are never lights")
    #expect(Self.skipWarnings(alone) == [Inventory.skipWarning(package.path)])
    #expect(Self.skipWarnings(nested).count == 1, "\(nested.warnings)")
  }

  @Test("a folder merely named like a package is read, nothing skipped", .scratchDirectory)
  func testSkipsNothingWithoutPackages() throws {
    let dir = try InventoryBuilderFallbackTests.folder("plain")
    try TestFITS.write(
      "pack.astrostack.d/l_1.fits", in: dir, pixel: 900,
      cards: Self.asi("'Light Frame'", filter: "'L'", exptime: "120.0"))

    let inventory = try Self.scan(dir)

    #expect(inventory.frames.count == 1, "a folder merely named like a package is read")
    #expect(Self.skipWarnings(inventory).isEmpty)
  }

  static func skipWarnings(_ inventory: Inventory) -> [String] {
    inventory.warnings.filter { $0.hasPrefix("skip ") && $0.hasSuffix("never read as captures") }
  }

  static func name(_ frame: CaptureFrame) -> String {
    (frame.path as NSString).lastPathComponent
  }
}

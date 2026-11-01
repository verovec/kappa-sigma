import Foundation
import StackKit
import TestSupport
import Testing

/// A mono night as users lay it out: one folder per filter under the import root, darks imported
/// afterwards from somewhere else; capture software writing `°` in a header comment.
extension InventoryBuilderTests {
  /// `relative` written by `TestFITS`, then every `@` in its header replaced by a Latin-1 `°`.
  static func writeWithDegree(_ relative: String, in dir: URL, cards: [String: String]) throws {
    let url = try TestFITS.write(relative, in: dir, pixel: 900, cards: cards)
    var data = try Data(contentsOf: url)
    for index in data.indices.prefix(2880) where data[index] == UInt8(ascii: "@") {
      data[index] = 0xB0
    }
    try data.write(to: url)
  }

  @Test(
    "src/L, src/Ha, src/B + a darks folder elsewhere: three filters, darks matched, no skip",
    .scratchDirectory)
  func testMonoFilterFoldersWithSeparateDarks() throws {
    let src = try InventoryBuilderFallbackTests.folder("src")
    let darks = try InventoryBuilderFallbackTests.folder("darks")
    // No FILTER card: the folder names the filter, as on the user's B/ and Ha/ frames.
    var light = Self.asi("'Light'", exptime: "15.0")
    light["CCD-TEMP"] = "-15.0 / sensor temperature in @C"
    for filter in ["L", "Ha", "B"] {
      for index in 1...2 {
        try Self.writeWithDegree("\(filter)/Light_\(filter)_\(index).fit", in: src, cards: light)
      }
    }
    try TestFITS.write(
      "dark_1.fit", in: darks, pixel: 600, cards: Self.asi("'Dark'", exptime: "15.0"))
    // macOS AppleDouble companions on exFAT/SMB volumes: binary, never frames.
    try Data([0x00, 0x05, 0x16, 0x07, 0xB0, 0xFF]).write(
      to: src.appendingPathComponent("B/._Light_B_1.fit"))

    let inventory = try Self.builder.scan(paths: [src.path, darks.path])

    #expect(!inventory.warnings.contains { $0.hasPrefix("skip ") }, "\(inventory.warnings)")
    #expect(inventory.countsByType == [.light: 6, .dark: 1])
    #expect(Set(inventory.frames.filter { $0.type == .light }.map(\.filter)) == ["L", "Ha", "B"])
  }

  @Test("an AppleDouble ._ file is not a FITS frame, whatever its extension")
  func testAppleDoubleIsNotFITS() {
    #expect(!InventoryBuilder.isFITS("/v/B/._Light_B_1.fit"))
    #expect(InventoryBuilder.isFITS("/v/B/Light_B_1.fit"))
    #expect(InventoryBuilder.isFITS("/v/B/_Light.fits"))
  }
}

import Foundation
import ImageKit
import TestSupport
import Testing

@Suite("ImageImport: a 16-bit PNG or TIFF read back as float planes, top row first")
struct ImageImportTests {
  /// A 3 × 2 ramp: every sample a distinct multiple of 1/65535.
  static func ramp(planes: Int) -> AstroImage {
    let values = (0..<planes).map { plane in
      (0..<6).map { Float($0 * 9_000 + plane * 1_000) / 65535 }
    }
    return AstroImage(
      width: 3, height: 2, planes: values, metadata: ImageMetadata(rowOrder: .topDown))
  }

  @Test(
    "what ImageExport writes reads back exactly, in RGB and gray, PNG and TIFF",
    .scratchDirectory,
    arguments: [(ImageExport.Format.png16, 3), (.tiff16, 3), (.png16, 1), (.tiff16, 1)])
  func testRoundTrip(format: ImageExport.Format, planes: Int) throws {
    let image = Self.ramp(planes: planes)
    let url = try ScratchDirectory.url.appendingPathComponent("ramp.\(format.fileExtension)")
    try ImageExport.write(image, to: url, format: format)
    let read = try ImageImport.read(at: url)
    #expect(read.width == 3 && read.height == 2 && read.metadata.rowOrder == .topDown)
    #expect(read.planes == image.planes)
  }

  @Test("a file that is not an image is refused with its path", .scratchDirectory)
  func testUnreadable() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("not.png")
    try Data("text".utf8).write(to: url)
    #expect(throws: ImageImport.ImportError.unreadable(path: url.path)) {
      try ImageImport.read(at: url)
    }
  }
}

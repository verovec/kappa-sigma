import CoreGraphics
import Foundation
import ImageIO
import ImageKit
import TestSupport
import Testing

@Suite("ImageExport: 16-bit TIFF/PNG for deliverables, top row first")
struct ImageExportTests {
  static func metadata(_ rowOrder: RowOrder) throws -> ImageMetadata {
    var metadata = try FITSFile.parse(FITSBytes.float32(width: 1, height: 1, planes: [[0]]))
      .image().metadata
    metadata.rowOrder = rowOrder
    return metadata
  }

  /// The 16-bit samples of the exported file, top row first, channels interleaved.
  static func samples(of url: URL) throws -> (CGImage, [UInt16]) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let data = try #require(image.dataProvider?.data as Data?)
    let littleEndian = image.bitmapInfo.contains(.byteOrder16Little)
    let values = stride(from: 0, to: data.count - 1, by: 2).map { offset -> UInt16 in
      let pair = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
      return littleEndian ? pair : pair.byteSwapped
    }
    return (image, values)
  }

  @Test(
    "RGB and mono export at 16 bits; values clamp to [0, 1]; bottom-up rows are flipped",
    .scratchDirectory,
    arguments: [ImageExport.Format.tiff16, .png16])
  func testImageExport_write(_ format: ImageExport.Format) throws {
    // 1 × 2 image: row 0 = 0.5 everywhere, row 1 = 2.0 (clamps to 1) / −1 (clamps to 0).
    let image = AstroImage(
      width: 1, height: 2, planes: [[0.5, 2], [0.5, -1], [0.5, 2]],
      metadata: try Self.metadata(.bottomUp))
    let url = try ScratchDirectory.url.appendingPathComponent("out.\(format.fileExtension)")
    try ImageExport.write(image, to: url, format: format)

    let (exported, values) = try Self.samples(of: url)
    #expect(exported.width == 1 && exported.height == 2)
    #expect(exported.bitsPerComponent == 16)
    let rowBytes = exported.bytesPerRow / 2
    // Bottom-up: file row 1 is the top of the frame, so it comes first in the export.
    #expect(Array(values[0..<3]) == [65535, 0, 65535])
    #expect(Array(values[rowBytes..<rowBytes + 3]) == [32768, 32768, 32768])
  }

  @Test(
    "a mono image exports one gamma-encoded 16-bit channel; NaN exports as 0",
    .scratchDirectory)
  func testImageExport_mono() throws {
    let image = AstroImage(
      width: 3, height: 1, planes: [[0, 1, .nan]], metadata: try Self.metadata(.topDown))
    let url = try ScratchDirectory.url.appendingPathComponent("mono.tif")
    try ImageExport.write(image, to: url, format: .tiff16)
    let (exported, values) = try Self.samples(of: url)
    #expect(exported.bitsPerPixel == 16)
    #expect(Array(values[0..<3]) == [0, 65535, 0])
    #expect(exported.colorSpace?.name != CGColorSpace.linearGray, "display-referred, not linear")
  }

  @Test("planes that do not match the dimensions are refused", .scratchDirectory)
  func testImageExport_rejectsShortPlane() throws {
    let image = AstroImage(
      width: 2, height: 2, planes: [[0, 1, 1]], metadata: try Self.metadata(.topDown))
    let url = try ScratchDirectory.url.appendingPathComponent("short.png")
    #expect(throws: ImageExport.ExportError.planeSizeMismatch) {
      try ImageExport.write(image, to: url, format: .png16)
    }
  }
}

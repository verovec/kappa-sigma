import CoreGraphics
import Foundation
import ImageIO
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

@Suite("Deliverable export: the legacy set, its formats, crop and mirror, never into a source")
struct ExportTests {
  /// A 3 × 2 image whose every sample is distinct: (plane, row, column) → value.
  static func image(offset: Float = 0) -> AstroImage {
    let planes = (0..<3).map { plane in
      (0..<6).map { Float(plane * 6 + $0) / 32 + offset }
    }
    return AstroImage(
      width: 3, height: 2, planes: planes, metadata: ImageMetadata(rowOrder: .topDown))
  }

  @Test(
    "the crop and the mirror move columns and rows as the 3 × 2 oracle says",
    arguments: [
      (ExportSettings.Orientation.none, [0, 1, 2, 3, 4, 5]), (.hflip, [2, 1, 0, 5, 4, 3]),
      (.vflip, [3, 4, 5, 0, 1, 2]),
    ])
  func testOrientation(orientation: ExportSettings.Orientation, order: [Int]) throws {
    var settings = ExportSettings()
    settings.orientation = orientation
    let image = Self.image()
    let shaped = try DeliverableExport.shape(image, settings: settings)
    let expected: [[Float]] = image.planes.map { plane in order.map { plane[$0] } }
    #expect(shaped.planes == expected)
  }

  @Test("a crop fraction trims each edge by the rounded fraction; one that leaves nothing fails")
  func testCrop() throws {
    let wide = AstroImage(
      width: 10, height: 4, planes: Array(repeating: (0..<40).map(Float.init), count: 3),
      metadata: ImageMetadata(rowOrder: .topDown))
    var settings = ExportSettings()
    settings.cropFraction = 0.12
    let cropped = try DeliverableExport.shape(wide, settings: settings)
    #expect(cropped.width == 8 && cropped.height == 4)
    let firstRow: [Float] = (1..<9).map(Float.init)
    #expect(Array(cropped.planes[0].prefix(8)) == firstRow)
    settings.cropFraction = 0.5
    #expect(throws: DeliverableExport.ExportError.cropTooLarge(0.5)) {
      try DeliverableExport.shape(wide, settings: settings)
    }
  }

  @Test(
    "five files with the legacy names; PNG16 and TIFF16 at 16 bits; FITS32 reads back",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testDeliverableSetNamesAndFormats() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let folder = try ScratchDirectory.url.appendingPathComponent("export")
    var settings = ExportSettings()
    settings.formats = [.png16, .tiff16, .fits32]
    let starless = Self.image()
    let written = try DeliverableExport(device: device).write(
      original: Self.image(offset: 0.1), starless: starless, settings: settings, to: folder,
      astro: try ScratchDirectory.url)
    let names = ["final", "final-starless", "final-75-stars", "final-50-stars", "final-25-stars"]
    let expected: [String] = names.flatMap { name in
      ["png", "tif", "fits"].map { "\(name).\($0)" }
    }
    #expect(written.map(\.lastPathComponent) == expected)
    for url in written where url.pathExtension != "fits" {
      let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
      let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
      #expect(image.bitsPerComponent == 16, "\(url.lastPathComponent)")
    }
    let fits = try FITSFile.read(at: folder.appendingPathComponent("final-starless.fits")).image()
    #expect(fits.planes == starless.planes && fits.metadata.rowOrder == .topDown)
  }

  @Test(
    "an export into the captures or the runs is refused before anything is written",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil),
    arguments: ["runs/M_31/20261018_191749", "captures/M31"])
  func testNeverWritesIntoOutputOrInput(relative: String) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let astro = try ScratchDirectory.url
    let folder = astro.appendingPathComponent(relative).appendingPathComponent("export")
    #expect {
      try DeliverableExport(device: device).write(
        original: Self.image(), starless: Self.image(), settings: ExportSettings(), to: folder,
        astro: astro)
    } throws: { error in
      guard case DeliverableExport.ExportError.readOnlyTarget(let reason) = error else {
        return false
      }
      return reason.contains("never writes")
    }
    #expect(!FileManager.default.fileExists(atPath: folder.path))
  }

  @Test("a folder that reaches the runs through a link is refused too", .scratchDirectory)
  func testRefusesThroughLink() throws {
    let astro = try ScratchDirectory.url
    let runs = astro.appendingPathComponent("runs")
    try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
    let link = astro.appendingPathComponent("deliverables")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: runs)
    #expect(ExportGuard.refusal(for: link.appendingPathComponent("M31"), astro: astro) != nil)
    #expect(
      ExportGuard.refusal(for: astro.appendingPathComponent("elsewhere"), astro: astro) == nil)
  }
}

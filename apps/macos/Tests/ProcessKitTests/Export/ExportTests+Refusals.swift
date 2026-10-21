import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

extension ExportTests {
  static func settings(crop: Double = 0, template: String = "{name}") -> ExportSettings {
    var settings = ExportSettings()
    settings.cropFraction = crop
    settings.nameTemplate = template
    return settings
  }

  @Test(
    "a crop or a name template that cannot work is refused before any file",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil),
    arguments: [
      (Self.settings(crop: -0.01), DeliverableExport.ExportError.invalidCrop(-0.01)),
      (Self.settings(template: "../../captures/{name}"), .invalidTemplate("../../captures/{name}")),
      (Self.settings(template: "M31"), .invalidTemplate("M31")),
    ])
  func testInvalidSettings(settings: ExportSettings, error: DeliverableExport.ExportError) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let folder = try ScratchDirectory.url.appendingPathComponent("export")
    #expect(throws: error) {
      try DeliverableExport(device: device).write(
        original: Self.image(), starless: Self.image(), settings: settings, to: folder,
        home: try ScratchDirectory.url)
    }
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    var nan = settings
    nan.cropFraction = .nan
    #expect(throws: DeliverableExport.ExportError.self) {
      try DeliverableExport.shape(Self.image(), settings: nan)
    }
  }

  @Test(
    "an original and a starless in different row orders are refused",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testRowOrderMismatch() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let bottomUp = Self.image().inRowOrder(.bottomUp)
    #expect(throws: DeliverableExport.ExportError.rowOrderMismatch) {
      try DeliverableExport(device: device).write(
        original: bottomUp, starless: Self.image(), settings: ExportSettings(),
        to: try ScratchDirectory.url.appendingPathComponent("export"),
        home: try ScratchDirectory.url)
    }
  }

  @Test(
    "the library, the fixtures and a differently-cased captures folder are read-only too",
    .scratchDirectory,
    arguments: [
      "Documents/astro/library/darks", "Documents/astro/fixtures/finish",
      "Documents/Astro/Captures/M31",
    ])
  func testReadOnlyFolders(relative: String) throws {
    let home = try ScratchDirectory.url
    #expect(ExportGuard.refusal(for: home.appendingPathComponent(relative), home: home) != nil)
  }
}

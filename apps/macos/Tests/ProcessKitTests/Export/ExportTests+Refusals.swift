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
        astro: try ScratchDirectory.url)
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
        astro: try ScratchDirectory.url)
    }
  }

  @Test(
    "the library, the fixtures and a differently-cased captures folder are read-only too",
    .scratchDirectory,
    arguments: ["library/darks", "fixtures/finish", "Captures/M31"])
  func testReadOnlyFolders(relative: String) throws {
    let astro = try ScratchDirectory.url
    #expect(ExportGuard.refusal(for: astro.appendingPathComponent(relative), astro: astro) != nil)
  }

  @Test(
    "testRefusalFollowsAstroRoot: a moved root is refused, the old default no longer",
    .scratchDirectory)
  func testRefusalFollowsAstroRoot() throws {
    let base = try ScratchDirectory.url
    let moved = base.appendingPathComponent("Volumes/SSD/astro")
    #expect(
      ExportGuard.refusal(for: moved.appendingPathComponent("captures/M31"), astro: moved) != nil)
    let old = base.appendingPathComponent("home/Documents/astro/captures/M31")
    #expect(
      ExportGuard.refusal(for: old, astro: moved) == nil, "the old default is just a folder now")
    #expect(ExportGuard.readOnly == ["captures", "runs", "library", "fixtures"])
  }
}

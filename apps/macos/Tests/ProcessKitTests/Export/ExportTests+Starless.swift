import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// An image never separated (no StarNet on this Mac, card 0091): the final image only, as it is.
extension ExportTests {
  @Test(
    "without a starless the final image is written as the shaped original; a star tier is refused",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testWithoutStarless() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let folder = try ScratchDirectory.url.appendingPathComponent("export")
    var settings = ExportSettings()
    settings.deliverables = [.final]
    settings.formats = [.fits32]
    settings.orientation = .hflip
    let image = Self.image()

    let written = try DeliverableExport(device: device).write(
      original: image, starless: nil, settings: settings, to: folder)

    #expect(written.map(\.lastPathComponent) == ["final.fits"])
    let read = try FITSFile.read(at: written[0]).image()
    #expect(read.planes == (try DeliverableExport.shape(image, settings: settings)).planes)

    settings.deliverables = [.final, .stars50]
    #expect(throws: DeliverableExport.ExportError.needsStarless([.stars50])) {
      try DeliverableExport(device: device).write(
        original: image, starless: nil, settings: settings, to: folder)
    }
  }

  @Test("ExportSettings round-trips through JSON (the exports record keeps it)")
  func testSettingsCodable() throws {
    var settings = ExportSettings()
    settings.deliverables = [.final, .stars25]
    settings.formats = [.tiff16, .fits32]
    settings.cropFraction = 0.05
    settings.orientation = .vflip
    settings.nameTemplate = "M31-{name}"
    settings.starColour = 0.4
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(ExportSettings.self, from: data) == settings)
  }
}

extension ExportTests {
  @Test("choosing a file or a format keeps the legacy order; unchoosing removes it")
  func testChoose() {
    var settings = ExportSettings()
    settings.choose(.stars50, false)
    settings.choose(.starless, false)
    settings.choose(.starless, true)
    #expect(settings.deliverables == [.final, .starless, .stars75, .stars25])
    settings.choose(.fits32, true)
    settings.choose(.png16, false)
    settings.choose(.tiff16, true)
    #expect(settings.formats == [.tiff16, .fits32])
  }
}

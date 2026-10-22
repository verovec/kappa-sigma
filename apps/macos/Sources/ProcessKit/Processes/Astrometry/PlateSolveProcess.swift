internal import Foundation
package import ImageKit
package import Metal

/// Plate solving (card 0093, design §3.2 « astrométrie »): Siril's solver finds where the image
/// points, from a centre, a focal length and a pixel size the user confirmed.
///
/// A host-tool process: Apply runs Siril through the tool the app injects (`hostTool`); the
/// pixels never change, so the preview is the image itself and the step's output is the same
/// pixels with the solution's WCS cards (`History` writes them; the viewer's RA/Dec readout reads
/// them). R2: the header's pointing and optics are suggestions, taken with one click; the
/// coordinates stay empty until then, and Apply refuses empty ones.
package struct PlateSolveProcess: ImageProcess {
  package static let id = "plate-solve"
  package static let title = "Plate solving"
  package static let stage = ProcessStage.any
  package static let previewExactOnlyAt1to1 = false
  package static let hostTool = true

  /// The catalogue options: the local Gaia extract (offline), or Gaia fetched online.
  package static let catalogues = ["local-gaia", "online-gaia"]

  package static let schema = ParamSchema([
    ParamSpec(id: "ra", title: "Right ascension", level: .simple, text: "", maxLength: 40),
    ParamSpec(id: "dec", title: "Declination", level: .simple, text: "", maxLength: 40),
    ParamSpec(
      id: "focalMm", title: "Focal length (mm)", unit: .none, level: .simple, number: 0,
      in: 0...10_000),
    ParamSpec(
      id: "pixelSizeUm", title: "Pixel size (µm)", unit: .none, level: .simple, number: 0,
      in: 0...50),
    ParamSpec(
      id: "limitMag", title: "Limit magnitude (0: automatic)", unit: .none, level: .advanced,
      number: 0, in: 0...22),
    ParamSpec(
      id: "catalogue", title: "Star catalogue", level: .advanced, choice: "local-gaia",
      of: catalogues),
  ])

  /// The reason of the header suggestions: an English key of the catalog.
  package static let fromHeader = "From the image header"
  package static let suggestionReasons = [fromHeader]

  package let params: ParamSet

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
  }

  /// The image as it is: a solve adds a solution, never changes a pixel.
  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    try ColourKernel.copy(input, into: output, commands: context.commands)
  }

  /// The pointing and optics the header gives (`OBJCTRA`/`OBJCTDEC`, else `RA`/`DEC` in
  /// degrees; `FOCALLEN`; `XPIXSZ`), one suggestion per value found; none is applied here.
  package static func suggestions(header: FITSHeader?) -> [Suggestion] {
    guard let header else { return [] }
    var values: [(String, ParamValue)] = []
    if let ra = header.string("OBJCTRA"), let dec = header.string("OBJCTDEC") {
      values += [("ra", .text(ra)), ("dec", .text(dec))]
    } else if let ra = header.double("RA"), let dec = header.double("DEC") {
      values += [("ra", .text(degrees(ra))), ("dec", .text(degrees(dec)))]
    }
    if let focal = header.double("FOCALLEN"), focal > 0 {
      values.append(("focalMm", .number(focal)))
    }
    if let pixel = header.double("XPIXSZ"), pixel > 0 {
      values.append(("pixelSizeUm", .number(pixel)))
    }
    return values.compactMap { id, value in
      // A value the schema would refuse or change is not offered as if it were the header's.
      var params = ParamSet(schema: schema)
      guard (try? params.set(id, value)) != nil, params[id] == value else { return nil }
      return Suggestion(paramID: id, value: value, reason: fromHeader)
    }
  }

  /// Degrees as typed back: up to six decimals, no trailing zeros, a point whatever the locale.
  private static func degrees(_ value: Double) -> String {
    value.formatted(
      .number.precision(.fractionLength(0...6)).grouping(.never)
        .locale(Locale(identifier: "en_US_POSIX")))
  }
}

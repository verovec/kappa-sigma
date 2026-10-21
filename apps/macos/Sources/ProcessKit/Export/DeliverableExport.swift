package import Foundation
package import ImageKit
package import Metal

/// Writes the deliverable set of a finished image: the image itself, its starless and the star
/// tiers (`StarRecompositionProcess` at each presence, the same shader as the Studio), cropped, mirrored,
/// named and in the formats `ExportSettings` say.
package struct DeliverableExport {
  /// Why an export was refused or failed.
  package enum ExportError: Error, Equatable, Sendable {
    /// The target folder is a read-only source (captures, legacy runs): the reason.
    case readOnlyTarget(String)
    /// The image and its starless are not two RGB images of one size.
    case sizeMismatch
    /// The crop leaves nothing.
    case cropTooLarge(Double)
  }

  private let device: MTLDevice
  private let runner: ProcessRunner

  /// An exporter rendering its star tiers on `device`.
  package init(device: MTLDevice) throws {
    self.device = device
    runner = try ProcessRunner(device: device)
  }

  /// Writes the deliverables of `settings` into `folder` and returns the files in write order.
  ///
  /// They come from `original` (with stars) and its `starless`. A folder under the captures or
  /// the runs of `home` is refused before anything is written.
  package func write(
    original: AstroImage, starless: AstroImage, settings: ExportSettings, to folder: URL,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> [URL] {
    if let reason = ExportGuard.refusal(for: folder, home: home) {
      throw ExportError.readOnlyTarget(reason)
    }
    guard original.planes.count == 3, starless.planes.count == 3,
      original.width == starless.width, original.height == starless.height
    else { throw ExportError.sizeMismatch }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var written: [URL] = []
    for deliverable in settings.deliverables {
      let image = try Self.shape(
        render(deliverable, original: original, starless: starless, settings: settings),
        settings: settings)
      for format in settings.formats {
        let url = folder.appendingPathComponent(settings.fileName(deliverable, format))
        switch format {
        case .png16: try ImageExport.write(image, to: url, format: .png16)
        case .tiff16: try ImageExport.write(image, to: url, format: .tiff16)
        case .fits32: try FITSFile.create(image, keeping: nil, at: url)
        }
        written.append(url)
      }
    }
    return written
  }

  /// `deliverable` before the crop and mirror: the starless, or the stars put back at its
  /// presence with the export's star colour.
  private func render(
    _ deliverable: ExportSettings.Deliverable, original: AstroImage, starless: AstroImage,
    settings: ExportSettings
  ) throws -> AstroImage {
    guard let presence = deliverable.presence else { return starless }
    var params = ParamSet(schema: StarRecompositionProcess.schema)
    try params.set("chroma", .number(settings.starColour))
    try params.set("presence", .number(presence))
    let planes = try runner.run(
      StarRecompositionProcess(params: params, device: device),
      input: GPUImage(device: device, image: original), stats: LayerStats(channels: []),
      layers: [StarRecompositionProcess.starlessLayer: GPUImage(device: device, image: starless)]
    ).read()
    return AstroImage(
      width: original.width, height: original.height, planes: planes,
      metadata: original.metadata)
  }

  /// `image` trimmed by `cropFraction` of its width and height on each edge (rounded, as
  /// astrocomp), then mirrored.
  package static func shape(_ image: AstroImage, settings: ExportSettings) throws -> AstroImage {
    let (dx, dy) = (
      Int((Double(image.width) * settings.cropFraction).rounded()),
      Int((Double(image.height) * settings.cropFraction).rounded())
    )
    let (width, height) = (image.width - 2 * dx, image.height - 2 * dy)
    guard width > 0, height > 0 else { throw ExportError.cropTooLarge(settings.cropFraction) }
    let planes = image.planes.map { plane in
      (0..<height).flatMap { row -> [Float] in
        let sourceRow = settings.orientation == .vflip ? dy + height - 1 - row : dy + row
        let line = plane[(sourceRow * image.width + dx)..<(sourceRow * image.width + dx + width)]
        return settings.orientation == .hflip ? line.reversed() : Array(line)
      }
    }
    return AstroImage(width: width, height: height, planes: planes, metadata: image.metadata)
  }
}

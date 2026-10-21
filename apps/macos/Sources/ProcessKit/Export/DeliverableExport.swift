package import Foundation
package import ImageKit
package import Metal

/// Writes the deliverable set of a finished image: the image itself, its starless and the star
/// tiers (`StarRecompositionProcess` at each presence, the same shader as the Studio), cropped,
/// mirrored, named and in the formats `ExportSettings` say.
package struct DeliverableExport {
  /// Why an export was refused or failed.
  package enum ExportError: Error, Equatable, Sendable {
    /// The target folder is a read-only source (captures, runs, library, fixtures): the reason.
    case readOnlyTarget(String)
    /// The image and its starless are not two RGB images of one size.
    case sizeMismatch
    /// The image and its starless store their rows in different orders: they would pair the
    /// wrong pixels.
    case rowOrderMismatch
    /// The crop leaves nothing.
    case cropTooLarge(Double)
    /// A negative or non-finite crop fraction.
    case invalidCrop(Double)
    /// A name template that is not one file name containing `{name}`.
    case invalidTemplate(String)
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
  /// They come from `original` (with stars) and its `starless`. Everything is checked before a
  /// file is written: a folder under the read-only sources of `home`, a crop or a name template
  /// that cannot work, two images that do not pair pixel for pixel.
  package func write(
    original: AstroImage, starless: AstroImage, settings: ExportSettings, to folder: URL,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> [URL] {
    if let reason = ExportGuard.refusal(for: folder, home: home) {
      throw ExportError.readOnlyTarget(reason)
    }
    try Self.validate(settings)
    guard original.planes.count == 3, starless.planes.count == 3,
      original.width == starless.width, original.height == starless.height
    else { throw ExportError.sizeMismatch }
    guard original.metadata.rowOrder == starless.metadata.rowOrder else {
      throw ExportError.rowOrderMismatch
    }
    // Shaped once: the recomposition is per pixel, so it commutes with the crop and the mirror.
    let (shapedOriginal, shapedStarless) = (
      try Self.shape(original, settings: settings), try Self.shape(starless, settings: settings)
    )
    let input = try GPUImage(device: device, image: shapedOriginal)
    let layers = [
      StarRecompositionProcess.starlessLayer: try GPUImage(device: device, image: shapedStarless)
    ]
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var written: [URL] = []
    for deliverable in settings.deliverables {
      let image =
        try deliverable.presence.map {
          try recompose(
            input, layers: layers, like: shapedOriginal, presence: $0, settings: settings)
        } ?? shapedStarless
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

  /// The stars put back at `presence` with the export's star colour.
  private func recompose(
    _ input: GPUImage, layers: [String: GPUImage], like image: AstroImage, presence: Double,
    settings: ExportSettings
  ) throws -> AstroImage {
    var params = ParamSet(schema: StarRecompositionProcess.schema)
    try params.set("chroma", .number(settings.starColour))
    try params.set("presence", .number(presence))
    let planes = try runner.run(
      StarRecompositionProcess(params: params, device: device), input: input,
      stats: LayerStats(channels: []), layers: layers
    ).read()
    return AstroImage(
      width: image.width, height: image.height, planes: planes, metadata: image.metadata)
  }

  /// The settings' crop and name template, refused when they cannot work.
  static func validate(_ settings: ExportSettings) throws {
    guard settings.cropFraction.isFinite, settings.cropFraction >= 0 else {
      throw ExportError.invalidCrop(settings.cropFraction)
    }
    let template = settings.nameTemplate
    guard template.contains("{name}"), !template.contains("/"), !template.hasPrefix(".") else {
      throw ExportError.invalidTemplate(template)
    }
  }

  /// `image` trimmed by `cropFraction` of its width and height on each edge (rounded, as
  /// astrocomp), then mirrored.
  package static func shape(_ image: AstroImage, settings: ExportSettings) throws -> AstroImage {
    try validate(settings)
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

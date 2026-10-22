import Foundation
import ImageKit
import Metal
import RenderKit
import os

/// A FITS decoded, uploaded and autostretched off the main actor: what a viewer window opens
/// (File › Open Image…, a layer of an opened run).
nonisolated struct LoadedImage {
  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/viewer")

  let image: AstroImage
  let texture: ImageTexture
  /// Each plane's median and MADN: the viewer's autostretch and σ controls read them.
  let statistics: [STFMapping]

  /// Decodes, uploads and measures `url` off the main actor.
  ///
  /// FITS decode, pyramid + upload and statistics are CPU-bound. Reads only (a legacy run folder
  /// is read-only).
  @concurrent
  static func read(_ url: URL, device: MTLDevice) async throws -> sending Self {
    let started = ContinuousClock.now
    let image = try FITSFile.read(at: url).image()
    let decoded = ContinuousClock.now
    let texture = try ImageTexture(
      device: device, width: image.width, height: image.height, planes: image.planes)
    let uploaded = ContinuousClock.now
    let statistics = STFMapping.measure(planes: image.planes, linked: false)
    logger.info(
      """
      opened \(url.lastPathComponent, privacy: .public) \(image.width)×\(image.height)×\
      \(image.planes.count), \(texture.mipLevels) mip levels: read \
      \(decoded - started, privacy: .public), upload \(uploaded - decoded, privacy: .public), \
      STF \(ContinuousClock.now - uploaded, privacy: .public)
      """)
    return Self(image: image, texture: texture, statistics: statistics)
  }
}

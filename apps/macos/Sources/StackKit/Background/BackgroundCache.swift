internal import CryptoKit
package import Foundation
package import ImageKit

/// The pairs already extracted under a scratch folder, keyed by the input pixels and the request
/// (the legacy `rgb_base_bg.fits` + `.sig`): an identical request never runs the tool again.
package struct BackgroundCache: Sendable {
  /// The folder holding one sub-folder per key.
  package let root: URL

  /// A cache under `root`.
  package init(root: URL) {
    self.root = root
  }

  /// The key of `image` under `engine` and `correction`.
  ///
  /// sha256 of the request line, the shape and every plane's bytes; checks for cancellation
  /// between planes (hundreds of MB on a full frame).
  package func key(image: AstroImage, engine: BackgroundEngine, correction: BackgroundCorrection)
    throws -> String
  {
    var hasher = SHA256()
    let request = "\(engine.cacheDescription)|\(correction.rawValue)|\(image.width)x\(image.height)"
    hasher.update(data: Data(request.utf8))
    for plane in image.planes {
      try Task.checkCancellation()
      plane.withUnsafeBytes { hasher.update(bufferPointer: $0) }
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// The folder of `key` (where its tool runs and its pair is kept).
  package func folder(_ key: String) -> URL {
    root.appendingPathComponent(key, isDirectory: true)
  }

  /// The stored pair of `key` with `metadata` (the input's), or nil when it is not complete.
  package func load(_ key: String, metadata: ImageMetadata) throws -> BackgroundResult? {
    let folder = folder(key)
    let urls = (
      folder.appendingPathComponent("corrected.fits"), folder.appendingPathComponent("model.fits")
    )
    guard FileManager.default.fileExists(atPath: urls.0.path),
      FileManager.default.fileExists(atPath: urls.1.path)
    else { return nil }
    return BackgroundResult(
      corrected: try Self.read(urls.0, metadata: metadata),
      model: try Self.read(urls.1, metadata: metadata), reused: true)
  }

  /// Keeps `result` under `key`.
  package func store(_ key: String, _ result: BackgroundResult) throws {
    let folder = folder(key)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FITSFile.create(
      result.corrected, keeping: nil, at: folder.appendingPathComponent("corrected.fits"))
    try FITSFile.create(result.model, keeping: nil, at: folder.appendingPathComponent("model.fits"))
  }

  /// A stored FITS in the row order of `metadata`, carrying it.
  ///
  /// A file without a `ROWORDER` card is taken as already in that order: a tool keeps the array
  /// as it read it, only the card may be dropped on the way (the FITS default would mirror it).
  package static func read(_ url: URL, metadata: ImageMetadata) throws -> AstroImage {
    let file = try FITSFile.read(at: url)
    var image = try file.image()
    if file.header.string("ROWORDER") != nil { image = image.inRowOrder(metadata.rowOrder) }
    image.metadata = metadata
    return image
  }
}

package import Foundation
package import ImageKit

/// Where the scan reads its captures (card 0166), injected like `PixelReader`: the walk of a root,
/// a frame's primary header, and the bytes of a side file (a SharpCap sidecar, an `info.txt`).
///
/// `.files` is the local disk — the walk and the readers the scan always used. The remote
/// snapshot (0167) answers the same three questions from an S3 prefix read in advance, so the
/// scan itself stays synchronous and unchanged.
package struct FrameSource: Sendable {
  /// The files and skipped packages under a root (`skippingOutput`: `output` folders skipped);
  /// call it through `listing(under:skippingOutput:)`.
  package var walk: @Sendable (_ root: String, _ skippingOutput: Bool) throws -> InspectWalk.Listing
  /// The primary header of the frame at a path (no pixels decoded).
  package var header: @Sendable (_ path: String) throws -> FITSHeader
  /// The bytes of the file at a path, `nil` when there is none.
  package var contents: @Sendable (_ path: String) -> Data?
  /// The path a frame found by the walk is recorded under (the disk's is URL-normalised, as the
  /// scan always stored it; another source keeps its own spelling, an `s3://` key for one).
  package var framePath: @Sendable (_ path: String) -> String

  /// A source from its closures; `framePath` keeps the walk's spelling unless given.
  package init(
    walk: @escaping @Sendable (String, Bool) throws -> InspectWalk.Listing,
    header: @escaping @Sendable (String) throws -> FITSHeader,
    contents: @escaping @Sendable (String) -> Data?,
    framePath: @escaping @Sendable (String) -> String = { $0 }
  ) {
    self.walk = walk
    self.header = header
    self.contents = contents
    self.framePath = framePath
  }

  /// The files and skipped packages under `root`; `skippingOutput` skips `output` folders.
  package func listing(under root: String, skippingOutput: Bool) throws -> InspectWalk.Listing {
    try walk(root, skippingOutput)
  }

  /// The local disk: `InspectWalk`, ImageKit's FITS header reader, `FileManager`.
  package static let files = Self(
    walk: { root, skippingOutput in
      try InspectWalk.listing(under: root, skippingOutput: skippingOutput)
    },
    header: { path in try FITSFile.read(at: URL(fileURLWithPath: path)).header },
    contents: { path in FileManager.default.contents(atPath: path) },
    framePath: { path in URL(fileURLWithPath: path).path })
}

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
  /// called through `listing(under:skippingOutput:)`.
  package private(set) var walk:
    @Sendable (_ root: String, _ skippingOutput: Bool) throws -> InspectWalk.Listing
  /// The primary header of the frame at a path (no pixels decoded).
  package private(set) var header: @Sendable (_ path: String) throws -> FITSHeader
  /// The bytes of the file at a path, `nil` when there is none.
  package private(set) var contents: @Sendable (_ path: String) -> Data?
  /// A source from its closures.
  ///
  /// Every path the scan uses — a frame's, its sidecar's, a manifest's — is the walk's spelling:
  /// a source spells its paths once, in `walk`.
  package init(
    walk: @escaping @Sendable (String, Bool) throws -> InspectWalk.Listing,
    header: @escaping @Sendable (String) throws -> FITSHeader,
    contents: @escaping @Sendable (String) -> Data?
  ) {
    self.walk = walk
    self.header = header
    self.contents = contents
  }

  /// The files and skipped packages under `root`; `skippingOutput` skips `output` folders.
  package func listing(under root: String, skippingOutput: Bool) throws -> InspectWalk.Listing {
    try walk(root, skippingOutput)
  }

  /// The local disk: `InspectWalk`, ImageKit's FITS header reader, `FileManager`.
  ///
  /// Its paths are the root's spelling plus the entries' names (the app passes absolute,
  /// canonical roots).
  package static let files = Self(
    walk: { root, skippingOutput in
      try InspectWalk.listing(under: root, skippingOutput: skippingOutput)
    },
    header: { path in try FITSFile.read(at: URL(fileURLWithPath: path)).header },
    contents: { path in FileManager.default.contents(atPath: path) })
}

package import Foundation
package import ImageKit

/// Where the scan reads its captures (card 0166), injected like `PixelReader`: the walk of a root,
/// a frame's primary header, and the bytes of a side file (a SharpCap sidecar, an `info.txt`).
///
/// `.files` is the local disk — the walk and the readers the scan always used. The remote
/// snapshot (0167) answers the same three questions from an S3 prefix read in advance, so the
/// scan itself stays synchronous and unchanged.
package struct FrameSource: Sendable {
  /// The files and skipped packages under a root (`skippingOutput`: `output` folders skipped).
  package var listing:
    @Sendable (_ root: String, _ skippingOutput: Bool) throws -> InspectWalk.Listing
  /// The primary header of the frame at a path (no pixels decoded).
  package var header: @Sendable (_ path: String) throws -> FITSHeader
  /// The bytes of the file at a path, `nil` when there is none.
  package var contents: @Sendable (_ path: String) -> Data?

  /// A source from the three closures.
  package init(
    listing: @escaping @Sendable (String, Bool) throws -> InspectWalk.Listing,
    header: @escaping @Sendable (String) throws -> FITSHeader,
    contents: @escaping @Sendable (String) -> Data?
  ) {
    self.listing = listing
    self.header = header
    self.contents = contents
  }

  /// The local disk: `InspectWalk`, ImageKit's FITS header reader, `FileManager`.
  package static let files = Self(
    listing: { root, skippingOutput in
      try InspectWalk.listing(under: root, skippingOutput: skippingOutput)
    },
    header: { path in try FITSFile.read(at: URL(fileURLWithPath: path)).header },
    contents: { path in FileManager.default.contents(atPath: path) })
}

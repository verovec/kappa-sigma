internal import CryptoKit
package import Foundation

/// Hashes of a file read in chunks (frames and stacks are hundreds of MB; never one `Data`).
package enum FileDigest {
  private static let chunk = 4 << 20

  /// The lowercase hex MD5 of `url` (a single-part ETag).
  package static func md5Hex(_ url: URL) throws -> String {
    try digest(url, into: Insecure.MD5()).hexString
  }

  /// The lowercase hex MD5 of `data` (the ETag of a single PUT of it).
  package static func md5Hex(_ data: Data) -> String {
    Insecure.MD5.hash(data: data).hexString
  }

  /// The ETag S3 gives an object completed from parts whose MD5s are `parts` (computed from the
  /// bytes sent, never read back from the service): the MD5 of those MD5s, then `-<count>`.
  package static func multipartETag(_ parts: [Data]) -> String? {
    guard !parts.isEmpty else { return nil }
    return "\(Insecure.MD5.hash(data: Data(parts.joined())).hexString)-\(parts.count)"
  }

  /// The binary MD5 of `data` (a part's, for `multipartETag`).
  package static func md5(_ data: Data) -> Data { Data(Insecure.MD5.hash(data: data)) }

  /// The base64 SHA-256 of `url` (an `x-amz-checksum-sha256` value).
  package static func sha256Base64(_ url: URL) throws -> String {
    Data(try digest(url, into: SHA256())).base64EncodedString()
  }

  /// The size of `url` in bytes, through symbolic links (a lane links its frames).
  package static func size(_ url: URL) throws -> Int64 {
    let target = url.resolvingSymlinksInPath()
    let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }

  private static func digest<H: HashFunction>(_ url: URL, into hasher: H) throws -> H.Digest {
    var hasher = hasher
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    while let data = try handle.read(upToCount: chunk), !data.isEmpty {
      try Task.checkCancellation()
      hasher.update(data: data)
    }
    return hasher.finalize()
  }
}

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

  /// The ETag S3 gives an object completed from parts tagged `parts` (each its part's hex MD5):
  /// the MD5 of the parts' binary MD5s, then `-<count>`; `nil` when a tag is not an MD5 (SSE-KMS
  /// or SSE-C), so nothing can be told from it.
  package static func multipartETag(_ parts: [String]) -> String? {
    var md5s = Data()
    for tag in parts {
      guard tag.utf8.count == 32, let bytes = hexBytes(tag) else { return nil }
      md5s.append(contentsOf: bytes)
    }
    return parts.isEmpty ? nil : "\(Insecure.MD5.hash(data: md5s).hexString)-\(parts.count)"
  }

  private static func hexBytes(_ hex: String) -> [UInt8]? {
    let digits = Array(hex.lowercased().utf8)
    var bytes: [UInt8] = []
    for index in stride(from: 0, to: digits.count, by: 2) {
      guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else {
        return nil
      }
      bytes.append(high << 4 | low)
    }
    return bytes
  }

  private static func nibble(_ digit: UInt8) -> UInt8? {
    switch digit {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
    default: nil
    }
  }

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

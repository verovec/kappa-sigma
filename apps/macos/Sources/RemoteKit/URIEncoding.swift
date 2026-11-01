internal import CryptoKit
package import Foundation

/// The percent-encoding SigV4 and S3 agree on.
///
/// Every byte but `A–Z a–z 0–9 - . _ ~` becomes `%XX` (uppercase), `/` kept only in a path.
/// Foundation's encoders keep more (`+`, `=`, …).
package enum URIEncoding {
  private static let digits = Array("0123456789ABCDEF".utf8)

  /// The UTF-8 bytes of `text` percent-encoded, `/` left literal when `keepingSlash`.
  package static func encode(_ text: String, keepingSlash: Bool = false) -> String {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(text.utf8.count)
    for byte in text.utf8 {
      if isUnreserved(byte) || (keepingSlash && byte == UInt8(ascii: "/")) {
        bytes.append(byte)
      } else {
        bytes += [UInt8(ascii: "%"), digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]]
      }
    }
    return String(bytes: bytes, encoding: .ascii) ?? ""
  }

  private static func isUnreserved(_ byte: UInt8) -> Bool {
    switch byte {
    case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
      UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
      UInt8(ascii: "_"), UInt8(ascii: "~"):
      true
    default: false
    }
  }
}

extension Sequence<UInt8> {
  /// The bytes as lowercase hex, as SigV4 writes hashes and signatures.
  package var hexString: String {
    let digits = Array("0123456789abcdef".utf8)
    var out: [UInt8] = []
    for byte in self { out += [digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]] }
    return String(bytes: out, encoding: .ascii) ?? ""
  }
}

extension Data {
  /// The lowercase hex SHA-256 of these bytes (a SigV4 payload hash).
  package var sha256Hex: String { SHA256.hash(data: self).hexString }

  /// Both forms of one SHA-256: hex (the payload hash) and base64 (the checksum header).
  package var sha256Digests: (hex: String, base64: String) {
    let digest = SHA256.hash(data: self)
    return (digest.hexString, Data(digest).base64EncodedString())
  }
}

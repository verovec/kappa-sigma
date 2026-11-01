package import Foundation

/// An object as a listing or a HEAD describes it.
package struct S3Object: Sendable, Equatable, Hashable {
  /// The full key.
  package let key: String
  /// Size in bytes.
  package let size: Int64
  /// The ETag without quotes: the content MD5 for a single-part, unencrypted upload,
  /// `<md5 of part md5s>-<parts>` for a multipart one.
  package let etag: String
  /// When the object was last written.
  package let lastModified: Date?

  /// Creates an object description.
  package init(key: String, size: Int64, etag: String, lastModified: Date?) {
    self.key = key
    self.size = size
    self.etag = etag
    self.lastModified = lastModified
  }

  /// `true` when the ETag is a bare 32-hex digest (a single-part upload), not `…-N`.
  package var isSinglePartETag: Bool {
    etag.count == 32 && etag.allSatisfy(\.isHexDigit)
  }

  /// `text` without the surrounding double quotes S3 puts on ETags.
  package static func unquoted(_ text: String) -> String {
    text.count >= 2 && text.hasPrefix("\"") && text.hasSuffix("\"")
      ? String(text.dropFirst().dropLast()) : text
  }
}

package import Foundation

/// A response as RemoteKit reads it: status, lowercase headers, body.
package struct HTTPResponse: Sendable, Equatable {
  /// The HTTP status code.
  package var status: Int
  /// Header values by lowercase name.
  package var headers: [String: String]
  /// The body (empty after a download wrote it to a file).
  package var body: Data

  /// Creates a response; header names are lowercased.
  package init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
    self.status = status
    self.headers = Dictionary(
      headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    self.body = body
  }

  /// `true` for 2xx.
  package var isSuccess: Bool { (200..<300).contains(status) }

  /// The `ETag` header without its quotes.
  package var etag: String? { headers["etag"].map(S3Object.unquoted) }
}

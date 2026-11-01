package import Foundation

/// A signed request ready for the wire.
package struct HTTPRequest: Sendable, Equatable {
  /// `GET`, `HEAD`, `PUT`, `POST`, `DELETE`.
  package var method: String
  /// The full URL, path and query already encoded as signed.
  package var url: URL
  /// Lowercase header names; `host` is informative (the transport derives it from `url`).
  package var headers: [String: String]
  /// The body, if any.
  package var body: Data?

  /// Creates a request.
  package init(method: String, url: URL, headers: [String: String], body: Data? = nil) {
    self.method = method
    self.url = url
    self.headers = headers
    self.body = body
  }
}

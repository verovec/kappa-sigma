/// An HTTP request as SigV4 sees it: decoded path and query, headers in sending order and the
/// hex SHA-256 of the body (or `UNSIGNED-PAYLOAD`).
package struct SignableRequest: Sendable, Equatable {
  /// One header line; a name may repeat (its values are joined with `,` when signed).
  package struct Header: Sendable, Equatable {
    /// The name as sent (signing lowercases it).
    package var name: String
    /// The value as sent (signing trims it and collapses inner runs of spaces).
    package var value: String

    /// Creates a header line.
    package init(_ name: String, _ value: String) {
      self.name = name
      self.value = value
    }
  }

  /// One query parameter, decoded; an empty value is still `name=`.
  package struct QueryItem: Sendable, Equatable {
    /// The decoded parameter name.
    package var name: String
    /// The decoded parameter value.
    package var value: String

    /// Creates a query parameter.
    package init(_ name: String, _ value: String) {
      self.name = name
      self.value = value
    }
  }

  /// `GET`, `PUT`, `POST`, `HEAD`, `DELETE`.
  package var method: String
  /// The decoded path, starting with `/`; signing percent-encodes it once, as S3 does.
  package var path: String
  /// The decoded query parameters, in any order.
  package var query: [QueryItem]
  /// The headers to sign, `host` included.
  package var headers: [Header]
  /// Lowercase hex SHA-256 of the body (or `UNSIGNED-PAYLOAD`).
  package var payloadHash: String

  /// Creates a request to sign.
  package init(
    method: String, path: String, query: [QueryItem] = [], headers: [Header],
    payloadHash: String
  ) {
    self.method = method
    self.path = path
    self.query = query
    self.headers = headers
    self.payloadHash = payloadHash
  }

  /// The value of the first header named `name` (case-insensitive), if any.
  package func header(_ name: String) -> String? {
    headers.first { $0.name.lowercased() == name.lowercased() }?.value
  }
}

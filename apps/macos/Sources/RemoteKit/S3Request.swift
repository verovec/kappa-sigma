package import Foundation

/// One S3 call before addressing and signing: method, bucket, key, query, extra headers, body.
package struct S3Request: Sendable, Equatable {
  /// `GET`, `HEAD`, `PUT`, `POST`, `DELETE`.
  package var method: String
  /// The bucket name.
  package var bucket: String
  /// The object key, decoded (`""` addresses the bucket).
  package var key: String
  /// Decoded query parameters.
  package var query: [SignableRequest.QueryItem]
  /// Headers beyond the ones signing adds (`range`, `x-amz-checksum-*`, …), lowercase names.
  package var headers: [String: String]
  /// The body; hashed into `x-amz-content-sha256`.
  package var body: Data?
  /// The body's hex SHA-256 when the caller already has it (hashed once, not once per try).
  package var payloadHash: String?

  /// Creates a call.
  package init(
    method: String, bucket: String, key: String,
    query: [SignableRequest.QueryItem] = [], headers: [String: String] = [:], body: Data? = nil,
    payloadHash: String? = nil
  ) {
    self.method = method
    self.bucket = bucket
    self.key = key
    self.query = query
    self.headers = headers
    self.body = body
    self.payloadHash = payloadHash
  }

  /// The wire request, addressed on `endpoint` and signed by `signer` at `date`.
  ///
  /// The URL carries the path and query in the exact encoding that was signed.
  package func prepared(endpoint: S3Endpoint, signer: SigV4, date: Date) throws -> HTTPRequest {
    let (host, path) = endpoint.location(bucket: bucket, key: key)
    let hash = payloadHash ?? (body ?? Data()).sha256Hex
    var headerLines = [
      SignableRequest.Header("host", host), SignableRequest.Header("x-amz-content-sha256", hash),
    ]
    headerLines += headers.keys.sorted().map { .init($0, headers[$0] ?? "") }
    let signed = signer.signed(
      SignableRequest(
        method: method, path: path, query: query, headers: headerLines,
        payloadHash: hash),
      date: date)

    // The canonical query order, so the URL sent is the one signed.
    let encodedQuery = SigV4.canonicalQuery(query)
    let text =
      "\(endpoint.scheme)://\(host)\(URIEncoding.encode(path, keepingSlash: true))"
      + (encodedQuery.isEmpty ? "" : "?\(encodedQuery)")
    guard let url = URL(string: text) else { throw S3Error.invalidRequest(text) }
    var wire: [String: String] = [:]
    for header in signed.headers { wire[header.name.lowercased()] = header.value }
    return HTTPRequest(method: method, url: url, headers: wire, body: body)
  }
}

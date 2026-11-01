package import Foundation

extension HTTPTransport {
  /// The live transport over a `URLSession` with `configuration`.
  ///
  /// Ephemeral by default: no cookies, no cache, no credentials kept. Downloads land in
  /// URLSession's temporary file, then move to the destination; progress is reported once, when
  /// the body is complete. Redirects are refused: the 3xx (S3's `PermanentRedirect` to another
  /// region) comes back as an error, never as a signed request replayed to another host.
  package static func urlSession(_ configuration: URLSessionConfiguration = .ephemeral) -> Self {
    let session = URLSession(
      configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
    return Self(
      send: { request in
        let (data, response) = try await session.data(for: urlRequest(request))
        return try httpResponse(response, body: data)
      },
      download: { request, destination, progress in
        let (temporary, response) = try await session.download(for: urlRequest(request))
        let files = FileManager.default
        defer { try? files.removeItem(at: temporary) }
        var http = try httpResponse(response, body: Data())
        guard http.isSuccess else {
          http.body = (try? Data(contentsOf: temporary)) ?? Data()
          return http
        }
        try? files.removeItem(at: destination)
        try files.moveItem(at: temporary, to: destination)
        progress(try FileDigest.size(destination))
        return http
      })
  }

  /// `request` for URLSession; `host` is left to URLSession, which derives it from the URL.
  static func urlRequest(_ request: HTTPRequest) -> URLRequest {
    var wire = URLRequest(url: request.url)
    wire.httpMethod = request.method
    for (name, value) in request.headers where name != "host" {
      wire.setValue(value, forHTTPHeaderField: name)
    }
    // Bytes as stored: URLSession would otherwise inflate a gzip-encoded object on its own,
    // breaking sizes, checksums and byte ranges.
    if wire.value(forHTTPHeaderField: "accept-encoding") == nil {
      wire.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    }
    wire.httpBody = request.body
    return wire
  }

  static func httpResponse(_ response: URLResponse, body: Data) throws -> HTTPResponse {
    guard let http = response as? HTTPURLResponse else {
      throw S3Error.invalidResponse(
        "not an HTTP response from \(response.url?.absoluteString ?? "?")")
    }
    var headers: [String: String] = [:]
    for (name, value) in http.allHeaderFields {
      if let name = name as? String, let value = value as? String { headers[name] = value }
    }
    return HTTPResponse(status: http.statusCode, headers: headers, body: body)
  }
}

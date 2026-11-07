package import Foundation

extension HTTPTransport {
  /// How long a request may wait for its next bytes before it times out (retried by `S3Client`).
  ///
  /// URLSession's own default, made explicit: a CompleteMultipartUpload that takes minutes stays
  /// alive on the whitespace S3 and MinIO send while they work.
  package static let idleTimeout: TimeInterval = 60
  /// The longest one request may take as a whole.
  ///
  /// 6 h: a 4 GB object still downloads at 200 kB/s, while a connection that only trickles ends
  /// instead of running for URLSession's 7 days.
  package static let transferTimeout: TimeInterval = 6 * 3600

  /// The live configuration: ephemeral (no cookies, cache or credentials kept) with `idle` and
  /// `transfer` timeouts.
  package static func configuration(
    idle: TimeInterval = idleTimeout, transfer: TimeInterval = transferTimeout
  ) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = idle
    configuration.timeoutIntervalForResource = transfer
    return configuration
  }

  /// The live transport over a `URLSession` with `configuration`.
  ///
  /// Bounded by `configuration()` by default (see `idleTimeout`, `transferTimeout`). Downloads land in
  /// URLSession's temporary file, then move to the destination; progress is reported once, when
  /// the body is complete. Redirects are refused: the 3xx (S3's `PermanentRedirect` to another
  /// region) comes back as an error, never as a signed request replayed to another host.
  package static func urlSession(_ configuration: URLSessionConfiguration = configuration())
    -> Self
  {
    let session = URLSession(
      configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
    let transfer = configuration.timeoutIntervalForResource
    return Self(
      send: { request in
        let (data, response) = try await bounded(transfer) {
          try await session.data(for: urlRequest(request))
        }
        return try httpResponse(response, body: data)
      },
      download: { request, destination, progress in
        let (temporary, response) = try await bounded(transfer) {
          try await session.download(for: urlRequest(request))
        }
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

  /// `body`, whose `URLError.timedOut` after `transfer` seconds becomes `transferTimedOut`.
  ///
  /// URLSession reports both of its timeouts as `.timedOut`: a stall is worth retrying, but a
  /// transfer that used its whole time would only start again from byte 0 under the same limit.
  static func bounded<T>(_ transfer: TimeInterval, _ body: () async throws -> T) async throws -> T {
    let start = ContinuousClock.now
    do {
      return try await body()
    } catch let error as URLError
      where error.code == .timedOut && ContinuousClock.now - start >= .seconds(transfer * 0.95)
    {
      throw S3Error.transferTimedOut(seconds: transfer)
    }
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

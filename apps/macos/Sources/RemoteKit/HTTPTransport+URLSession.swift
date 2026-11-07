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

  /// The live configuration: ephemeral (no cookies, cache or credentials kept), a stall ending
  /// after `idle` seconds (`URLError.timedOut`, retried).
  ///
  /// The whole-transfer limit is not URLSession's: it reports it with the same `.timedOut` as a
  /// stall, so `urlSession(_:transfer:)` owns it and ends it as `S3Error.transferTimedOut`.
  package static func configuration(idle: TimeInterval = idleTimeout) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = idle
    return configuration
  }

  /// The live transport over a `URLSession` with `configuration`, each request ended after
  /// `transfer` seconds.
  ///
  /// A stall ends after `idleTimeout` (`configuration()`). Downloads land in URLSession's
  /// temporary file, then move to the destination; progress is reported once, when
  /// the body is complete. Redirects are refused: the 3xx (S3's `PermanentRedirect` to another
  /// region) comes back as an error, never as a signed request replayed to another host.
  package static func urlSession(
    _ configuration: URLSessionConfiguration = configuration(),
    transfer: TimeInterval = transferTimeout
  ) -> Self {
    let session = URLSession(
      configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
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

  /// `body`, or `S3Error.transferTimedOut` once it has run for `transfer` seconds.
  ///
  /// The deadline is a timer that cancels the request, so every `URLError.timedOut` left is a
  /// stall (retried) and a transfer that used its whole time is not: a new try would start again
  /// from byte 0. A caller's cancel reaches the request as before (`URLError.cancelled`), and an
  /// answer that lands as the timer fires is returned, never dropped (a download's file with it).
  static func bounded<T: Sendable>(
    _ transfer: TimeInterval, _ body: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    // An already-cancelled caller sends nothing: the request below is not a child task.
    try Task.checkCancellation()
    let expiry = Expiry()
    let work = Task { try await body() }
    let timer = Task {
      try await Task.sleep(for: .seconds(transfer))
      await expiry.expire()
      work.cancel()
    }
    defer { timer.cancel() }
    return try await withTaskCancellationHandler {
      do {
        return try await work.value
      } catch {
        // Only the timer's own cancel is the deadline: a stall or a caller's cancel that lands
        // as the timer fires keeps its own error (a stall stays retried).
        let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
        if cancelled, !Task.isCancelled, await expiry.expired {
          throw S3Error.transferTimedOut(seconds: transfer)
        }
        throw error
      }
    } onCancel: {
      work.cancel()
    }
  }

  /// Whether a request's deadline has passed.
  private actor Expiry {
    private(set) var expired = false
    func expire() { expired = true }
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

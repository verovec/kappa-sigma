import Foundation
import RemoteKit
import Testing

/// A scripted S3 server: answers each request through `respond` and records what it was sent.
final class Fake: Sendable {
  static let credentials = S3Credentials(accessKey: "AKFAKE", secretKey: "secret")
  /// `2026-11-01T12:00:00Z`.
  static let date = Date(timeIntervalSince1970: 1_793_534_400)

  typealias Respond = @Sendable (HTTPRequest, _ call: Int) throws -> HTTPResponse

  private let log = Log()
  private let respond: Respond

  init(_ respond: @escaping Respond) { self.respond = respond }

  /// Every request received, in order.
  var requests: [HTTPRequest] { get async { await log.requests } }

  /// A transport over this fake; `download` writes a 2xx body to the destination.
  var transport: HTTPTransport {
    HTTPTransport(
      send: { request in try await self.answer(request) },
      download: { request, destination, progress in
        var response = try await self.answer(request)
        guard (200..<300).contains(response.status) else { return response }
        try response.body.write(to: destination)
        progress(Int64(response.body.count))
        response.body = Data()
        return response
      })
  }

  /// A client over this fake with the given policy, no real sleeps and a fixed clock.
  func client(policy: S3Client.Policy = .init(), sleeps: SleepLog? = nil) throws -> S3Client {
    let endpoint = try S3Endpoint(
      url: try #require(URL(string: "http://127.0.0.1:9000")), region: "us-east-1",
      addressing: .pathStyle)
    return S3Client(
      endpoint: endpoint, credentials: Self.credentials, transport: transport, policy: policy,
      clock: { Self.date }, sleep: { await sleeps?.append($0) })
  }

  private func answer(_ request: HTTPRequest) async throws -> HTTPResponse {
    let call = await log.append(request)
    return try respond(request, call)
  }

  private actor Log {
    var requests: [HTTPRequest] = []
    func append(_ request: HTTPRequest) -> Int {
      requests.append(request)
      return requests.count - 1
    }
  }
}

/// The backoff delays a client asked for.
actor SleepLog {
  var delays: [Duration] = []
  func append(_ delay: Duration) { delays.append(delay) }
}

extension HTTPResponse {
  /// A response with lowercase header names.
  static func make(_ status: Int, _ body: String = "", headers: [String: String] = [:]) -> Self {
    HTTPResponse(status: status, headers: headers, body: Data(body.utf8))
  }

  /// An S3 `<Error>` document.
  static func error(_ status: Int, code: String, message: String) -> Self {
    make(
      status,
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Error><Code>\(code)</Code>"
        + "<Message>\(message)</Message><RequestId>R1</RequestId></Error>")
  }
}

extension HTTPRequest {
  /// The decoded value of query parameter `name`.
  func query(_ name: String) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == name }.map { $0.value ?? "" }
  }
}

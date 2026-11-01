import Foundation
import RemoteKit
import Synchronization
import TestSupport
import Testing

/// The live transport over a stubbed URL loading system: no network, same URLSession code path.
@Suite("The URLSession transport carries requests and responses as is")
struct URLSessionTransportTests {
  /// Answers by host, so parallel tests never share a route; records what it received.
  final class Stub: URLProtocol {
    struct Route: Sendable {
      var status: Int
      var headers: [String: String]
      var body: Data
      var received: HTTPRequest?
    }

    static let routes = Mutex<[String: Route]>([:])

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      let host = request.url?.host ?? ""
      let route = Self.routes.withLock { routes -> Route? in
        routes[host]?.received = HTTPRequest(
          method: request.httpMethod ?? "", url: request.url ?? URL(fileURLWithPath: "/"),
          headers: Self.headers(of: request), body: Self.body(of: request))
        return routes[host]
      }
      guard let route, let url = request.url,
        let response = HTTPURLResponse(
          url: url, statusCode: route.status, httpVersion: "HTTP/1.1", headerFields: route.headers)
      else {
        return client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)) ?? ()
      }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: route.body)
      client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func headers(of request: URLRequest) -> [String: String] {
      Dictionary(
        (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) },
        uniquingKeysWith: { first, _ in first })
    }

    /// URLSession hands an upload body to a protocol as a stream.
    private static func body(of request: URLRequest) -> Data? {
      if let body = request.httpBody { return body }
      guard let stream = request.httpBodyStream else { return nil }
      stream.open()
      defer { stream.close() }
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(contentsOf: buffer[..<count])
      }
      return data
    }
  }

  static func transport() -> HTTPTransport {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Stub.self]
    return .urlSession(configuration)
  }

  static func route(_ host: String, _ route: Stub.Route) {
    Stub.routes.withLock { $0[host] = route }
  }

  static func received(_ host: String) -> HTTPRequest? {
    Stub.routes.withLock { $0[host]?.received }
  }

  @Test("send: method, headers and body out; status, headers and body back")
  func testSend() async throws {
    Self.route(
      "send.test",
      .init(status: 201, headers: ["ETag": "\"e\""], body: Data("ok".utf8), received: nil))
    let url = try #require(URL(string: "http://send.test/b/k?partNumber=1"))

    let response = try await Self.transport().send(
      HTTPRequest(
        method: "PUT", url: url, headers: ["host": "send.test", "x-amz-date": "D"],
        body: Data("part".utf8)))

    #expect(response.status == 201)
    #expect(response.etag == "e")
    #expect(response.body == Data("ok".utf8))
    let received = try #require(Self.received("send.test"))
    #expect(received.method == "PUT")
    #expect(received.url == url)
    #expect(received.headers["x-amz-date"] == "D")
    #expect(received.headers["accept-encoding"] == "identity")
    #expect(received.body == Data("part".utf8))
  }

  @Test(
    "download: a 2xx body lands in the destination, progress reports its size",
    .scratchDirectory)
  func testDownload_success() async throws {
    Self.route("get.test", .init(status: 200, headers: [:], body: Data("frame".utf8)))
    let destination = try ScratchDirectory.url.appendingPathComponent("f.part")
    let seen = Mutex<[Int64]>([])

    let response = try await Self.transport().download(
      HTTPRequest(
        method: "GET", url: try #require(URL(string: "http://get.test/b/f")), headers: [:]),
      destination, { bytes in seen.withLock { $0.append(bytes) } })

    #expect(response.status == 200)
    #expect(try Data(contentsOf: destination) == Data("frame".utf8))
    #expect(seen.withLock { $0 } == [5])
  }

  @Test("download: an error body comes back in the response, no file written", .scratchDirectory)
  func testDownload_error() async throws {
    Self.route("missing.test", .init(status: 404, headers: [:], body: Data("<Error/>".utf8)))
    let destination = try ScratchDirectory.url.appendingPathComponent("f.part")

    let response = try await Self.transport().download(
      HTTPRequest(
        method: "GET", url: try #require(URL(string: "http://missing.test/b/f")), headers: [:]),
      destination, { _ in })

    #expect(response.status == 404)
    #expect(response.body == Data("<Error/>".utf8))
    #expect(!FileManager.default.fileExists(atPath: destination.path))
  }
}

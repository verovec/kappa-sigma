import Foundation
import RemoteKit
import TestSupport
import Testing

/// Card 0184: a stalled answer ends in a timeout, which `S3Client` retries; the live
/// configuration bounds every transfer instead of URLSession's 7-day default.
extension URLSessionTransportTests {
  enum Call: String, CaseIterable, Sendable { case send, download }

  @Test("a stalled answer times out and is retryable", .scratchDirectory, arguments: Call.allCases)
  func testTimesOut(call: Call) async throws {
    let host = "stall-\(call.rawValue).test"
    Self.route(host, .init(status: 200, headers: [:], body: Data(), stalls: true))
    let configuration = HTTPTransport.configuration(idle: 0.2, transfer: 5)
    configuration.protocolClasses = [Stub.self]
    let transport = HTTPTransport.urlSession(configuration)
    let request = HTTPRequest(
      method: "GET", url: try #require(URL(string: "http://\(host)/b/k")), headers: [:])
    let destination = try ScratchDirectory.url.appendingPathComponent("k.part")

    let error = await #expect(throws: URLError.self) {
      switch call {
      case .send: _ = try await transport.send(request)
      case .download: _ = try await transport.download(request, destination, { _ in })
      }
    }

    #expect(error?.code == .timedOut)
    #expect(S3Error.isRetryable(try #require(error)))
  }

  @Test("the live configuration bounds a stall and a whole transfer")
  func testDefaultConfigurationBoundsEveryTransfer() {
    let configuration = HTTPTransport.configuration()

    #expect(configuration.timeoutIntervalForRequest == HTTPTransport.idleTimeout)
    #expect(configuration.timeoutIntervalForResource == HTTPTransport.transferTimeout)
    // A stall is seen within a minute; a transfer is bounded far below URLSession's 7 days,
    // yet a 4 GB object at 200 kB/s still fits.
    #expect(HTTPTransport.idleTimeout <= 60)
    #expect(HTTPTransport.transferTimeout < 7 * 24 * 3600)
    #expect(HTTPTransport.transferTimeout >= 4e9 / 200e3)
    // Still ephemeral: no cache on disk between launches.
    #expect((configuration.urlCache?.diskCapacity ?? 0) == 0)
  }
}

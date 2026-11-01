package import Foundation

/// The network, as two closures: tests script it, the app uses `urlSession(_:)`.
package struct HTTPTransport: Sendable {
  /// Sends a request and returns the whole response body.
  package typealias Send = @Sendable (HTTPRequest) async throws -> HTTPResponse
  /// Sends a request and writes a 2xx body to the given file, reporting bytes written so far;
  /// any other status leaves no file and returns its body in the response.
  package typealias Download =
    @Sendable (HTTPRequest, URL, @escaping @Sendable (Int64) -> Void) async throws
    -> HTTPResponse

  /// Body in memory.
  package let send: Send
  /// Body to a file.
  package let download: Download

  /// Creates a transport from its two calls.
  package init(send: @escaping Send, download: @escaping Download) {
    self.send = send
    self.download = download
  }
}

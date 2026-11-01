package import Foundation

/// The URLSession delegate that answers « no » to every HTTP redirect, so URLSession hands the 3xx back as the response.
///
/// A followed redirect would resend the signed request (`Authorization`, `x-amz-date`) to a
/// host it was not signed for: a confusing `SignatureDoesNotMatch` at best, a replayable
/// signature handed to a third party at worst.
package final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
  /// Never follows.
  ///
  /// The completion-handler form: Swift 6.4.2 crashes emitting the Objective-C thunk of the
  /// `async` one.
  package func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

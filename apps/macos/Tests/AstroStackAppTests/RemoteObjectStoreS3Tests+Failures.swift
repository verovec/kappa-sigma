import AstroStackApp
import Foundation
import ImageKit
import RemoteKit
import StackKit
import Testing

/// Card 0186: which read failures the scan stops on. The bucket's answer for every object (a key
/// that may list but not read, a service or network down) fails the scan in the service's words;
/// an object gone or shrunk since the listing (404, 416) stays that frame's skip.
@Suite("RemoteObjectStore.s3 — the bucket's failures from an object's")
struct RemoteObjectStoreS3FailureTests {
  @Test(
    "a read failure is the bucket's, or the object's alone",
    arguments: [
      (
        S3Error.service(status: 403, code: "AccessDenied", message: nil, requestID: nil)
          as any Error, true
      ),
      (S3Error.service(status: 404, code: "NoSuchKey", message: nil, requestID: nil), false),
      (S3Error.service(status: 416, code: "InvalidRange", message: nil, requestID: nil), false),
      (S3Error.service(status: 500, code: "InternalError", message: nil, requestID: nil), true),
      (S3Error.transferTimedOut(seconds: 60), true),
      (URLError(.notConnectedToInternet), true),
      (URLError(.cancelled), false),
      (CancellationError(), false),
      (FITSError.noHeaderEnd, false),
    ])
  func testBucketFailures(error: any Error, fatal: Bool) {
    #expect(RemoteObjectStore.isBucketFailure(error) == fatal, "\(error)")
  }
}

package import Foundation
package import RemoteKit
package import StackKit

// MARK: - A bucket of Settings as the remote scan's store (card 0167)

extension RemoteObjectStore {
  /// `bucket` through `client`: the listing and the ranged reads the remote scan makes.
  nonisolated package static func s3(_ client: S3Client, bucket: String) -> Self {
    Self(
      bucket: bucket,
      list: { prefix in
        try await client.list(bucket: bucket, prefix: prefix).map {
          Object(key: $0.key, size: $0.size, etag: $0.etag)
        }
      },
      get: { key, range in try await client.get(bucket: bucket, key: key, range: range) },
      // A whole frame goes through `S3Client.download` (card 0154): written to `<name>.part`,
      // its size and checksum verified, then renamed — and nothing left behind if it fails.
      fetch: { key, destination in
        let object = try await client.download(
          bucket: bucket, key: key, to: destination, expect: nil)
        return Object(key: object.key, size: object.size, etag: object.etag)
      },
      failsTheScan: isBucketFailure)
  }

  /// Whether a read's failure is the bucket's answer for every object (card 0186).
  ///
  /// A refused key, a bucket gone (`404 NoSuchBucket`), a service or network down, a transfer
  /// cut — not an object gone (`404 NoSuchKey`) or shrunk (416) since the listing, nor a
  /// cancellation, which are the frame's or nobody's.
  nonisolated package static func isBucketFailure(_ error: any Error) -> Bool {
    switch error {
    case is CancellationError: false
    case S3Error.service(404, let code, _, _): code == "NoSuchBucket"
    case S3Error.service(let status, _, _, _): status != 416
    case is S3Error: true
    case let error as URLError: error.code != .cancelled
    default: false
    }
  }

  /// The line the Données inventory shows under a remote scan whose pixel checks were not run on
  /// `count` frames, in `locale` (PO 01/11: « non vérifié (distant) », never taken as passed).
  nonisolated package static func notCheckedWords(_ count: Int, locale: Locale? = nil)
    -> LocalizedStringResource
  {
    .app("Pixel checks not run on \(count) frames (remote)", locale: locale)
  }
}

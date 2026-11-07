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
      })
  }

  /// `bucket` when its connection cannot be used: every read answers `error` as it is, so the
  /// run that needs the bucket says why (card 0185), never « no bucket ».
  nonisolated package static func refusing(bucket: String, _ error: any Error) -> Self {
    Self(
      bucket: bucket, list: { _ in throw error }, get: { _, _ in throw error },
      fetch: { _, _ in throw error })
  }

  /// The line the Données inventory shows under a remote scan whose pixel checks were not run on
  /// `count` frames, in `locale` (PO 01/11: « non vérifié (distant) », never taken as passed).
  nonisolated package static func notCheckedWords(_ count: Int, locale: Locale? = nil)
    -> LocalizedStringResource
  {
    .app("Pixel checks not run on \(count) frames (remote)", locale: locale)
  }
}

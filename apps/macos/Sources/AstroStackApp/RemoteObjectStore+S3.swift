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
      get: { key, range in try await client.get(bucket: bucket, key: key, range: range) })
  }

  /// The line the Données inventory shows under a remote scan whose pixel checks were not run on
  /// `count` frames, in `locale` (PO 01/11: « non vérifié (distant) », never taken as passed).
  nonisolated package static func notCheckedWords(_ count: Int, locale: Locale? = nil)
    -> LocalizedStringResource
  {
    .app("Pixel checks not run on \(count) frames (remote)", locale: locale)
  }
}

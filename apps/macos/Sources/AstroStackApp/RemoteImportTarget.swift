package import Foundation
package import ProjectKit

/// A bucket prefix chosen for import (card 0169): the Settings connection it is read through
/// (card 0150, by id so a rename follows), the bucket, and where in it.
package nonisolated struct RemoteImportTarget: Equatable, Sendable {
  /// The connection's id, never its name.
  package var connectionID: UUID
  /// The bucket.
  package var bucket: String
  /// The prefix inside it (`""` = the whole bucket); a trailing `/` is not significant.
  package var prefix: String

  /// A target.
  package init(connectionID: UUID, bucket: String, prefix: String) {
    self.connectionID = connectionID
    self.bucket = bucket
    self.prefix = prefix
  }

  /// The target a remote source row names (card 0168 stores all three); `nil` when the row was
  /// written by a build that did not, or its connection id is not one.
  package init?(source: ProjectSource) {
    guard let bucket = source.bucket, let prefix = source.prefix,
      let connection = source.connectionID.flatMap(UUID.init(uuidString:))
    else { return nil }
    self.init(connectionID: connection, bucket: bucket, prefix: prefix)
  }

  /// The virtual path the scan walks and the project stores — one spelling for both
  /// (`ProjectSource.remotePath`).
  package var path: String {
    ProjectSource.remotePath(bucket: bucket, prefix: prefix)
  }
}

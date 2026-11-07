package import AppKit
package import ProcessKit
package import ProjectKit

// MARK: - The open projects' capture prefixes, never an export target (R7 on remote, card 0180)

extension RemoteLocation {
  /// Where a remote night's captures are; `nil` for a local source.
  ///
  /// The bucket and prefix columns first; a row written without them still names its prefix in
  /// its virtual `s3://bucket/prefix` path, read then, so the guard never fails open on it.
  package nonisolated init?(source: ProjectSource) {
    guard source.kind == .remoteNight else { return nil }
    if let bucket = source.bucket, let prefix = source.prefix {
      self.init(bucket: bucket, prefix: prefix)
    } else if let (bucket, prefix) = ExportStageModel.split(source.path) {
      self.init(bucket: bucket, prefix: prefix)
    } else {
      return nil
    }
  }
}

extension ProjectDocument {
  /// The capture prefixes of every open project's remote nights: an export from one window
  /// never lands in the captures another window reads.
  package static func openRemoteLocations() -> [RemoteLocation] {
    remoteLocations(of: openDocuments())
  }

  /// The capture prefixes of the remote nights of `documents`, in document then import order.
  ///
  /// Read from each project's database, so a window that has not refreshed yet (or none at all)
  /// hides nothing; the window's last list only when the database cannot be read.
  package static func remoteLocations(of documents: [NSDocument]) -> [RemoteLocation] {
    documents.flatMap { document -> [RemoteLocation] in
      guard let project = document as? ProjectDocument else { return [] }
      let sources = (try? project.projectSources()) ?? project.windowModel?.sources ?? []
      return sources.compactMap(RemoteLocation.init(source:))
    }
  }
}

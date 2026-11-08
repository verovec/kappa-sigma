package import AppKit
internal import OSLog
package import ProcessKit
package import ProjectKit

// MARK: - The open projects' capture prefixes, never an export target (R7 on remote, card 0180)

extension RemoteLocation {
  /// Where a remote night's captures are (`ProjectSource.remoteFolder`); `nil` for a local source.
  package nonisolated init?(source: ProjectSource) {
    guard let folder = source.remoteFolder else { return nil }
    self.init(bucket: folder.bucket, prefix: folder.prefix)
  }
}

extension ProjectDocument {
  private static let remoteLogger = Logger(subsystem: "fr.astrostack", category: "App/export")

  /// The capture prefixes of every open project's remote nights: an export from one window
  /// never lands in the captures another window reads.
  package static func openRemoteLocations() -> [RemoteLocation] {
    remoteLocations(of: openDocuments())
  }

  /// The capture prefixes of the remote nights of `documents`, in document then import order.
  ///
  /// Read from each project's database, so a window that has not refreshed yet (or none at all)
  /// hides nothing. A database that cannot be read leaves the window's last list, logged: there
  /// is no prefix to refuse without one.
  package static func remoteLocations(of documents: [NSDocument]) -> [RemoteLocation] {
    documents.flatMap { document -> [RemoteLocation] in
      guard let project = document as? ProjectDocument else { return [] }
      let sources: [ProjectSource]
      do {
        sources = try project.projectSources() ?? project.windowModel?.sources ?? []
      } catch {
        remoteLogger.error("reading the capture sources failed: \(error)")
        sources = project.windowModel?.sources ?? []
      }
      return sources.compactMap(RemoteLocation.init(source:))
    }
  }
}

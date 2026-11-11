internal import CryptoKit
package import Foundation
package import StackKit

extension RemoteFrameCache {
  /// The kept frames of the project saved at `project`, under `scratch` (card 0191).
  ///
  /// One folder a project, named after the package and a digest of where it is saved: two
  /// projects never share copies, so removing one project's (card 0192) cannot touch another's.
  package nonisolated init(project: URL, scratch: URL) {
    let path = project.standardizedFileURL.path
    let digest = SHA256.hash(data: Data(path.utf8)).prefix(4)
      .map { String(format: "%02x", $0) }.joined()
    let name = project.deletingPathExtension().lastPathComponent
    self.init(
      root: scratch.appendingPathComponent(Self.folderName, isDirectory: true)
        .appendingPathComponent("\(name)-\(digest)", isDirectory: true))
  }
}

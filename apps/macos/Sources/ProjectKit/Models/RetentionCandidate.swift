package import Foundation

/// A stack the retention policy offers: its project, its row and its folder's size.
package struct RetentionCandidate: Equatable, Sendable, Identifiable {
  /// The package holding it.
  package var project: URL
  /// Its row.
  package var stack: ProjectStack
  /// Its folder's bytes on disk.
  package var bytes: Int64

  /// A candidate.
  package init(project: URL, stack: ProjectStack, bytes: Int64) {
    self.project = project
    self.stack = stack
    self.bytes = bytes
  }

  /// The project and the stack.
  package var id: String { "\(project.path)#\(stack.id)" }
}

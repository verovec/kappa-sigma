internal import Foundation
package import ProjectKit

/// One stack as the Storage section lists it (card 0114): its row, its folder's size on disk
/// (measured on demand, never stored) and how often it was exported.
package nonisolated struct StackStorageRow: Equatable, Identifiable, Sendable {
  /// The stack.
  package let stack: ProjectStack
  /// Its folder's bytes on disk.
  package let bytes: Int64
  /// Exports recorded for it; 0 = never exported.
  package let exports: Int

  /// A row.
  package init(stack: ProjectStack, bytes: Int64, exports: Int) {
    self.stack = stack
    self.bytes = bytes
    self.exports = exports
  }

  /// The stack's id.
  package var id: Int64 { stack.id }
}

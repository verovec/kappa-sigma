/// One image of a stack (a role: `rgb`, `L`, `Ha`…) and the head of its history.
package struct ProjectImage: Equatable, Sendable {
  /// Row id.
  package let id: Int64
  /// The stack it belongs to.
  package let stackID: Int64
  /// The image's role in the stack.
  package let role: String
  /// The current history step, `nil` before the first process.
  package let headStepID: Int64?
  /// Creation time, Unix milliseconds.
  package let createdAt: Int64
  /// Last update time, Unix milliseconds.
  package let updatedAt: Int64
}

/// One broken rule of the module graph.
package struct BoundaryViolation: Equatable, Sendable, CustomStringConvertible {
  /// A human-readable statement of the violation.
  package let description: String
}

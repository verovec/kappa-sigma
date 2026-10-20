/// A target declared in `Package.swift`, with the names of the targets and products it uses.
package struct DeclaredTarget: Equatable, Sendable {
  /// The manifest call that declared the target.
  package enum Kind: Equatable, Sendable {
    /// `.target(…)`
    case library
    /// `.executableTarget(…)`
    case executable
    /// `.testTarget(…)`
    case test
  }

  /// The target name.
  package let name: String
  /// How the target was declared.
  package let kind: Kind
  /// Target and product names, in declaration order (`.product(name:)` contributes its name).
  package let dependencies: [String]

  /// Creates a declared target.
  package init(name: String, kind: Kind, dependencies: [String]) {
    self.name = name
    self.kind = kind
    self.dependencies = dependencies
  }
}

/// A bundle produced by preprocessing (0057) or read from a legacy run (0043).
package struct ProjectStack: Equatable, Sendable {
  /// Row id.
  package let id: Int64
  /// The bundle folder, relative to the package.
  package let bundlePath: String
  /// The sources the stack was built from, ascending.
  package let sourceIDs: [Int64]
  /// The run parameters, as JSON.
  package let paramsJSON: String
  /// Creation time, Unix milliseconds.
  package let createdAt: Int64
  /// Last update time, Unix milliseconds.
  package let updatedAt: Int64
}

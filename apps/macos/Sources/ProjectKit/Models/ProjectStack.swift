/// A bundle produced by preprocessing (0057) or read from a legacy run (0043).
package struct ProjectStack: Equatable, Sendable, Identifiable {
  /// Row id.
  package let id: Int64
  /// The bundle folder, relative to the package.
  package let bundlePath: String
  /// The sources the stack was built from, ascending.
  package let sourceIDs: [Int64]
  /// The run parameters, as JSON.
  package let paramsJSON: String
  /// The object the run stacked (card 0095); `""` for a stack of every light of its sources.
  package let object: String
  /// The run scope as JSON (the app's `RunScope`); `nil` for a stack recorded before 0095.
  package let scopeJSON: String?
  /// Creation time, Unix milliseconds.
  package let createdAt: Int64
  /// Last update time, Unix milliseconds.
  package let updatedAt: Int64

  /// A stack row.
  package init(
    id: Int64, bundlePath: String, sourceIDs: [Int64], paramsJSON: String, object: String = "",
    scopeJSON: String? = nil, createdAt: Int64, updatedAt: Int64
  ) {
    self.id = id
    self.bundlePath = bundlePath
    self.sourceIDs = sourceIDs
    self.paramsJSON = paramsJSON
    self.object = object
    self.scopeJSON = scopeJSON
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

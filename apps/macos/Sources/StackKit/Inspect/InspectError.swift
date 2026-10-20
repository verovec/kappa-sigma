/// Why an inspection request was refused, with what the user can act on.
package enum InspectError: Error, Equatable, Sendable {
  /// A filter-set override that is not `unknown`, `broadband` or `dualband`.
  case unknownFilterSet(String)
  /// A colour-model choice that is not `auto`, `mono` or `osc`.
  case unknownColorChoice(String)
  /// The asserted colour model matches none of the scan's lights.
  case noLightsForColorModel(choice: String, dropped: Int)
  /// A capture folder that does not exist or cannot be listed (path, permissions, TCC).
  case unreadableFolder(String)
  /// `scan` was called without a folder.
  case noFolders
}

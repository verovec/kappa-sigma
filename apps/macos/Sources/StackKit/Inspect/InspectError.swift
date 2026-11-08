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
  /// A frame of an S3 prefix the bucket refused to read (card 0186): its virtual path and the
  /// service's own words. Every frame would fail the same way, so the scan stops (R2).
  case remoteUnreadable(path: String, reason: String)
  /// An S3 prefix holding more objects than a scan reads (card 0186): its virtual path and the
  /// limit.
  case remoteTooLarge(path: String, limit: Int)
}

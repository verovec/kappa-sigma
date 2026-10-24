/// Why the sky-object catalogue could not be read (card 0129).
package enum SkyCatalogueError: Error, Equatable, Sendable {
  /// No Siril at `path`: its lists come with it, and the app shows the install card (R2).
  case sirilMissing(path: String)
  /// Siril is there but its catalogue folder is not.
  case catalogueMissing(folder: String)
  /// A list could not be read.
  case unreadable(file: String, reason: String)
  /// A list lacks its `name`, `ra` or `dec` column.
  case missingColumns(file: String)
}

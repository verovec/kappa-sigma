/// Why a `.astrostack` package could not be created or opened; each case carries the path.
public enum ProjectPackageError: Error, Equatable, Sendable {
  /// Nothing at the path, or a plain file where a package folder was expected.
  case notAPackage(path: String)
  /// The package folder has no `project.db`.
  case missingDatabase(path: String)
  /// `project.db` is an SQLite database that AstroStack did not create.
  case foreignDatabase(path: String)
  /// Something already exists where a new package was to be created.
  case alreadyExists(path: String)
  /// Another running process holds the package open (card 0147): its pid.
  case openElsewhere(path: String, pid: Int32)
}

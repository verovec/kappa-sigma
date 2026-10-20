/// Errors raised while locating the package or reading its files.
package enum ModuleBoundaryError: Error, Equatable {
  /// No `Package.swift` above the given source file.
  case packageNotFound(from: String)
}

internal import AppKit
internal import ProjectKit

extension ProjectDocument {
  /// Opens the package at `url` as this window's (card 0147); when another running AstroStack
  /// holds it, the refusal reaches the user as a sentence, not NSDocument's generic one.
  static func openOwned(_ url: URL) throws -> ProjectPackage {
    do {
      return try ProjectPackage.open(at: url)
    } catch let error as ProjectPackageError {
      guard case .openElsewhere = error else { throw error }
      throw CocoaError(
        .fileReadNoPermission,
        userInfo: [NSLocalizedDescriptionKey: String(localized: UserFacingError(error).message)])
    }
  }
}

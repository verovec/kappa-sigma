package import AppKit
internal import ProjectKit

extension ProjectDocument {
  /// Refuses, with the same sentence, to write over the package at `url` while another running
  /// AstroStack holds it (card 0147): a Save As would swap its `project.db` from under it.
  package static func refuseHeldElsewhere(_ url: URL) throws {
    guard ProjectOwner.heldElsewhere(in: url) != nil else { return }
    throw CocoaError(
      .fileWriteNoPermission,
      userInfo: [
        NSLocalizedDescriptionKey: String(
          localized: UserFacingError.projectOpenElsewhere(path: url.path).message)
      ])
  }

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

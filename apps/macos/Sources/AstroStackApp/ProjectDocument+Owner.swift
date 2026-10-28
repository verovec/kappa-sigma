package import AppKit
internal import ProjectKit

extension ProjectDocument {
  /// A refusal NSDocument shows as its sentence (`UserFacingError`), not a generic one.
  static func refusal(_ code: CocoaError.Code, _ error: UserFacingError) -> CocoaError {
    CocoaError(code, userInfo: [NSLocalizedDescriptionKey: String(localized: error.message)])
  }

  /// Refuses to write over the package at `url` while another running AstroStack holds it, or
  /// another window of this one shows it (card 0147): a Save As would swap its `project.db` from
  /// under them.
  package static func refuseHeldElsewhere(_ url: URL) throws {
    if ProjectOwner.heldElsewhere(in: url) != nil {
      throw refusal(.fileWriteNoPermission, .projectOpenElsewhere(path: url.path))
    }
    if NSDocumentController.shared.document(for: url) != nil {
      throw refusal(.fileWriteNoPermission, .projectOpenInWindow(path: url.path))
    }
  }

  /// Opens the package at `url` as this window's (card 0147); when another running AstroStack
  /// holds it, the refusal reaches the user as a sentence, not NSDocument's generic one.
  static func openOwned(_ url: URL) throws -> ProjectPackage {
    do {
      return try ProjectPackage.open(at: url)
    } catch let error as ProjectPackageError {
      guard case .openElsewhere = error else { throw error }
      throw refusal(.fileReadNoPermission, UserFacingError(error))
    }
  }
}

package import Foundation
package import ProjectKit
package import StackKit

/// The calibration library indexed into a project, once: concurrent scans share one reindex.
package actor LibraryIndex {
  private let store: ProjectStore?
  private let folder: URL
  private var indexed: [CalibrationMaster]?

  /// The library at `folder`, indexed into `store` on first use.
  package init(store: ProjectStore?, folder: URL) {
    self.store = store
    self.folder = folder
  }

  /// The indexed masters; empty without a store or a library folder.
  ///
  /// A library macOS or its permissions refuse is `UserFacingError.documentsAccess`, never an
  /// empty library: every master would silently be planned as « build » (R2).
  package func masters() throws -> [CalibrationMaster] {
    if let indexed { return indexed }
    var masters: [CalibrationMaster] = []
    if let store, try Self.exists(folder) {
      try CalibrationLibrary(folder: folder).reindex(into: store)
      masters = try CalibrationLibrary.masters(in: store)
    }
    indexed = masters
    return masters
  }

  /// Whether `folder` exists and can be listed: `false` when it is absent, the access error when
  /// it is there but refused (`fileExists` says « absent » for a folder privacy settings hide).
  nonisolated static func exists(_ folder: URL) throws -> Bool {
    do {
      _ = try FileManager.default.contentsOfDirectory(atPath: folder.path)
      return true
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return false
    } catch let error as CocoaError where error.code == .fileReadNoPermission {
      throw UserFacingError.documentsAccess(path: folder.path)
    } catch let error as CocoaError {
      let posix = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
      if posix == Int(EPERM) || posix == Int(EACCES) {
        throw UserFacingError.documentsAccess(path: folder.path)
      }
      throw error
    }
  }

  /// Forgets the index: a master was just written into the library.
  package func invalidate() {
    indexed = nil
  }
}

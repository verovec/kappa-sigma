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
    } catch {
      throw refusal(error, path: folder.path)
    }
  }

  /// What listing the library at `path` failing with `error` tells the user.
  ///
  /// A privacy refusal (EPERM: macOS has not granted Documents) says where to allow it; plain
  /// permissions (EACCES) are the library's own « cannot be read »; anything else as it came.
  package nonisolated static func refusal(_ error: any Error, path: String) -> any Error {
    let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
    switch underlying.map({ Int32($0.code) }) {
    case EPERM: return UserFacingError.documentsAccess(path: path)
    case EACCES: return CalibrationError.unreadableLibrary(path)
    default: return error
    }
  }

  /// Forgets the index: a master was just written into the library.
  package func invalidate() {
    indexed = nil
  }
}

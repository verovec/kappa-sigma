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
  package func masters() throws -> [CalibrationMaster] {
    if let indexed { return indexed }
    var masters: [CalibrationMaster] = []
    if let store, FileManager.default.fileExists(atPath: folder.path) {
      try CalibrationLibrary(folder: folder).reindex(into: store)
      masters = try CalibrationLibrary.masters(in: store)
    }
    indexed = masters
    return masters
  }

  /// Forgets the index: a master was just written into the library.
  package func invalidate() {
    indexed = nil
  }
}

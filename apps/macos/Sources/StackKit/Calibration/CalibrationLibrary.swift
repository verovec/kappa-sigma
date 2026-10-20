package import Foundation
internal import ImageKit
package import ProjectKit

/// The calibration library folder (`~/Documents/astro/library`, reused as is) and its index in the
/// project database (`calibration_masters`). The folder is the truth: a master is its file name
/// (`MasterName`), its `.sig` (pool hash, depth) and its FITS header (pixel size); `reindex`
/// makes the index equal the folder.
package struct CalibrationLibrary: Sendable {
  package var folder: URL

  /// The library at `folder`.
  package init(folder: URL) {
    self.folder = folder
  }

  /// Every master file at the top of the folder, read; other files and sub-folders are ignored.
  package func scan() throws -> [CalibrationMasterRow] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
      throw CalibrationError.unreadableLibrary(folder.path)
    }
    return names.sorted().compactMap { name in
      Self.row(folder.appendingPathComponent(name).path)
    }
  }

  /// Rebuilds the index from the folder; returns what changed.
  @discardableResult
  package func reindex(into store: ProjectStore) throws -> CalibrationSyncReport {
    try store.syncCalibrationMasters(scan())
  }

  /// The indexed masters, as candidates for matching (all `fromLibrary`).
  package static func masters(in store: ProjectStore) throws -> [CalibrationMaster] {
    try store.calibrationMasters().compactMap(master)
  }

  /// The index row of one file, `nil` when it is not a master.
  static func row(_ path: String) -> CalibrationMasterRow? {
    guard let master = MasterName.parse(path),
      let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    else { return nil }
    var row = CalibrationMasterRow(path: path, type: master.type.rawValue)
    row.filter = master.filter
    row.exposureMs = master.exposureMs
    row.gain = master.gain
    row.offset = master.offset
    row.bin = master.bin
    row.tempMilliC = master.tempMilliC
    row.hasTemp = master.hasTemp
    row.session = master.session
    row.recipe = master.recipe
    if let sig = PoolSignature.read(at: PoolSignature.sidecar(of: path)) {
      row.poolHash = sig.hash
      row.frameCount = sig.frameCount
    }
    if let size = DimensionGuard.dimensions(path) {
      row.width = size.width
      row.height = size.height
    }
    row.fileBytes = (attributes[.size] as? Int) ?? 0
    let modified = (attributes[.modificationDate] as? Date) ?? .distantPast
    row.fileMtimeMs = Int64((modified.timeIntervalSince1970 * 1000).rounded())
    return row
  }

  /// A row back as a library master.
  static func master(_ row: CalibrationMasterRow) -> CalibrationMaster? {
    guard let type = MasterType(rawValue: row.type) else { return nil }
    var master = CalibrationMaster(type: type, path: row.path)
    master.filter = row.filter
    master.exposureMs = row.exposureMs
    master.gain = row.gain
    master.offset = row.offset
    master.bin = row.bin
    master.tempMilliC = row.tempMilliC
    master.hasTemp = row.hasTemp
    master.frameCount = row.frameCount
    master.session = row.session
    master.recipe = row.recipe
    master.fromLibrary = true
    return master
  }
}

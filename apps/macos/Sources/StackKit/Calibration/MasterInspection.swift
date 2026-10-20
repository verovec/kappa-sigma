package import Foundation
internal import ImageKit

/// One calibration master as the Import sheet inspects it: what its name and `.sig` say, its
/// size, when it was built, its statistics and the thresholds they cross (card 0071).
package struct MasterInspection: Equatable, Sendable {
  package var path: String
  /// The master its file name describes (type, filter, exposure, gain, temperature, night).
  package var master: CalibrationMaster
  package var width: Int
  package var height: Int
  package var planes: Int
  /// Frames stacked, from the `.sig`; 0 when unproven.
  package var frames: Int
  /// The file's modification time: when Siril wrote it.
  package var builtAt: Date
  package var stats: MasterStats
  package var warnings: [MasterWarning]

  /// An inspection from its parts (what `read` measures; tests build one directly).
  package init(
    path: String, master: CalibrationMaster, width: Int, height: Int, planes: Int, frames: Int,
    builtAt: Date, stats: MasterStats, warnings: [MasterWarning]
  ) {
    self.path = path
    self.master = master
    self.width = width
    self.height = height
    self.planes = planes
    self.frames = frames
    self.builtAt = builtAt
    self.stats = stats
    self.warnings = warnings
  }

  /// Reads and measures the master at `path` (seconds for a 26 Mpx master: call it off the main
  /// actor).
  package static func read(_ path: String) throws -> Self {
    guard let master = MasterName.parse(path) else {
      throw CalibrationError.notAMaster(path)
    }
    let url = URL(fileURLWithPath: path)
    let image = try FITSFile.read(at: url).image()
    let count = image.width * image.height
    guard count > 0, !image.planes.isEmpty, image.planes.allSatisfy({ $0.count == count }) else {
      throw CalibrationError.unreadableMaster(path)
    }
    let stats = MasterStats(
      type: master.type, width: image.width, height: image.height, planes: image.planes)
    let modified =
      (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    return Self(
      path: path, master: master, width: image.width, height: image.height,
      planes: image.planes.count,
      frames: PoolSignature.read(at: PoolSignature.sidecar(of: path))?.frameCount ?? 0,
      builtAt: modified ?? .distantPast, stats: stats, warnings: MasterWarning.all(for: stats))
  }
}

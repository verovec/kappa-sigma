package import Foundation
internal import OSLog

/// A finished stack folder trimmed to what its bundle reads (card 0114).
///
/// Once `bundle.json` is written the Studio opens only the layers it names, so the run's other
/// intermediate FITS at the top of the folder (`aligned_*`, `combine_*`, an unnamed `combined`)
/// are dead weight: lossless to remove. Masters stay (a master is the run's result, card 0071
/// inspects it), and so does everything that is not a FITS file: previews, records, `history/`.
package enum StackFolder {
  /// One file the trim removed and the bytes it took on disk.
  package struct Trimmed: Equatable, Sendable {
    /// Its name in the folder.
    package var name: String
    /// The bytes it took.
    package var bytes: Int64
  }

  /// A trim refused: the bundle names a layer that is not a file of the folder itself.
  package struct Refusal: Error, Equatable {
    /// The layer file refused.
    package var file: String
  }

  /// Removes the FITS at the top of `folder` that `bundle` does not name, masters excepted.
  ///
  /// Returns the removed files by name; a file that cannot be removed is logged and kept. A layer
  /// named outside the folder refuses the trim before anything goes: the bundle would not be the
  /// folder's.
  @discardableResult
  package static func trim(_ folder: URL, bundle: LinearBundle) throws -> [Trimmed] {
    let named = Set(bundle.layers.map(\.file))
    if let foreign = named.first(where: { $0.contains("/") || $0.hasPrefix(".") }) {
      throw Refusal(file: foreign)
    }
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
    var trimmed: [Trimmed] = []
    for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    where isIntermediate(name) && !named.contains(name) {
      let file = folder.appendingPathComponent(name)
      // One file that cannot go (vanished, permissions) leaves the others to trim and to report.
      do {
        let values = try file.resourceValues(forKeys: keys)
        guard values.isRegularFile == true else { continue }
        try FileManager.default.removeItem(at: file)
        trimmed.append(Trimmed(name: name, bytes: Int64(values.totalFileAllocatedSize ?? 0)))
      } catch {
        logger.error("could not trim \(file.path): \(error)")
      }
    }
    let total = trimmed.reduce(Int64(0)) { $0 + $1.bytes }
    logger.notice("trimmed \(trimmed.count) files (\(total) bytes) from \(folder.path)")
    return trimmed
  }

  /// A FITS file that is not a master.
  private static func isIntermediate(_ name: String) -> Bool {
    let lower = name.lowercased()
    return (lower.hasSuffix(".fits") || lower.hasSuffix(".fit")) && !lower.hasPrefix("master_")
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "StackKit/stackfolders")
}

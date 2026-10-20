internal import Foundation
internal import ImageKit

/// Gives every channel master the first solved channel's parity (`normalizeMasterParity`).
///
/// Run before the masters are co-registered: star registration matches asterisms by chirality,
/// so an opposite-parity master never registers. Masters whose parity cannot be read stay as
/// they are.
package struct ParityNormalizer: Sendable {
  /// The throwaway image a probe saves beside the master.
  static let probeName = "_parity_probe"

  package var runner: SirilRunner
  /// The `platesolve` coordinates (nil: Siril reads the header).
  package var coordinates: String?

  /// A normalizer running probes through `runner`.
  package init(runner: SirilRunner, coordinates: String? = nil) {
    self.runner = runner
    self.coordinates = coordinates
  }

  /// Probes each master in `ordered` order (`masters`: filter → absolute path) and mirrors the
  /// ones whose parity differs from the reference.
  package func normalize(
    _ masters: [String: String], ordered: [String], journal: inout PreprocessJournal
  ) async throws {
    guard ordered.count >= 2 else { return }
    var signs: [String: Int] = [:]
    for filter in ordered {
      signs[filter] = try await probe(masters[filter] ?? "")
    }
    guard let reference = ordered.first(where: { signs[$0] != 0 }) else {
      journal.warn("channel parity check skipped (no master could be plate-solved)", live: false)
      return
    }
    for filter in ordered where signs[filter] != 0 && signs[filter] != signs[reference] {
      try await mirror(
        masters[filter] ?? "", filter: filter, reference: reference, journal: &journal)
    }
  }

  /// The parity sign of a master's solved WCS: −1 (East-left), +1 (mirrored), 0 when unsolved.
  func probe(_ master: String) async throws -> Int {
    let (folder, base) = Self.split(master)
    let probe = folder.appendingPathComponent(Self.probeName + ".fits")
    defer { try? FileManager.default.removeItem(at: probe) }
    do {
      _ = try await runner.run(
        SirilScripts.parityProbe(load: base, out: Self.probeName, coords: coordinates), folder
      ) { _ in }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return 0
    }
    guard let determinant = try? FITSFile.read(at: probe).header.cdDeterminant else { return 0 }
    return determinant < 0 ? -1 : 1
  }

  private func mirror(
    _ master: String, filter: String, reference: String, journal: inout PreprocessJournal
  ) async throws {
    let (folder, base) = Self.split(master)
    do {
      _ = try await runner.run(SirilScripts.mirrorFrames([base]), folder) { _ in }
      journal.warn(
        "channel \(filter): master mirror-corrected (opposite parity vs \(reference)) "
          + "before channel alignment", live: false)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      journal.warn(
        "channel \(filter): parity flip failed (\(ChannelStacker.describe(error))) "
          + "— master left mirrored",
        live: false)
    }
  }

  /// A master's folder and Siril load name (`masterDirBase`).
  static func split(_ path: String) -> (folder: URL, base: String) {
    let url = URL(fileURLWithPath: path)
    return (url.deletingLastPathComponent(), url.deletingPathExtension().lastPathComponent)
  }
}

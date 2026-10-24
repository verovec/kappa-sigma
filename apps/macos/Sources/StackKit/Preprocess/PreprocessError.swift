internal import Foundation

/// Why a preprocessing step failed.
package enum PreprocessError: Error, Equatable, Sendable {
  /// Grading left fewer frames than Siril's two-frame stack minimum.
  case belowStackMinimum(survivors: Int, registered: Int)
  /// The bundle's layers do not share one geometry.
  case mixedDimensions([String])
  /// Another run already holds this target's output folder.
  case targetBusy(String)
  /// No channel produced a master.
  case noChannels([String])
  /// Mono and colour lights together: no single run stacks them.
  case mixedColorModel
  /// Lights of several objects together (card 0095): one run stacks one object, never a majority.
  case mixedObjects([String])
  /// No light set to stack: the capture holds none, or a scope whose sets the re-planned scan no
  /// longer has (card 0095).
  case noLights
  /// The scan moved since the series were chosen: this object has light sets the scope does not
  /// list (card 0095); rescan and choose again rather than stack a part in silence.
  case scopeOutdated([String])
  /// The run's scratch estimate exceeds the room left on the scratch folder's volume (card
  /// 0098): refused before Siril starts, never left to fail mid-run on a full disk.
  case scratchFull(neededBytes: Int64, availableBytes: Int64, folder: String)
}

extension PreprocessError: LocalizedError {
  package var errorDescription: String? {
    switch self {
    case .belowStackMinimum(let survivors, let registered):
      "\(survivors) of \(registered) registered frames survived grading — "
        + "below Siril's two-frame stack minimum"
    case .mixedDimensions(let layers):
      "the bundle's layers have different dimensions: \(layers.joined(separator: ", "))"
    case .targetBusy(let path): "another run is already writing \(path)"
    case .noChannels(let errors):
      "no channel could be stacked: \(errors.joined(separator: "; "))"
    case .mixedColorModel: "the capture mixes mono and colour lights — stack them as separate runs"
    case .mixedObjects(let objects):
      "the lights span several objects (\(Self.names(objects))) — choose the series of one object "
        + "per run"
    case .noLights:
      "no light set to stack — the capture holds none, or the series chosen are not in this scan"
    case .scopeOutdated(let sets):
      "the scan moved since the series were chosen (\(sets.count) set(s) changed) — "
        + "rescan and choose again"
    case .scratchFull(let needed, let available, let folder):
      "the run needs ~\(Self.gigabytes(needed)) of scratch in \(folder), "
        + "\(Self.gigabytes(available)) free — free some space or choose another scratch folder"
    }
  }

  /// A byte count as the engine's messages write it (decimal units, `81 GB`).
  static func gigabytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .decimal).locale(Locale(identifier: "en_US_POSIX")))
  }

  /// Object names as the message lists them; an empty OBJECT reads as such.
  package static func names(_ objects: [String]) -> String {
    objects.map { $0.isEmpty ? "(no OBJECT)" : $0 }.joined(separator: ", ")
  }
}

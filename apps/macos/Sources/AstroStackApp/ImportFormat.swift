internal import Foundation
package import StackKit

/// How the Import sheet writes the plan's values: text only, nothing decided here.
package nonisolated enum ImportFormat {
  /// `300 s`, `2.5 s`, `5 ms`; `—` when the type carries no exposure.
  package static func exposure(_ ms: Int) -> String {
    guard ms > 0 else { return "—" }
    guard ms >= 1000 else { return "\(ms) ms" }
    let seconds = Double(ms) / 1000
    return seconds == seconds.rounded() ? "\(Int(seconds)) s" : "\(seconds) s"
  }

  /// The temperature cluster of the thermal types (`−17 °C`); `—` for the others.
  package static func temperature(_ key: SetKey) -> String {
    guard key.type.usesTemperature else { return "—" }
    return key.tempBucketC < 0 ? "−\(-key.tempBucketC) °C" : "\(key.tempBucketC) °C"
  }

  /// Gain, offset and binning, as masters name them.
  package static func sensor(_ key: SetKey) -> String {
    "g\(key.gain) o\(key.offset) b\(key.bin)"
  }

  /// A night's heading.
  package static func night(_ session: String) -> String {
    session.isEmpty ? "Shared calibration and undated frames" : "Night of \(session)"
  }

  /// What a calibration cell will do.
  package static func status(_ status: ImportPlan.Status) -> String {
    switch status {
    case .library(let path, let frames):
      let name = URL(fileURLWithPath: path).lastPathComponent
      return frames > 0 ? "library: \(name) (\(frames) frames)" : "library: \(name)"
    case .build(let frames):
      return "build from \(frames) frame\(frames == 1 ? "" : "s")"
    case .excluded(let proposed):
      return "excluded (proposed: \(Self.status(proposed)))"
    case .missing:
      return "missing"
    }
  }
}

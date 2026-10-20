package import Foundation
package import StackKit

/// How the Import sheet writes the plan's values: text only, nothing decided here.
///
/// Sentences come from the app's catalog; units and numbers are written here until
/// `AstroFormat` (card 0074) formats them per locale.
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
  package static func night(_ session: String) -> LocalizedStringResource {
    session.isEmpty ? .app("Shared calibration and undated frames") : .app("Night of \(session)")
  }

  /// What a calibration cell will do.
  package static func status(_ status: ImportPlan.Status) -> LocalizedStringResource {
    switch status {
    case .library(let path, let frames):
      let name = URL(fileURLWithPath: path).lastPathComponent
      return frames > 0
        ? .app("library: \(name) (\(Self.frames(frames)))") : .app("library: \(name)")
    case .build(let frames):
      return .app("build from \(frames) frames")
    case .excluded(let proposed):
      return .app("excluded (proposed: \(Self.status(proposed)))")
    case .missing:
      return .app("missing")
    }
  }

  /// A frame count, singular or plural.
  package static func frames(_ count: Int) -> LocalizedStringResource {
    .app("\(count) frames")
  }
}

package import Foundation
package import StackKit

/// How the Import sheet writes the plan's values: text only, nothing decided here.
///
/// Sentences come from the app's catalog, values from `AstroFormat` in the view's locale; this
/// type only holds the plan's rules (which types carry a temperature, how masters name a sensor).
package nonisolated enum ImportFormat {
  /// The temperature cluster of the thermal types (`−17 °C`); `—` for the others.
  package static func temperature(_ key: SetKey, in format: AstroFormat) -> String {
    key.type.usesTemperature ? format.temperature(celsius: key.tempBucketC) : "—"
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
        ? .app("library: \(name) (\(AstroFormat.frameCount(frames)))") : .app("library: \(name)")
    case .build(let frames):
      return .app("build from \(frames) frames")
    case .excluded(let proposed):
      return .app("excluded (proposed: \(Self.status(proposed)))")
    case .missing:
      return .app("missing")
    }
  }
}

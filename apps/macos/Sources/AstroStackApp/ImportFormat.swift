package import FilterKit
package import Foundation
package import RenderKit
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

  /// The gain alone, as masters name it (`g100`).
  package static func gain(_ gain: Int, locale: Locale) -> String {
    String(localized: .app("g\(gain)", locale: locale))
  }

  /// Gain, offset and binning, as masters name them.
  package static func sensor(_ key: SetKey) -> String {
    "g\(key.gain) o\(key.offset) b\(key.bin)"
  }

  /// A light set's filter in words: the glossary's term (`Hα`, `RGB` for one-shot colour), a
  /// custom name as the capture wrote it, then the clip filter when known (« RGB · bi-bande »).
  package static func filter(_ name: String, filterSet: FilterSet, locale: Locale) -> String {
    let filter =
      name == Filter.color
      ? AppGlossary.label(LinearBundle.Role.rgb.termID, locale: locale)
      : Filter(rawValue: name).map { AppGlossary.label($0.termID, locale: locale) } ?? name
    guard filterSet.isKnown else { return filter }
    return filter + " · " + AppGlossary.label(filterSet.termID, locale: locale)
  }

  /// A night's heading.
  package static func night(_ session: String) -> LocalizedStringResource {
    session.isEmpty ? .app("Shared calibration and undated frames") : .app("Night of \(session)")
  }

  /// A calibration cell's badge: covered is fine, skipped is the user's choice, a gap needs
  /// attention.
  package static func badge(_ status: ImportPlan.Status) -> DesignStatus {
    switch status {
    case .library, .build: .ok
    case .excluded: .unavailable
    case .missing: .attention
    }
  }

  /// The library file a calibration cell applies; `nil` for a master the run builds from the
  /// capture, an excluded one, or a gap.
  package static func libraryPath(_ status: ImportPlan.Status) -> String? {
    if case .library(let path, _) = status, !path.isEmpty { path } else { nil }
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

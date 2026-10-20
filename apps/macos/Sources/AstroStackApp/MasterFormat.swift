package import Foundation
package import StackKit

/// How the master disclosure writes its values: text only; numbers wait for AstroFormat (0074).
package nonisolated enum MasterFormat {
  /// A normalised pixel value, five significant digits.
  package static func value(_ value: Double) -> String {
    String(format: "%.5g", value)
  }

  /// A percentage with two decimals and its sign when positive (`+3.1 %`).
  package static func percent(_ value: Double) -> String {
    String(format: value > 0 ? "+%.2f %%" : "%.2f %%", value)
  }

  /// The file name of a master.
  package static func name(_ path: String) -> String {
    URL(fileURLWithPath: path).lastPathComponent
  }

  /// Why an alternative is, or is not, applied.
  package static func verdict(_ verdict: MasterAlternative.Verdict) -> LocalizedStringResource {
    switch verdict {
    case .chosen: .app("applied")
    case .matches: .app("matches, ranked below the applied one")
    case .needsForce: .app("applied only when forced (gain, exposure or temperature differs)")
    // StackKit's note, as it words it.
    case .otherSensor(let note) where note.isEmpty: .app("another sensor")
    case .otherSensor(let note): .app("\(note)")
    }
  }
}

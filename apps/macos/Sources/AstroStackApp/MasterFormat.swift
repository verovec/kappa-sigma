internal import Foundation
package import StackKit

/// How the master disclosure writes its values: text only.
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
  package static func verdict(_ verdict: MasterAlternative.Verdict) -> String {
    switch verdict {
    case .chosen: "applied"
    case .matches: "matches, ranked below the applied one"
    case .needsForce: "applied only when forced (gain, exposure or temperature differs)"
    case .otherSensor(let note): note.isEmpty ? "another sensor" : note
    }
  }
}

package import Foundation
package import StackKit

/// How the master disclosure words its values; numbers come from `AstroFormat`.
package nonisolated enum MasterFormat {
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

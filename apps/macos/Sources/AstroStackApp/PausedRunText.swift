package import Foundation
package import ProjectKit
internal import StackKit

/// How a paused run is named in the Stacking stage (card 0097).
package enum PausedRunText {
  /// « Paused run 20261021_210000 — stacked: RGB · left: RGB-dualband »; `locale` pins the
  /// language (tests), the user's otherwise.
  package static func words(_ paused: ProjectStack, locale: Locale? = nil)
    -> LocalizedStringResource
  {
    let runID = URL(fileURLWithPath: paused.bundlePath).lastPathComponent
    let checkpoint = paused.checkpointJSON.flatMap {
      try? JSONDecoder().decode(PreprocessCheckpoint.self, from: Data($0.utf8))
    }
    let done = checkpoint?.lanesDone.joined(separator: ", ") ?? ""
    let left = checkpoint?.lanesLeft.joined(separator: ", ") ?? ""
    return .app("Paused run \(runID) — stacked: \(done) · left: \(left)", locale: locale)
  }
}

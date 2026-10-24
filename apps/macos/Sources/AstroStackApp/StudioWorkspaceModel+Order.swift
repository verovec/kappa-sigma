package import Foundation
package import ProcessKit

/// The usual processing order in the Studio (card 0116): which process usually comes next after
/// the head, a suggestion only — nothing greyed, nothing reordered (R2).
extension StudioWorkspaceModel {
  /// The process usually applied after the head's steps (`ProcessOrder.usuallyNext`), `nil` past
  /// the last.
  package var usuallyNext: String? {
    ProcessOrder.usuallyNext(after: studio.steps.map(\.processID))
  }

  /// Why `id` usually comes at this point, by its stage: linear work before the stretch, the
  /// finish after it.
  package static func usuallyNextReason(_ stage: ProcessStage) -> LocalizedStringResource {
    switch stage {
    case .linear: .app("Usually next: it works on the linear data, before the stretch.")
    case .any: .app("Usually next: it fits before or after the stretch.")
    case .nonlinear: .app("Usually next: it finishes the stretched image.")
    }
  }
}

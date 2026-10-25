package import Foundation
package import ProcessKit

/// The usual processing order in the Studio (card 0116): which process usually comes next after
/// the head, a suggestion only — nothing greyed, nothing reordered (R2).
extension StudioWorkspaceModel {
  /// The process usually applied after the head's steps (`ProcessOrder.usuallyNext`), a greyed
  /// one skipped (a row never says « needs a tool » and « usually next » at once); `nil` past the
  /// last.
  package var usuallyNext: String? {
    let greyed = Set(catalogue.flatMap(\.entries).filter { $0.unavailable != nil }.map(\.id))
    return ProcessOrder.usuallyNext(after: steps.map(\.processID), skipping: greyed)
  }

  /// Why process `id` of `stage` usually comes at this point: linear work before the stretch,
  /// the stretch itself, the finish after it.
  package static func usuallyNextReason(_ id: String, stage: ProcessStage)
    -> LocalizedStringResource
  {
    if id == StretchProcess.id {
      return .app("Usually next: the stretch, once the linear work is done.")
    }
    return switch stage {
    case .linear: .app("Usually next: it works on the linear data, before the stretch.")
    case .any: .app("Usually next: it fits before or after the stretch.")
    case .nonlinear: .app("Usually next: it finishes the stretched image.")
    }
  }
}

internal import Foundation
package import StackKit

/// Stack folders a run left without a stack (card 0113): removed when nothing finished in them,
/// listed otherwise, deleted only when the user says so (R2).
extension ProjectWindowModel {
  /// Lists the package's stack folders no stack records; the empty ones are removed on the way.
  ///
  /// Stacks that cannot be read list nothing and remove nothing: every registered stack would
  /// otherwise read as a leftover offered for deletion.
  func listLeftoverStacks() {
    leftoverStacks = []
    guard !isStacking, let folder = folder(), let store = store(),
      let recorded = try? store.stacks().map(\.bundlePath)
    else { return }
    leftoverStacks = StackLeftovers.orphans(in: folder, recorded: Set(recorded))
  }

  /// Deletes `leftover` from the package; a failure is shown.
  package func deleteLeftoverStack(_ leftover: LeftoverStack) {
    guard let folder = folder() else { return }
    do {
      try StackLeftovers.remove(leftover, in: folder)
    } catch {
      self.error = UserFacingError(error)
    }
    listLeftoverStacks()
  }

  /// Removes the folder of a run that did not finish unless a finished master is in it, once
  /// the run's task let go of it.
  @concurrent
  nonisolated static func removeUnfinished(_ output: URL) async {
    await StackLeftovers.removeUnfinished(output)
  }
}

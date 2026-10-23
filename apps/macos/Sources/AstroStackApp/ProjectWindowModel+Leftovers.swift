internal import Foundation
package import StackKit

/// Stack folders a run left without a stack (card 0113): removed when nothing finished in them,
/// listed otherwise, deleted only when the user says so (R2).
extension ProjectWindowModel {
  /// Lists the package's stack folders no stack records; the empty ones are removed on the way.
  func listLeftoverStacks() {
    guard !isStacking, let folder = folder() else {
      leftoverStacks = []
      return
    }
    let recorded = Set((try? store()?.stacks().map(\.bundlePath)) ?? stacks.map(\.bundlePath))
    leftoverStacks = StackLeftovers.orphans(in: folder, recorded: recorded)
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

  /// Removes the folder of a run that did not finish unless a finished master is in it.
  @concurrent
  nonisolated static func removeUnfinished(_ output: URL) async {
    StackLeftovers.removeUnfinished(output)
  }
}

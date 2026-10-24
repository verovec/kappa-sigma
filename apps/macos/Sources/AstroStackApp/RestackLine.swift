internal import RenderKit
package import SwiftUI

/// The re-stack line of the Stacking stage (card 0100): the nights and lights the next run redoes
/// and the folders added since the last stack — said before Run, so adding a night is never a
/// surprise twelve-minute run.
package struct RestackLine: View {
  let plan: RestackPlan

  /// The line of `plan`.
  package init(plan: RestackPlan) {
    self.plan = plan
  }

  package var body: some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: "arrow.triangle.2.circlepath")
    }
    .foregroundStyle(DesignColor.textSecondary.color)
    .padding([.horizontal, .bottom], DesignMetrics.spacingM)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The sentence: a first stack, or a re-stack from scratch with the folders imported since the
  /// last stack.
  package var text: LocalizedStringResource {
    let nights = AstroFormat.nightCount(plan.nights)
    let frames = AstroFormat.frameCount(plan.frames)
    switch plan.added {
    case nil:
      return .app("Stacks \(nights) (\(frames)): each is calibrated, registered and graded.")
    case 0:
      return .app("Re-stacks \(nights) (\(frames)) from scratch: nothing is reused.")
    case let added?:
      let folders = Self.importedCount(added)
      return .app("Re-stacks \(nights) (\(frames)) from scratch, \(folders): nothing is reused.")
    }
  }

  /// `2 dossiers importés depuis le dernier empilement` / `2 folders imported since the last
  /// stack`: a fact about the project, whether or not their sets are checked.
  static func importedCount(_ count: Int) -> LocalizedStringResource {
    .app("\(count) folders imported since the last stack")
  }
}

internal import ProjectKit
internal import RenderKit
package import SwiftUI

/// The launch sheet of the retention policy in Ask mode (card 0114).
///
/// The stacks never exported and unused for N days, across the recent projects, with their total
/// size. Nothing goes until Delete all (R2); Keep never asks about them again; Remind in 7 days
/// asks later.
package struct RetentionSheet: View {
  var review: RetentionReview
  @Environment(\.locale) private var locale

  /// The sheet listing the pending stacks of `review`.
  package init(review: RetentionReview) {
    self.review = review
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      Text(.app("Stacks never exported")).font(.title2)
      Text(.app("\(size(total)) in stacks that were never exported nor opened for a while."))
        .foregroundStyle(DesignColor.textSecondary.color)
      List(review.pending) { candidate in
        HStack {
          Text(verbatim: name(candidate))
          Spacer()
          Text(verbatim: size(candidate.bytes)).monospacedDigit()
        }
      }
      .frame(minHeight: 160)
      HStack {
        Button(.app("Remind in 7 Days")) { review.remindLater() }
        Spacer()
        Button(.app("Keep")) { Task { await review.keep() } }
        Button(.app("Delete All (\(size(total)))"), role: .destructive) {
          Task { await review.deleteAll() }
        }
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(width: 520)
  }

  private var total: Int64 { review.pending.reduce(0) { $0 + $1.bytes } }

  /// « M 31 · stacks/20261022_202418 ».
  private func name(_ candidate: RetentionCandidate) -> String {
    "\(candidate.project.deletingPathExtension().lastPathComponent) · \(candidate.stack.bundlePath)"
  }

  private func size(_ bytes: Int64) -> String {
    AstroFormat(locale: locale).bytes(bytes)
  }
}

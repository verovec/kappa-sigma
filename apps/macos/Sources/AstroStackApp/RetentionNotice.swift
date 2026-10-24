internal import ProjectKit
internal import RenderKit
internal import SwiftUI

/// What the retention policy removed at this launch (card 0114), automatically or by Delete
/// All, shown once in the welcome window until OK.
struct RetentionNotice: View {
  var review: RetentionReview
  @Environment(\.locale) private var locale

  var body: some View {
    if !review.removed.isEmpty {
      HStack(alignment: .firstTextBaseline) {
        Label {
          Text(.app("Stacks never exported, deleted: \(review.removed.count) (\(size))."))
        } icon: {
          Image(systemName: "externaldrive.badge.minus")
        }
        Spacer()
        Button(.app("OK")) { review.dismissRemoved() }
      }
      .help(Text(verbatim: review.removed.map(\.stack.bundlePath).joined(separator: "\n")))
    }
  }

  private var size: String {
    AstroFormat(locale: locale).bytes(review.removed.reduce(0) { $0 + $1.bytes })
  }
}

internal import RenderKit
internal import SwiftUI

/// The run's journal with its filter: its own view, so a new line redraws the list alone.
struct JournalView: View {
  @Bindable var run: RunViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField(.app("Filter the journal"), text: $run.journalFilter)
        .textFieldStyle(.roundedBorder)
        .padding(DesignMetrics.spacingS)
      List(run.shownJournal) { line in
        Text(verbatim: line.text)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(
            line.isWarning ? DesignColor.statusAttention.color : DesignColor.textPrimary.color
          )
          .textSelection(.enabled)
      }
    }
  }
}

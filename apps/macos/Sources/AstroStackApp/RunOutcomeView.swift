internal import RenderKit
internal import SwiftUI

/// What a stopped run leaves to read: a finished run's channels, trail masks, decisions and
/// warnings; a cancelled or failed run's kept files, and the journal tail of a failed one.
struct RunOutcomeView: View {
  var run: RunViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      if let result = run.result {
        section(.app("Channels"), RunSummary.channels(result) + RunSummary.trailMasks(result))
        section(.app("Decisions"), verbatim: result.notes)
        section(.app("Warnings"), verbatim: result.warnings)
      }
      if run.phase != .finished && run.phase != .running {
        section(.app("Kept in the stack folder"), verbatim: run.kept)
      }
      if case .failed = run.phase {
        section(.app("Last journal lines"), verbatim: run.journalTail.map(\.text))
      }
    }
  }

  @ViewBuilder
  private func section(_ title: LocalizedStringResource, _ lines: [LocalizedStringResource])
    -> some View
  {
    if !lines.isEmpty {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
        SectionHeader(title)
        ForEach(lines.indices, id: \.self) { Text(lines[$0]) }
      }
    }
  }

  /// StackKit's own sentences (decisions, warnings, Siril lines) are shown as written.
  @ViewBuilder
  private func section(_ title: LocalizedStringResource, verbatim lines: [String]) -> some View {
    if !lines.isEmpty {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
        SectionHeader(title)
        ForEach(lines.indices, id: \.self) {
          Text(verbatim: lines[$0]).textSelection(.enabled)
        }
      }
    }
  }
}

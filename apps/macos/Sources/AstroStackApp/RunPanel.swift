internal import AppKit
internal import RenderKit
internal import SwiftUI

/// One run as it goes: where it stands, its steps, the stage previews and the journal; once it
/// stops, what it decided or what it left behind.
struct RunPanel: View {
  @Bindable var run: RunViewModel

  var body: some View {
    HStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
          Self.badge(for: run.phase)
          if let percent = run.percent {
            ProgressView(value: Double(percent), total: 100)
          }
          steps
          if !run.previews.isEmpty { previews }
          RunOutcomeView(run: run)
        }
        .padding(DesignMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(minWidth: 320)
      Divider()
      journal.frame(minWidth: 280)
    }
  }

  /// Where the run stands, in a badge.
  @ViewBuilder
  static func badge(for phase: RunViewModel.Phase) -> some View {
    switch phase {
    case .running:
      // A run going as planned is no warning: a spinner, not the attention badge.
      Label {
        Text(.app("Running"))
      } icon: {
        ProgressView().controlSize(.small)
      }
    case .finished: StatusBadge(.ok, .app("Stacked"))
    case .cancelled: StatusBadge(.unavailable, .app("Cancelled"))
    case .failed(let error): StatusBadge(.error, error.message)
    }
  }

  private var steps: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      ForEach(run.steps) { step in
        Label {
          if step.title.isEmpty {
            Text(.app("Step \(step.number)"))
          } else {
            Text(verbatim: step.title)
          }
        } icon: {
          Self.icon(step.state)
        }
        .foregroundStyle(step.state == .pending ? .secondary : .primary)
      }
    }
  }

  private static func icon(_ state: RunViewModel.StepState) -> Image {
    switch state {
    case .pending: Image(systemName: "circle")
    case .running: Image(systemName: "circle.dotted")
    case .done: Image(systemName: "checkmark.circle")
    case .failed: Image(systemName: "xmark.octagon")
    case .cancelled: Image(systemName: "stop.circle")
    }
  }

  private var previews: some View {
    ScrollView(.horizontal) {
      HStack(spacing: DesignMetrics.spacingS) {
        ForEach(run.previews) { thumbnail in
          VStack(spacing: DesignMetrics.spacingXS) {
            if let image = NSImage(contentsOf: thumbnail.url) {
              Image(nsImage: image).resizable().scaledToFit().frame(height: 96)
            } else {
              Image(systemName: "photo").frame(width: 96, height: 96)
            }
            Text(verbatim: thumbnail.stage).font(.caption)
          }
        }
      }
    }
    .frame(height: 124)
  }

  private var journal: some View {
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

internal import RenderKit
internal import StackKit
internal import SwiftUI

/// One lane's review (card 0069): where it stands, Continue, the metric histogram, the table of
/// every frame with its verdict, and the blink panel while the run waits.
struct FrameReviewView: View {
  @Bindable var review: FrameReviewViewModel
  @State private var selection: FrameReviewViewModel.Row.ID?
  @State private var metric = Metric.fwhm
  @Environment(\.locale) private var locale

  /// A metric the histogram plots.
  enum Metric: String, CaseIterable, Identifiable {
    case fwhm, roundness, stars, background, shift
    var id: String { rawValue }

    var keyPath: KeyPath<FrameReviewViewModel.Row, Double> {
      switch self {
      case .fwhm: \.fwhm
      case .roundness: \.roundness
      case .stars: \.starsAsDouble
      case .background: \.background
      case .shift: \.shift
      }
    }

    var title: LocalizedStringResource {
      switch self {
      case .fwhm: .app("FWHM")
      case .roundness: .app("Roundness")
      case .stars: .app("Stars")
      case .background: .app("Background")
      case .shift: .app("Shift")
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      status
      HStack(alignment: .top, spacing: DesignMetrics.spacingM) {
        VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
          histogram
          FrameTable(review: review, selection: $selection)
        }
        if review.isLive { FrameBlinkView(review: review).frame(width: 300) }
      }
    }
    .padding([.horizontal, .bottom], DesignMetrics.spacingM)
    .onChange(of: selection) { _, chosen in review.select(chosen) }
    .onChange(of: review.current, initial: true) { _, shown in selection = shown }
  }

  /// Live: waiting, the counts and Continue; read-only: what the last run stacked.
  private var status: some View {
    let registered = format.frames(review.rows.count(where: \.isRegistered))
    let kept = format.frames(review.keptCount)
    return HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingM) {
      Text(verbatim: review.lane).font(.headline)
      if let error = review.error {
        StatusBadge(.error, verbatim: error)
      } else if review.isLive {
        StatusBadge(.attention, .app("Waiting for you: \(registered) registered, \(kept) kept"))
      } else if review.isAnswered {
        StatusBadge(.ok, .app("Continuing: \(kept) kept of \(registered)"))
      } else {
        StatusBadge(.ok, .app("Last run: \(kept) stacked of \(registered)"))
      }
      if let elected = review.elected {
        Text(.app("Registration reference: frame \(format.integer(elected))"))
          .foregroundStyle(.secondary)
      }
      Spacer()
      if review.isLive {
        Button(.app("Continue (\(format.frames(review.keptCount)) kept)")) {
          review.continueStacking()
        }
        .disabled(!review.canContinue)
        .accessible(.reviewContinue, label: .app("Continue"))
      }
    }
  }

  /// The chosen metric over the registered frames (0085's handles come later).
  private var histogram: some View {
    HStack(spacing: DesignMetrics.spacingS) {
      Picker(.app("Metric"), selection: $metric) {
        ForEach(Metric.allCases) { Text($0.title).tag($0) }
      }
      .fixedSize()
      .accessible(.reviewMetric, label: .app("Metric"))
      HistogramView(bins: review.histogram(metric.keyPath)).frame(height: 48)
    }
  }

  private var format: AstroFormat { AstroFormat(locale: locale) }
}

extension FrameReviewViewModel.Row {
  /// The star count as a metric to plot.
  nonisolated var starsAsDouble: Double { Double(starCount) }
}

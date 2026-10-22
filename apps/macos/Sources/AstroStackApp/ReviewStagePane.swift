internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The Tri stage (card 0069): the `frame_review` knob, then the lane a run waits on, or the last
/// run's verdicts read-only, or what to do to get some.
struct ReviewStagePane: View {
  var model: ProjectWindowModel
  @State private var lane: String?
  @Environment(\.locale) private var locale

  var body: some View {
    let lanes = model.reviewLanes
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingM) {
        SectionHeader(
          .app("Frame review"),
          detail: .app("Every verdict of the grader, yours to veto before the stack."),
          help: StageHelp.help(.review, locale: locale))
        Spacer()
        reviewToggle
      }
      .padding(DesignMetrics.spacingM)
      if lanes.isEmpty {
        EmptyState(.app("Frame review"), message: emptyMessage, systemImage: "rectangle.grid.3x2")
      } else {
        let shown = lanes.first { $0.lane == lane } ?? lanes[0]
        if lanes.count > 1 { lanePicker(lanes) }
        // Each lane gets its own table state: a selection never bleeds into the next lane.
        FrameReviewView(review: shown).id(ObjectIdentifier(shown))
      }
    }
    .onChange(of: lanes.map(\.lane), initial: true) { _, names in
      if let lane, names.contains(lane) { return }
      lane = names.first
    }
  }

  /// What to expect: a run going with the knob on pauses here; otherwise how to get a review.
  private var emptyMessage: LocalizedStringResource {
    if model.run?.isRunning == true, model.knobs.settings.frameReview {
      return .app("Grading: each lane pauses here after its registration.")
    }
    return .app("Run a stack with the review on: each lane pauses here after grading.")
  }

  /// The knob, worded by the knobs glossary, frozen while a run goes (R2: values shown = applied).
  private var reviewToggle: some View {
    let term = AppGlossary.term(
      Knob.termID(KnobSchema.frameReviewID), locale: locale, in: AppGlossary.knobs)
    return Toggle(isOn: frameReview) { Text(verbatim: term.label) }
      .help(term.definition)
      .disabled(model.run?.isRunning == true)
      .accessible(.reviewToggle, verbatim: term.label)
  }

  private var frameReview: Binding<Bool> {
    Binding(
      get: { model.knobs.settings.frameReview },
      set: { model.knobs.set(KnobSchema.frameReviewID, to: .flag($0)) })
  }

  /// A run with several lanes (M 31 BB+DB: RGB then RGB-dualband) reviews each in turn.
  private func lanePicker(_ lanes: [FrameReviewViewModel]) -> some View {
    Picker(.app("Lane"), selection: $lane) {
      ForEach(lanes, id: \.lane) { Text(verbatim: $0.lane).tag(Optional($0.lane)) }
    }
    .pickerStyle(.segmented)
    .fixedSize()
    .padding(.horizontal, DesignMetrics.spacingM)
    .accessible(.reviewLane, label: .app("Lane"))
  }
}

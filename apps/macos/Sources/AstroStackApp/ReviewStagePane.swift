internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The Tri stage (card 0069): the `frame_review` knob, then the lane a run waits on, or the last
/// run's verdicts read-only, or what to do to get some.
struct ReviewStagePane: View {
  var model: ProjectWindowModel
  @State private var laneID: String?
  @Environment(\.locale) private var locale

  var body: some View {
    let lanes = model.reviewLanes
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingM) {
        SectionHeader(
          .app("Frame review"),
          detail: .app("Every verdict of the grader, yours to veto before the stack."))
        Spacer()
        VStack(alignment: .trailing, spacing: DesignMetrics.spacingXS) {
          reviewToggle
          referenceToggle
        }
      }
      .padding(DesignMetrics.spacingM)
      if lanes.isEmpty {
        EmptyState(.app("Frame review"), message: emptyMessage, systemImage: "rectangle.grid.3x2")
      } else {
        let shown = lanes.first { $0.id == laneID } ?? lanes[0]
        if lanes.count > 1 { lanePicker(lanes) }
        // Each lane gets its own table state: a selection never bleeds into the next lane.
        FrameReviewView(review: shown).id(ObjectIdentifier(shown))
      }
    }
    .onChange(of: lanes.map(\.id), initial: true) { _, ids in
      if let laneID, ids.contains(laneID) { return }
      laneID = ids.first
    }
  }

  /// What to expect: a run going with the knob on pauses here; otherwise how to get a review.
  private var emptyMessage: LocalizedStringResource {
    let settings = model.knobs.settings
    // The reference pause comes first in a run: it is the one to announce when both are on.
    if model.run?.isRunning == true, settings.referenceBreakpoint {
      return .app("Measuring: each lane pauses here before its registration is applied.")
    }
    if model.run?.isRunning == true, settings.frameReview {
      return .app("Grading: each lane pauses here after its registration.")
    }
    return .app("Run a stack with the review on: each lane pauses here after grading.")
  }

  /// The knob, worded by the knobs glossary, frozen while a run or a queue goes (R2: values shown = applied).
  private var reviewToggle: some View {
    let term = AppGlossary.term(
      Knob.termID(KnobSchema.frameReviewID), locale: locale, in: AppGlossary.knobs)
    return Toggle(isOn: frameReview) { Text(verbatim: term.label) }
      .help(term.definition)
      .disabled(model.isStacking)
      .accessible(.reviewToggle, verbatim: term.label)
  }

  private var frameReview: Binding<Bool> {
    Binding(
      get: { model.knobs.settings.frameReview },
      set: { model.knobs.set(KnobSchema.frameReviewID, to: .flag($0)) })
  }

  /// The reference-pin knob (card 0096), worded by the knobs glossary, frozen while a run or a queue goes.
  private var referenceToggle: some View {
    let term = AppGlossary.term(
      Knob.termID(KnobSchema.referenceBreakpointID), locale: locale, in: AppGlossary.knobs)
    return Toggle(isOn: referenceBreakpoint) { Text(verbatim: term.label) }
      .help(term.definition)
      .disabled(model.isStacking)
      .accessible(.referenceToggle, verbatim: term.label)
  }

  private var referenceBreakpoint: Binding<Bool> {
    Binding(
      get: { model.knobs.settings.referenceBreakpoint },
      set: { model.knobs.set(KnobSchema.referenceBreakpointID, to: .flag($0)) })
  }

  /// A run with several lanes (M 31 BB+DB: RGB then RGB-dualband) reviews each in turn.
  private func lanePicker(_ lanes: [FrameReviewViewModel]) -> some View {
    Picker(.app("Lane"), selection: $laneID) {
      ForEach(lanes, id: \.id) { lane in
        if lane.kind == .reference {
          Text(.app("\(lane.lane) · reference")).tag(Optional(lane.id))
        } else {
          Text(verbatim: lane.lane).tag(Optional(lane.id))
        }
      }
    }
    .pickerStyle(.segmented)
    .fixedSize()
    .padding(.horizontal, DesignMetrics.spacingM)
    .accessible(.reviewLane, label: .app("Lane"))
  }
}

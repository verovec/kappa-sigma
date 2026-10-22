internal import ImageKit
package import ProcessKit
package import RenderKit

extension StudioWorkspaceModel {
  /// What `type` with `params` proposes on the head, and for the levels the viewer's display
  /// stretch (the STF → HT handoff, card 0089): offered, never set (R2).
  package func offers(for type: any ImageProcess.Type, params: ParamSet) -> [Suggestion] {
    let suggestions = (try? studio.session.suggestions(for: type, params: params)) ?? []
    guard type == LevelsProcess.self else { return suggestions }
    return suggestions + Self.displaySuggestions(viewer.model.frame.stf)
  }

  /// The panel's inputs on the head: its suggestions, the head's sample and statistics.
  func refresh(_ panel: ProcessPanelModel) {
    panel.suggestions = offers(for: panel.type, params: panel.params)
    guard panel.type is any HistogramHandled.Type else { return }
    panel.sample = HeadSample(studio.head)
    panel.headStats = studio.session.stepStats
  }

  /// The display stretch `stf` (one per channel; `nil`: off) as the levels' values.
  ///
  /// One RGB/K triple, linked, when every channel shows the same stretch; else each channel's
  /// own, unlinked, with RGB/K at the identity. One reason, taken together.
  package static func displaySuggestions(_ stf: [STFParameters]?) -> [Suggestion] {
    guard let stf, let first = stf.first else { return [] }
    let reason = LevelsProcess.suggestionReasons[1]
    if stf.allSatisfy({ $0 == first }) {
      return [Suggestion(paramID: "linked", value: .flag(true), reason: reason)]
        + LevelsProcess.suggestions(first, as: "rgb", reason: reason)
    }
    return [Suggestion(paramID: "linked", value: .flag(false), reason: reason)]
      + zip(["r", "g", "b"], stf).flatMap { triple, channel in
        LevelsProcess.suggestions(channel, as: triple, reason: reason)
      }
      + LevelsProcess.suggestions(.identity, as: "rgb", reason: reason)
  }
}

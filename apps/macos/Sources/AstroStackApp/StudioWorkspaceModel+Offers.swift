internal import ImageKit
internal import Observation
package import ProcessKit
package import RenderKit

extension StudioWorkspaceModel {
  /// What `type` with `params` proposes on the head, for the levels the viewer's display
  /// stretch (the STF → HT handoff, card 0089), for plate solving the stack header's pointing and
  /// optics (0093) then the catalogue object's position (0130), for the denoise the head's
  /// measured noise (0115): offered, never set (R2).
  package func offers(for type: any ImageProcess.Type, params: ParamSet) -> [Suggestion] {
    let session = studio.session
    let measured =
      selection.layerID.map { try? session.branchSuggestions($0, for: type, params: params) }
      ?? (try? session.suggestions(for: type, params: params))
    let suggestions = measured ?? []
    if type == PlateSolveProcess.self {
      let object = catalogueObject().map {
        PlateSolveProcess.suggestions(object: $0.name, raDeg: $0.raDeg, decDeg: $0.decDeg)
      }
      return suggestions + PlateSolveProcess.suggestions(header: studio.header) + (object ?? [])
    }
    if type == DenoiseProcess.self { return suggestions + denoiseOffers() }
    guard type == LevelsProcess.self else { return suggestions }
    return suggestions + Self.displaySuggestions(viewer.model.frame.stf)
  }

  /// The sidebar's object changed (a choice, the catalogue read): an open plate-solve panel offers
  /// the new position.
  package func catalogueOfferChanged() {
    guard let panel, panel.type == PlateSolveProcess.self else { return }
    panel.suggestions = offers(for: panel.type, params: panel.params)
  }

  /// The denoise's noise level from the head's measured noise, once measured: the panel's
  /// suggestions are rebuilt when the measurement ends.
  private func denoiseOffers() -> [Suggestion] {
    // Keyed by history too: a branch's step files are named like the main history's.
    let key = String(describing: selection) + "/" + (steps.last?.file ?? "")
    let sigma = headNoise.sigma(of: key, image: head) { [weak self] in
      guard let self, !self.isRetired, let panel = self.panel, panel.type == DenoiseProcess.self
      else { return }
      panel.suggestions = self.offers(for: panel.type, params: panel.params)
    }
    return sigma.map { DenoiseProcess.suggestions(measured: $0) } ?? []
  }

  /// Waits for the head's noise measurement under way, if any: a test sees the denoise's
  /// suggestion without sleeping.
  package func settleNoise() async {
    await headNoise.settle()
  }

  /// Follows the viewer's display stretch: when it changes (mode, link, a manual drag, a new
  /// head), the levels' « display stretch » suggestion is rebuilt, so what is offered is what is
  /// on screen.
  func watchDisplayStretch() {
    withObservationTracking {
      _ = viewer.model.frame.stf
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, !self.isRetired else { return }
        if let panel = self.panel, panel.type == LevelsProcess.self {
          panel.suggestions = self.offers(for: panel.type, params: panel.params)
        }
        self.watchDisplayStretch()
      }
    }
  }

  /// The panel's inputs on the head: its suggestions, the head's size, its sample (the input
  /// histogram of every process that keeps the grid, card 0128) and, for the handles, statistics.
  func refresh(_ panel: ProcessPanelModel) {
    panel.suggestions = offers(for: panel.type, params: panel.params)
    panel.headSize = (head.width, head.height)
    // A head already solved says so on the plate-solve panel (card 0130); a new solve stays a choice.
    panel.solved =
      panel.type == PlateSolveProcess.self
      ? PlateSolveStatus(wcs: head.metadata.wcs, width: head.width, height: head.height) : nil
    guard !(panel.type is any GeometricProcess.Type) else {
      panel.sample = nil
      return
    }
    panel.sample = sampleOfHead()
    guard panel.type is any HistogramHandled.Type else { return }
    panel.headStats = studio.session.stepStats
  }

  /// The head's sample, measured once per head: opening another panel or a refused move does
  /// not sample the same image again.
  private func sampleOfHead() -> HeadSample {
    let head = self.head
    if let headSample, headSample.head === head { return headSample.sample }
    let sample = HeadSample(head)
    headSample = (head, sample)
    return sample
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

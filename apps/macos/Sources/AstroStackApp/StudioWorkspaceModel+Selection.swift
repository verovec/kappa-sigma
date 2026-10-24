package import ImageKit
package import ProcessKit
internal import RenderKit
internal import StackKit

extension StudioWorkspaceModel {
  /// The histories the switcher offers: the combined image, then one branch per bundle layer
  /// (the base layer first, then in filter order); none for a single-layer bundle.
  package var selections: [StudioSelection] {
    let ids = Array(studio.session.stackBundle.layers.keys)
    guard ids.count > 1 else { return [] }
    let base = StudioSession.baseLayerID(ids)
    let ordered = ids.sorted { one, two in
      if one == base { return two != base }
      if two == base { return false }
      let (first, second) = (Filter.rank(one), Filter.rank(two))
      return first == second ? one < two : first < second
    }
    return [.main] + ordered.map { .branch($0) }
  }

  /// The history the viewer, the panel, Apply and Undo work on from now on.
  package func select(_ selection: StudioSelection) {
    // A replay or a run rewrites the combined image: the view stays on it until it ends.
    guard selection != self.selection, !isReplaying, !(pipeline?.isRunning ?? false) else { return }
    stretches[self.selection] = ViewerStretch(
      stretch: viewer.model.stretch, linked: viewer.model.linked, manual: viewer.model.manualSTF)
    try? compare(toStep: nil)
    self.selection = selection
    // Its own stretch (a line layer is mono), auto on a first visit; set before the head is shown,
    // so the panel's offers read the stretch on screen.
    let kept = stretches[selection] ?? ViewerStretch(stretch: .auto, linked: false, manual: [])
    viewer.model.linked = kept.linked
    viewer.model.stretch = kept.stretch
    if kept.stretch == .manual { viewer.model.manualSTF = kept.manual }
    refreshCatalogue()
    // A process this history refuses is not left in the panel.
    let entries = catalogue.flatMap(\.entries)
    if let panel, entries.first(where: { $0.id == panel.type.id })?.unavailable != nil {
      closePanel()
    }
    do {
      try headChanged()
    } catch {
      failure = UserFacingError(error).message
    }
  }

  /// The applied steps of the history shown.
  package var steps: [History.Step] { studio.steps(of: selection) }

  /// The head of the history shown.
  package var head: AstroImage { studio.head(of: selection) }

  /// What the combined view says when a branch edit outdated main steps; `nil` on a branch.
  package var staleNotice: StaleNotice? {
    guard selection == .main, let start = studio.staleFrom else { return nil }
    let steps = Array(start..<studio.steps.count)
    let moved = steps.flatMap { studio.session.movedBranches(ofStep: $0) }
    return StaleNotice(steps: steps, branches: Array(Set(moved)).sorted())
  }

  /// The other histories whose head lies on the grid of the one shown: what « Compare with… »
  /// offers (the combined image after a crop is on another grid).
  package var comparable: [StudioSelection] {
    let shown = head
    return selections.filter { other in
      guard other != selection else { return false }
      let image = studio.head(of: other)
      return image.width == shown.width && image.height == shown.height
    }
  }

  /// Compares the viewer's image with the head of `other` (`nil`: no compare).
  package func compare(with other: StudioSelection?) throws {
    try compare(toStep: nil)
    guard let other, comparable.contains(other) else { return }
    viewer.reference = try Self.texture(studio.head(of: other), device: studio.session.device)
    comparingWith = other
  }

  /// Why branch `layerID` cannot take `type`, or `nil` (R2: greyed with the reason).
  func branchUnavailable(_ type: any ImageProcess.Type, layerID: String) -> StudioUnavailable? {
    let planes = studio.session.stackBundle.layers[layerID]?.planes.count ?? 0
    switch StudioSession.refusal(of: type, planes: planes) {
    case .needsColour: return .needsColourLayer
    case .movesPixels, .notPerLayer: return .onCombinedImage
    case nil: return type.hostTool ? .toolOnCombinedImage : nil
    }
  }
}

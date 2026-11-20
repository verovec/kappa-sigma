/// Card 0171: a step 0 kept from an older or incomplete bundle is offered the combination the
/// stack opens on today. Offered on the panel, never written to the history (R2).
extension ChannelCombinationProcess {
  /// Why every slot is offered a palette's source; the suggestion's subject names the palette.
  package static let spelledReason = "the layers spell a palette this step does not read"
  /// Why a slot that cannot run is offered another source, when the layers spell no palette.
  package static let lackingReason =
    "the slot reads a layer the stack lacks: the source this stack opens on"
  /// Every reason the combination's suggestions give: keys of the catalog.
  package static let suggestionReasons = [spelledReason, lackingReason, skyBlackReason]

  /// The sources the stack opens on, for a step that is a grey or reads a layer the stack lacks,
  /// then the black of each slot under its layer's sky (card 0172): one list, a suggestion per
  /// parameter at most; never applied by the process (R2).
  package func suggestions(stats: LayerStats, layers: [String: LayerStats]) -> [Suggestion] {
    // The step context also holds the outputs of later steps, by role (a starless, a background
    // model): no colour source, as `StudioSession.layerPlanes()` says.
    let stack = layers.filter { LayerRole(rawValue: $0.key) == nil }
    let sources = Self.sourceSuggestions(params, planes: stack.mapValues { $0.channels.count })
    // A slot about to read another layer is not offered the sky of the one it reads now.
    return sources
      + Self.blackSuggestions(params, layers: stack, pending: Set(sources.map(\.paramID)))
  }

  /// One suggestion per slot of `params` that `initialParams(planes:)` would fill otherwise.
  ///
  /// Asked only when the step shows less colour than the layers could give: a slot reads a layer
  /// outside `planes`, or the layers spell a palette while a colour slot is a leftover of a grey
  /// (`isLeftover`). With a palette spelled every slot goes to it (never a mix of two palettes),
  /// and the offer lasts until the last slot is taken; a luminance the stack holds is not offered
  /// away. Without one, only the slots that cannot run move.
  package static func sourceSuggestions(_ params: ParamSet, planes: [String: Int]) -> [Suggestion] {
    let layerIDs = Set(planes.keys)
    let lacking = Set(unavailableReasons(params, layerIDs: layerIDs).keys)
    let palette = Palette.spelled(planes: planes)
    guard let opening = try? initialParams(planes: planes) else { return [] }
    if lacking.isEmpty {
      // Another palette the layers allow (HOO on SHO layers) is a choice, never a leftover.
      guard let palette, Palette.matching(params) == nil,
        colourSlots.contains(where: { isLeftover($0, in: params, of: palette) })
      else { return [] }
    }
    return slotSources.compactMap { slot in
      let source = opening.choice(slot)
      guard source != params.choice(slot), layers(of: source).allSatisfy(layerIDs.contains)
      else { return nil }
      if !lacking.contains(slot), palette == nil || source == "none" { return nil }
      return Suggestion(
        paramID: slot, value: .choice(source),
        reason: palette == nil ? lackingReason : spelledReason, subject: palette?.title)
    }
  }

  /// The source parameters of the three colour slots.
  private static let colourSlots = Array(slotSources.prefix(3))

  /// True when colour `slot` shows what a grey left there rather than a colour of its own: a
  /// source `palette` does not put in it, that another colour slot reads too or that the palette
  /// reads elsewhere (L in the blue slot of an LRGB stack).
  private static func isLeftover(_ slot: String, in params: ParamSet, of palette: Palette) -> Bool {
    let source = params.choice(slot)
    let spelled = Dictionary(uniqueKeysWithValues: zip(slotSources, palette.sources))
    guard source != spelled[slot] else { return false }
    let shared = colourSlots.contains { $0 != slot && params.choice($0) == source }
    return shared || palette.sources.contains(source)
  }
}

internal import FilterKit

/// Card 0172: the black point of each slot, offered at the sky its layer measures on the stack.
///
/// The slots read raw linear masters, so with every black at 0 each master's sky offset sets the
/// R:G:B ratios instead of the object. R2: the sky is the bundle's statistic, shown as a
/// suggestion; the defaults stay 0 and step 0 keeps its bytes.
extension ChannelCombinationProcess {
  /// Why a slot's black point is offered: an English key of the catalog.
  package static let skyBlackReason =
    "the sky level of the slot's layer on the stack: subtracted, the channel ratios show the colour"

  package static let suggestionReasons = [skyBlackReason]

  /// The black points of the slots, R, G, B then L; never applied by the process (R2).
  package func suggestions(stats: LayerStats, layers: [String: LayerStats]) -> [Suggestion] {
    Self.blackSuggestions(params, layers: layers)
  }

  /// For each slot reading one plane with its black still at 0: that plane's bundle median (the
  /// sky of a deep-sky master), inside the parameter's range.
  ///
  /// None on a colour bundle (its base is one calibrated image, not three masters with their own
  /// offsets), on a grey (one plane in the three colour slots has no ratio to give back), for a
  /// √(A·B) slot (the sky of a product is not a layer's), for a black the user set, nor without
  /// a per-plane statistic above 0.
  package static func blackSuggestions(_ params: ParamSet, layers: [String: LayerStats])
    -> [Suggestion]
  {
    let colour = Set(slotSources.prefix(3).map(params.choice))
    guard layers[Filter.color] == nil, colour.count > 1 else { return [] }
    return slotSources.compactMap { slot in
      let source = params.choice(slot)
      let black = String(slot.dropLast("Source".count)) + "Black"
      guard source != "none", !source.contains("*"), params.number(black) == 0,
        case .number(_, let bounds)? = schema.spec(black)?.kind,
        let sky = LayerPlane(source).stats(in: layers)?.median, sky > 0
      else { return nil }
      return Suggestion(
        paramID: black, value: .number(min(sky, bounds.upperBound)), reason: skyBlackReason)
    }
  }
}

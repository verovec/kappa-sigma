internal import FilterKit
internal import RenderKit

/// Card 0172: the black point of each slot, offered just under the sky its layer measures on
/// the stack.
///
/// The slots read raw linear masters, so with every black at 0 each master's sky offset sets the
/// R:G:B ratios instead of the object. R2: the sky is the bundle's statistic, shown as a
/// suggestion; the defaults stay 0 and step 0 keeps its bytes.
extension ChannelCombinationProcess {
  /// Why a slot's black point is offered: an English key of the catalog.
  package static let skyBlackReason =
    "the slot's layer on the stack, 2.8 σ under its sky: subtracted, the channel ratios show "
    + "the colour"

  /// The black parameter of each slot, R, G, B, then L.
  static let slotBlacks = ["rBlack", "gBlack", "bBlack", "lBlack"]

  /// A black one click would set is on screen first: its row shows while it is offered (R2).
  package static let showsSuggestedRows = true

  /// A black the step subtracts is shown without the disclosure: what is applied is on screen.
  package static func promoted(_ params: ParamSet) -> Set<String> {
    Set(slotBlacks.filter { params.number($0) != 0 })
  }

  /// For each slot reading one plane: that plane's bundle median less 2.8 MADN — the shadows the
  /// autostretch places (`AutoSTF.shadowsClip`), under the sky so its noise is not clipped to 0 —
  /// inside the parameter's range.
  ///
  /// None on a colour bundle (its base is one calibrated image, not three masters with their own
  /// offsets), on a grey (one plane in the three colour slots has no ratio to give back), for a
  /// √(A·B) slot (the sky of a product is not a layer's), for a black already there, nor
  /// without a per-plane statistic leaving a level above 0.
  package static func blackSuggestions(_ params: ParamSet, layers: [String: LayerStats])
    -> [Suggestion]
  {
    let colour = Set(slotSources.prefix(3).map(params.choice))
    guard layers[Filter.color] == nil, colour.count > 1 else { return [] }
    return zip(slotSources, slotBlacks).compactMap { slot, black in
      let source = params.choice(slot)
      guard source != "none", !source.contains("*"),
        case .number(_, let bounds)? = schema.spec(black)?.kind,
        let sky = LayerPlane(source).stats(in: layers)
      else { return nil }
      let level = min(sky.median + AutoSTF.shadowsClip * sky.madn, bounds.upperBound)
      // The source may have changed since a black was taken: offered again unless it is there.
      guard level > 0, level != params.number(black) else { return nil }
      return Suggestion(paramID: black, value: .number(level), reason: skyBlackReason)
    }
  }
}

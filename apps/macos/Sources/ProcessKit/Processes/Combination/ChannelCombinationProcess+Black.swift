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

  /// The decimals a suggested black keeps: what its row shows (`Suggested: 0.0204`), so the value
  /// one click sets is the value read (R2).
  static let blackDecimals = 10_000.0

  /// For each slot reading one plane: that plane's bundle median less 2.8 MADN — the shadows the
  /// autostretch places (`AutoSTF.shadowsClip`), under the sky so its noise is not clipped to 0 —
  /// inside the parameter's range, to four decimals.
  ///
  /// None on a colour bundle (its base is one calibrated image, not three masters with their own
  /// offsets) nor on a grey (one plane in the three colour slots has no ratio to give back). The
  /// three colour slots are offered together or not at all — a sky subtracted from two channels
  /// is a cast of its own: none when one of them is a √(A·B) product (its sky is not a layer's),
  /// lacks a per-plane statistic, measures no level above 0, or is in `pending` (the slots whose
  /// source another suggestion is about to replace). A black already there is not offered again.
  package static func blackSuggestions(
    _ params: ParamSet, layers: [String: LayerStats], pending: Set<String> = []
  ) -> [Suggestion] {
    let colour = Set(slotSources.prefix(3).map(params.choice))
    guard layers[Filter.color] == nil, colour.count > 1 else { return [] }
    let levels = zip(slotSources, slotBlacks).map { slot, black in
      pending.contains(slot) ? nil : blackLevel(of: params.choice(slot), black, layers: layers)
    }
    let colourMeasured = levels.prefix(3).allSatisfy { $0 != nil }
    return zip(slotBlacks, levels).enumerated().compactMap { index, slot in
      // The source may have changed since a black was taken: offered again unless it is there.
      guard let level = slot.1, index == 3 || colourMeasured, level != params.number(slot.0)
      else { return nil }
      return Suggestion(paramID: slot.0, value: .number(level), reason: skyBlackReason)
    }
  }

  /// The level offered to parameter `black` for the plane `source` names, or `nil` without one
  /// above 0.
  private static func blackLevel(
    of source: String, _ black: String, layers: [String: LayerStats]
  ) -> Double? {
    guard source != "none", !source.contains("*"),
      case .number(_, let bounds)? = schema.spec(black)?.kind,
      let sky = LayerPlane(source).stats(in: layers)
    else { return nil }
    let raw = min(sky.median + AutoSTF.shadowsClip * sky.madn, bounds.upperBound)
    let level = (raw * blackDecimals).rounded() / blackDecimals
    return level > 0 ? level : nil
  }
}

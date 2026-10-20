/// The light set being calibrated and the clip filter its night was shot through
/// (`calib.LightRef`).
///
/// The filter set sits beside the key, never in it: set ids are stored tokens.
package struct LightRef: Equatable, Sendable {
  package var key: SetKey
  /// `unknown` for every mono light and every colour night the pixels could not settle, which
  /// reproduces the matching without filter sets exactly.
  package var filterSet: FilterSet

  /// A light with a known (or unknown) filter set.
  package init(key: SetKey, filterSet: FilterSet = .unknown) {
    self.key = key
    self.filterSet = filterSet
  }

  /// The ref of a light set of `inventory` (`RefFor`): its own verdict, else its night's — the one
  /// place the run and the preview agree on a light's clip filter.
  package init(_ set: FrameSet, in inventory: Inventory) {
    let own = set.filterSet.isKnown ? set.filterSet : inventory.filterSets[set.key.id] ?? .unknown
    self.init(
      key: set.key, filterSet: own.isKnown ? own : inventory.nightFilterSet(set.key.session))
  }
}

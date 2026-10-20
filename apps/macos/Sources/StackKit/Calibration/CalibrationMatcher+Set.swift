extension CalibrationMatcher {
  /// What a run applies to one light set (`processChannel`'s selection): masters from another
  /// sensor leave the POOL first (under `force` too), then the matcher picks, the pool's note
  /// appended.
  package static func select(
    _ set: FrameSet, in inventory: Inventory, masters: [CalibrationMaster], excluded: [String] = [],
    force: Bool = false
  ) -> CalibrationSelection {
    let pool = DimensionGuard.keepMatching(masters, lightPath: set.frames.first?.path ?? "")
    var selection = match(
      LightRef(set, in: inventory), masters: pool.masters, excluded: excluded, force: force)
    if let note = pool.note { selection.notes.append(note) }
    return selection
  }
}

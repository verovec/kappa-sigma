internal import ImageKit

// MARK: - Moves of the shown image (card 0105)

extension GeometryProcess {
  /// `params` with `move` done after them on the shown image.
  ///
  /// The turn and flips become those of the image moved, written with the fewest values changed
  /// (a flip after a half turn stays a flip) and never both flips (a half turn: the identity is
  /// always 0° without flips, so `isIdentity` sees it); a flip mirrors the fine angle. Crops and
  /// the rest are kept.
  package static func composing(_ move: GeometryMove, onto params: ParamSet) -> ParamSet {
    let turns = (Int(params.choice("rotation")) ?? 0) / 90
    let (flipH, flipV) = (params.flag("flipH"), params.flag("flipV"))
    let target = Self.moved(Self.map(turns: turns, flipH: flipH, flipV: flipV), by: move).matrix
    // The schema's order (turn, then flips of the turned image) writes each mirror of a
    // rectangle twice; the one closest to the panel's values is kept.
    let forms = (0..<4).flatMap { turns in
      [(false, false), (true, false), (false, true)].map { (turns, $0.0, $0.1) }
    }
    let matching = forms.filter { Self.map(turns: $0.0, flipH: $0.1, flipV: $0.2).matrix == target }
    let changes = { (form: (Int, Bool, Bool)) in
      (form.0 == turns ? 0 : 1) + (form.1 == flipH ? 0 : 1) + (form.2 == flipV ? 0 : 1)
    }
    guard let form = matching.min(by: { changes($0) < changes($1) }) else { return params }
    var moved = params
    try? moved.set("rotation", .choice(String(form.0 * 90)))
    try? moved.set("flipH", .flag(form.1))
    try? moved.set("flipV", .flag(form.2))
    if move.mirrors, params.number("angle") != 0 {
      try? moved.set("angle", .number(-params.number("angle")))
    }
    return moved
  }

  /// The turns then flips on one pixel shown top-down, built as `GeometryPlan` builds them.
  private static func map(turns: Int, flipH: Bool, flipV: Bool) -> GridMap {
    var map = GridMap.identity(width: 1, height: 1)
    for _ in 0..<turns { map = map.quarterTurned() }
    if flipH { map = map.flippedX() }
    if flipV { map = map.flippedY() }
    return map
  }

  /// `map` followed by `move` of the image it makes.
  private static func moved(_ map: GridMap, by move: GeometryMove) -> GridMap {
    switch move {
    case .rotateClockwise: map.quarterTurned()
    case .rotateCounterclockwise: map.quarterTurned().quarterTurned().quarterTurned()
    case .flipHorizontally: map.flippedX()
    case .flipVertically: map.flippedY()
    }
  }
}

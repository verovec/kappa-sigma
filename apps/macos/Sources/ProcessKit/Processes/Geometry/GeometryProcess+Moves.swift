// MARK: - Moves of the shown image (card 0105)

/// A move of the image as shown, which a shortcut composes onto the geometry values.
package enum GeometryMove: Sendable, CaseIterable {
  /// A quarter turn clockwise.
  case rotateClockwise
  /// A quarter turn counter-clockwise.
  case rotateCounterclockwise
  /// Left and right swapped.
  case flipHorizontally
  /// Top and bottom swapped.
  case flipVertically
}

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
    let target = move.matrix * Self.matrix(turns: turns, flipH: flipH, flipV: flipV)
    // The schema's order (turn, then flips of the turned image) writes each mirror of a
    // rectangle twice; the one closest to the panel's values is kept.
    let forms = (0..<4).flatMap { turns in
      [(false, false), (true, false), (false, true)].map { (turns, $0.0, $0.1) }
    }
    let matching = forms.filter { Self.matrix(turns: $0.0, flipH: $0.1, flipV: $0.2) == target }
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

  /// The move of `turns` clockwise quarter turns then the flips, on shown coordinates.
  private static func matrix(turns: Int, flipH: Bool, flipV: Bool) -> GeometryMove.Matrix {
    var matrix = GeometryMove.Matrix.identity
    for _ in 0..<turns { matrix = GeometryMove.rotateClockwise.matrix * matrix }
    if flipH { matrix = GeometryMove.flipHorizontally.matrix * matrix }
    if flipV { matrix = GeometryMove.flipVertically.matrix * matrix }
    return matrix
  }
}

extension GeometryMove {
  /// A whole-number 2 × 2 matrix on shown coordinates (x right, y down), row by row.
  struct Matrix: Equatable {
    let m11: Int, m12: Int, m21: Int, m22: Int

    static let identity = Self(m11: 1, m12: 0, m21: 0, m22: 1)

    static func * (lhs: Self, rhs: Self) -> Self {
      Self(
        m11: lhs.m11 * rhs.m11 + lhs.m12 * rhs.m21, m12: lhs.m11 * rhs.m12 + lhs.m12 * rhs.m22,
        m21: lhs.m21 * rhs.m11 + lhs.m22 * rhs.m21, m22: lhs.m21 * rhs.m12 + lhs.m22 * rhs.m22)
    }
  }

  var matrix: Matrix {
    switch self {
    // Clockwise with y down: right goes to bottom.
    case .rotateClockwise: Matrix(m11: 0, m12: -1, m21: 1, m22: 0)
    case .rotateCounterclockwise: Matrix(m11: 0, m12: 1, m21: -1, m22: 0)
    case .flipHorizontally: Matrix(m11: -1, m12: 0, m21: 0, m22: 1)
    case .flipVertically: Matrix(m11: 1, m12: 0, m21: 0, m22: -1)
    }
  }

  /// Whether it mirrors the image (a fine angle then turns the other way).
  var mirrors: Bool { self == .flipHorizontally || self == .flipVertically }
}

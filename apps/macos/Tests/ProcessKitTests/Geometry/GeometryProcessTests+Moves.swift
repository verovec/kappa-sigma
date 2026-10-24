import ProcessKit
import Testing

extension GeometryProcessTests {
  /// One row: panel values, the shortcuts pressed in order, the values they leave.
  struct MoveCase: Sendable, CustomTestStringConvertible {
    let name: String
    let start: [String: ParamValue]
    let moves: [GeometryMove]
    let values: [String: ParamValue]
    var testDescription: String { name }
  }

  nonisolated static let identityValues: [String: ParamValue] = [
    "rotation": .choice("0"), "flipH": .flag(false), "flipV": .flag(false),
  ]

  nonisolated static let moveCases: [MoveCase] = [
    MoveCase(
      name: "CW ×4 = identity", start: [:], moves: Array(repeating: .rotateClockwise, count: 4),
      values: identityValues),
    MoveCase(
      name: "CW then CCW = identity", start: [:],
      moves: [.rotateClockwise, .rotateCounterclockwise], values: identityValues),
    MoveCase(
      name: "flipH twice = identity", start: [:], moves: [.flipHorizontally, .flipHorizontally],
      values: identityValues),
    MoveCase(
      name: "CW then flipH: the turned image mirrored", start: [:],
      moves: [.rotateClockwise, .flipHorizontally],
      values: ["rotation": .choice("90"), "flipH": .flag(true), "flipV": .flag(false)]),
    MoveCase(
      // = 90° then flipV, written with the flip already set: 270° then flipH.
      name: "flipH then CW: the flip stays, the turn goes the other way", start: [:],
      moves: [.flipHorizontally, .rotateClockwise],
      values: ["rotation": .choice("270"), "flipH": .flag(true), "flipV": .flag(false)]),
    MoveCase(
      name: "flipV from identity stays a flip, not a half turn", start: [:],
      moves: [.flipVertically],
      values: ["rotation": .choice("0"), "flipH": .flag(false), "flipV": .flag(true)]),
    MoveCase(
      name: "CCW from identity", start: [:], moves: [.rotateCounterclockwise],
      values: ["rotation": .choice("270"), "flipH": .flag(false), "flipV": .flag(false)]),
    MoveCase(
      name: "both flips are a half turn: CW writes 270° without flips",
      start: ["flipH": .flag(true), "flipV": .flag(true), "cropLeft": .number(1)],
      moves: [.rotateClockwise],
      values: ["rotation": .choice("270"), "flipH": .flag(false), "flipV": .flag(false)]),
    MoveCase(
      name: "back to the shown original is the identity values",
      start: ["rotation": .choice("90"), "flipH": .flag(true)],
      moves: [.rotateCounterclockwise, .flipVertically],
      values: ["rotation": .choice("0"), "flipH": .flag(false), "flipV": .flag(false)]),
  ]

  /// Card 0105: a shortcut composes its move of the shown image onto the panel's values; the
  /// result shows what was asked (oracle: the display-order `expected` of 0090), crops untouched.
  @Test("testComposingMoves", arguments: moveCases)
  func testComposingMoves(_ row: MoveCase) throws {
    var params = try Self.params(row.start)
    let rows = (0..<3).map { r in (0..<4).map { Float(r * 4 + $0) } }
    var shown = Self.expected(rows, row.start)
    for move in row.moves {
      params = GeometryProcess.composing(move, onto: params)
      shown = Self.displayed(shown, move)
    }
    for (id, value) in row.values { #expect(params[id] == value, "\(id)") }
    #expect(params.number("cropLeft") == (row.start["cropLeft"] == nil ? 0 : 1))
    var values = row.start
    for id in ["rotation", "flipH", "flipV"] { values[id] = params[id] }
    #expect(Self.expected(rows, values) == shown, "the image shows the moves pressed")
  }

  /// Card 0105: a flip mirrors the fine angle too, so the turned frame is mirrored as shown; a
  /// quarter turn keeps it.
  @Test("testComposingKeepsTheAngleShown")
  func testComposingKeepsTheAngleShown() throws {
    let params = try Self.params(["angle": .number(2.5)])
    #expect(GeometryProcess.composing(.flipHorizontally, onto: params).number("angle") == -2.5)
    #expect(GeometryProcess.composing(.rotateClockwise, onto: params).number("angle") == 2.5)
  }

  /// `move` done on the rows as shown (top row first).
  static func displayed(_ rows: [[Float]], _ move: GeometryMove) -> [[Float]] {
    switch move {
    case .rotateClockwise:
      (0..<rows[0].count).map { column in rows.reversed().map { $0[column] } }
    case .rotateCounterclockwise:
      (0..<rows[0].count).reversed().map { column in rows.map { $0[column] } }
    case .flipHorizontally: rows.map { $0.reversed() }
    case .flipVertically: rows.reversed()
    }
  }
}

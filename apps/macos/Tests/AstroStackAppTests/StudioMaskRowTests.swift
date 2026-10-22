import AstroStackApp
import ProcessKit
import Testing

/// The mask row's values (card 0087): each row moves its own value, a range end never crosses
/// its start, and a value the source has not leaves the source as it is.
@Suite("Studio mask row — each value moves its own field")
struct StudioMaskRowTests {
  static let range = MaskSource.luminosityRange(low: 0.2, high: 0.8, softness: 0.1)
  static let stars = MaskSource.stars(threshold: 0.02, radiusPx: 8)

  struct Move: Sendable, CustomTestStringConvertible {
    let source: MaskSource
    let field: StudioMaskRow.Field
    let value: Double
    let expected: MaskSource
    var testDescription: String { "\(field) → \(value)" }
  }

  static let moves: [Move] = [
    Move(source: range, field: .low, value: 0.5, expected: .luminosityRange(0.5, 0.8, 0.1)),
    Move(source: range, field: .low, value: 0.9, expected: .luminosityRange(0.9, 0.9, 0.1)),
    Move(source: range, field: .high, value: 0.6, expected: .luminosityRange(0.2, 0.6, 0.1)),
    Move(source: range, field: .high, value: 0.1, expected: .luminosityRange(0.1, 0.1, 0.1)),
    Move(source: range, field: .softness, value: 0.3, expected: .luminosityRange(0.2, 0.8, 0.3)),
    Move(source: range, field: .radius, value: 4, expected: range),
    Move(source: stars, field: .threshold, value: 0.05, expected: .stars(0.05, 8)),
    Move(source: stars, field: .radius, value: 12, expected: .stars(0.02, 12)),
    Move(source: stars, field: .low, value: 0.5, expected: stars),
  ]

  @Test("a moved value lands in its field, the range stays ordered", arguments: moves)
  func testMoved(move: Move) {
    #expect(StudioMaskRow.moved(move.source, move.field, to: move.value) == move.expected)
  }

  @Test("the starting value of each field, none for a field the source has not")
  func testValue() {
    #expect(StudioMaskRow.value(.low, of: Self.range) == 0.2)
    #expect(StudioMaskRow.value(.high, of: Self.range) == 0.8)
    #expect(StudioMaskRow.value(.softness, of: Self.range) == 0.1)
    #expect(StudioMaskRow.value(.threshold, of: Self.stars) == 0.02)
    #expect(StudioMaskRow.value(.radius, of: Self.stars) == 8)
    #expect(StudioMaskRow.value(.feather, of: Self.stars) == nil)
  }
}

extension MaskSource {
  fileprivate static func luminosityRange(_ low: Double, _ high: Double, _ softness: Double)
    -> Self
  { .luminosityRange(low: low, high: high, softness: softness) }

  fileprivate static func stars(_ threshold: Double, _ radiusPx: Double) -> Self {
    .stars(threshold: threshold, radiusPx: radiusPx)
  }
}

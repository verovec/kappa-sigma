import ProcessKit
import Testing

/// Card 0189: the proxy's reduction factor — the smallest integer that brings the longer side
/// under the maximum; 1 when it already fits (no proxy).
struct ProxyLevelTests {
  struct Case: CustomTestStringConvertible {
    let width: Int
    let height: Int
    let maxSide: Int
    let factor: Int
    var testDescription: String { "\(width)×\(height) under \(maxSide) → \(factor)" }
  }

  static let cases: [Case] = [
    Case(width: 6248, height: 4176, maxSide: 1600, factor: 4),
    Case(width: 3008, height: 2168, maxSide: 1600, factor: 2),
    Case(width: 1600, height: 1200, maxSide: 1600, factor: 1),
    Case(width: 1601, height: 100, maxSide: 1600, factor: 2),
    Case(width: 4, height: 2, maxSide: 1600, factor: 1),
    Case(width: 2000, height: 9000, maxSide: 1600, factor: 6),
    Case(width: 64, height: 32, maxSide: 32, factor: 2),
  ]

  @Test("testFactor", arguments: cases)
  func testFactor(_ testCase: Case) {
    let factor = ProxyLevel.factor(
      width: testCase.width, height: testCase.height, maxSide: testCase.maxSide)
    #expect(factor == testCase.factor)
    // The factor is the smallest that fits: one less does not.
    let longer = max(testCase.width, testCase.height)
    #expect((longer + factor - 1) / factor <= testCase.maxSide)
    if factor > 1 { #expect((longer + factor - 2) / (factor - 1) > testCase.maxSide) }
  }
}

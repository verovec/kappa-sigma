import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Card 0187: `LayerStats.measured` reads a plane's extremes in one specialised pass. The numbers
/// are the ones the lazy formula gave (the oracle below is that formula): the same minimum and
/// maximum of the finite values, `0` for a plane without one.
@Suite("LayerStats.measured — one pass over the finite values")
struct LayerStatsMeasuredTests {
  /// One plane and what its extremes must read.
  struct Case: CustomTestStringConvertible {
    let name: String
    let plane: [Float]
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(name: "a ramp", plane: (0..<64).map { Float($0) / 63 }),
    Case(name: "a NaN inside", plane: [0.5, .nan, 0.25, 0.75]),
    Case(name: "infinities are not finite", plane: [-.infinity, 0.5, .infinity, 0.75]),
    Case(name: "nothing finite", plane: [.nan, .infinity, -.infinity]),
    Case(name: "negatives", plane: [-3, -0.5, -7.25, -1]),
    Case(name: "one pixel", plane: [0.125]),
    Case(name: "empty", plane: []),
    Case(name: "signed zeros", plane: [-0.0, 0.0]),
  ]

  /// The formula 0187 replaces, kept as the oracle.
  static func oracle(_ plane: [Float]) -> (minimum: Double, maximum: Double) {
    let finite = plane.lazy.filter(\.isFinite)
    return (Double(finite.min() ?? 0), Double(finite.max() ?? 0))
  }

  @Test("testMeasured_MatchesLazyOracle", arguments: cases)
  func testMeasured_MatchesLazyOracle(_ testCase: Case) throws {
    // The plane and its mirror: on a tie (signed zeros) the first value wins, as the oracle has it.
    let planes = [testCase.plane, testCase.plane.reversed()]
    let image = AstroImage(
      width: max(testCase.plane.count, 1), height: 1, planes: planes,
      metadata: ImageMetadata(rowOrder: .topDown))

    let measured = LayerStats.measured(image)

    #expect(measured.channels.count == 2)
    for (channel, plane) in zip(measured.channels, planes) {
      let expected = Self.oracle(plane)
      #expect(channel.minimum.bitPattern == expected.minimum.bitPattern)
      #expect(channel.maximum.bitPattern == expected.maximum.bitPattern)
    }
  }

  /// The median and MADN beside the extremes are untouched: the strided sample's.
  @Test("testMeasured_KeepsTheStridedMedian")
  func testMeasured_KeepsTheStridedMedian() {
    let plane = (0..<1024).map { Float($0) / 1023 }
    let image = AstroImage(
      width: 32, height: 32, planes: [plane], metadata: ImageMetadata(rowOrder: .topDown))

    let measured = LayerStats.measured(image)

    let channel = measured.channels[0]
    #expect(channel.median == Double(plane[512]))
    #expect(channel.madn > 0)
    #expect(channel.minimum == 0 && channel.maximum == 1)
  }
}

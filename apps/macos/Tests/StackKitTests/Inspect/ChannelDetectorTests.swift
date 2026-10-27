import Foundation
import StackKit
import Testing

/// Translated from `internal/channeldetect/channeldetect_test.go`.
@Suite("ChannelDetector — unlabeled lights named by the wheel's cyclic order")
struct ChannelDetectorTests {
  typealias Fingerprint = ChannelDetector.Fingerprint
  typealias Sample = ChannelDetector.Sample

  static let fingerprints: [String: Fingerprint] = [
    "L": Fingerprint(background: 500, flux: 2000, starRichness: 0.050, exposureMs: 30000),
    "R": Fingerprint(background: 300, flux: 800, starRichness: 0.020, exposureMs: 30000),
    "G": Fingerprint(background: 280, flux: 900, starRichness: 0.025, exposureMs: 30000),
    "B": Fingerprint(background: 350, flux: 700, starRichness: 0.018, exposureMs: 30000),
    "Ha": Fingerprint(background: 120, flux: 150, starRichness: 0.002, exposureMs: 30000),
  ]

  /// Blocks of `perBlock` frames at a 31 s cadence, 200 s between blocks (a wheel move).
  static func build(_ filters: [String], perBlock: Int) -> [Sample] {
    var out: [Sample] = []
    var time = 0
    for (block, filter) in filters.enumerated() {
      if block > 0 { time += 200_000 }
      for _ in 0..<perBlock {
        out.append(
          Sample(
            order: time, path: String(format: "f%03d.fits", out.count),
            fingerprint: fingerprints[filter] ?? Fingerprint()))
        time += 31000
      }
    }
    return out
  }

  @Test(
    "block-captured cycles are labeled in wheel order",
    arguments: [["L", "R", "G", "B", "Ha"], ["L", "R", "G", "B", "Ha", "L", "R", "G", "B", "Ha"]])
  func testChannelDetector_cyclicOrder(sequence: [String]) {
    let samples = Self.build(sequence, perBlock: 6)
    let result = ChannelDetector.detect(samples)
    #expect(result.runs.count == sequence.count)
    let byPath = Dictionary(uniqueKeysWithValues: result.assignments.map { ($0.path, $0.filter) })
    for (index, sample) in samples.enumerated() {
      #expect(byPath[sample.path] == sequence[index / 6], "frame \(index)")
    }
    #expect(result.overallConfidence > 0.3)
  }

  @Test("a skipped filter keeps the signal anchors: L brightest, Ha faintest, broadband between")
  func testChannelDetector_skippedFilter() throws {
    let result = ChannelDetector.detect(Self.build(["L", "R", "B", "Ha"], perBlock: 6))
    try #require(result.runs.count == 4)
    #expect(result.runs[0].filter == "L")
    #expect(result.runs[3].filter == "Ha")
    #expect(result.runs[1...2].allSatisfy { ["R", "G", "B"].contains($0.filter) })
  }

  static func block(firstBackground: Double) -> [Sample] {
    (0..<6).map { index in
      Sample(
        order: index * 31000, path: String(format: "f%03d.fits", index),
        fingerprint: Fingerprint(
          background: index == 0 ? firstBackground : 300, flux: 800, starRichness: 0.02,
          exposureMs: 30000))
    }
  }

  @Test("an off-brightness first frame is flagged as a wheel transition; a settled one is not")
  func testChannelDetector_transitions() {
    let moving = ChannelDetector.detect(Self.block(firstBackground: 600))
    #expect(moving.runs.count == 1)
    #expect(moving.assignments.filter(\.wheelTransition).map(\.path) == ["f000.fits"])
    let settled = ChannelDetector.detect(Self.block(firstBackground: 305))
    #expect(!settled.assignments.contains { $0.wheelTransition })
  }

  @Test("the default wheel order is the Go port's L R G B Ha, whatever FilterKit adds later")
  func testChannelDetector_defaultOrder() {
    #expect(ChannelDetector.defaultOrder == ["L", "R", "G", "B", "Ha"])
    #expect(ChannelDetector.Options().order == ChannelDetector.defaultOrder)
  }

  @Test("no samples: no assignments, the default order")
  func testChannelDetector_empty() {
    let result = ChannelDetector.detect([])
    #expect(result.assignments.isEmpty)
    #expect(result.order == ChannelDetector.Options().order)
  }

  @Test("a star-rich run is never cheaply narrowband; neutral richness reduces to brightness")
  func testChannelDetector_emission() {
    #expect(abs(ChannelDetector.emission("Ha", level: 0, richness: 0)) < 1e-9)
    #expect(
      ChannelDetector.emission("Ha", level: 0, richness: 1)
        > ChannelDetector.emission("R", level: 0, richness: 1))
    #expect(
      abs(ChannelDetector.emission("Ha", level: 0.3, richness: 0.5) - (0.5 * 0.3 + 0.5 * 0.5))
        < 1e-9)
  }

  @Test(
    "a zero or negative lookahead disables transition flags instead of trapping",
    arguments: [0, -1])
  func testChannelDetector_lookaheadBounds(lookahead: Int) {
    var options = ChannelDetector.Options()
    options.transitionLookahead = lookahead
    let result = ChannelDetector.detect(Self.block(firstBackground: 600), options: options)
    #expect(!result.assignments.contains { $0.wheelTransition })
  }
}

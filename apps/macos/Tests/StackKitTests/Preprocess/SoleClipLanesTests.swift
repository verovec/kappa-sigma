import FilterKit
import StackKit
import Testing

/// Card 0162: a one-shot-colour run through one line clip alone never splits its lanes (the
/// Siril scripts stay those of a plain run); at assembly its one channel is read as that clip's
/// lane, so the emission step keeps it as the base AND writes its lines.
@Suite("Sole line clip — the colour channel is the clip's lane at assembly")
struct SoleClipLanesTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let channels: [String: String]
    let clip: FilterSet?
    let expected: [String: String]
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(
      name: "dual-band alone: RGB is the dual-band lane", channels: ["RGB": "trim_RGB"],
      clip: .dualband, expected: ["RGB-dualband": "trim_RGB"]),
    Case(
      name: "SII + OIII alone: RGB is the dualband-sii lane", channels: ["RGB": "trim_RGB"],
      clip: .dualbandSII, expected: ["RGB-dualband-sii": "trim_RGB"]),
    Case(
      name: "a custom colour name keeps its name", channels: ["CLS": "trim_CLS"],
      clip: .dualband, expected: ["CLS-dualband": "trim_CLS"]),
    Case(
      name: "broadband alone: unchanged", channels: ["RGB": "trim_RGB"], clip: .broadband,
      expected: ["RGB": "trim_RGB"]),
    Case(
      name: "no sole verdict: unchanged (unclassified is silence)",
      channels: ["RGB": "trim_RGB"], clip: nil, expected: ["RGB": "trim_RGB"]),
    Case(
      name: "a lane already named after its clip: unchanged",
      channels: ["RGB-dualband": "trim_RGB-dualband"], clip: .dualband,
      expected: ["RGB-dualband": "trim_RGB-dualband"]),
    Case(
      name: "two channels: unchanged", channels: ["Ha": "trim_Ha", "OIII": "trim_OIII"],
      clip: .dualband, expected: ["Ha": "trim_Ha", "OIII": "trim_OIII"]),
  ]

  @Test("testSoleClipLanes", arguments: cases)
  func testSoleClipLanes(row: Case) {
    #expect(Preprocessor.soleClipLanes(row.channels, clip: row.clip) == row.expected)
  }

  /// An inventory of OSC light sets with these verdicts (`nil` = unclassified).
  static func inventory(_ verdicts: [FilterSet?]) -> Inventory {
    var inventory = Inventory(root: "", frames: [])
    let keys = verdicts.indices.map { index in
      SetKey(
        type: .light, object: "IC 1848", filter: Filter.color, exposureMs: 60_000 + index,
        gain: 100, offset: 50, bin: 1, session: "", color: true)
    }
    inventory.sets = keys.map { FrameSet(key: $0, frames: [], indices: []) }
    for (key, verdict) in zip(keys, verdicts) {
      if let verdict { inventory.filterSets[key.id] = verdict }
    }
    return inventory
  }

  @Test(
    "testSoleVerdict: one clip only when every light set carries it",
    arguments: [
      ([FilterSet?.some(.dualband)], FilterSet?.some(.dualband)),
      ([.dualband, .dualband], .dualband),
      ([.dualband, nil], nil),
      ([.dualband, .unknown], nil),
      ([.dualband, .broadband], nil),
      ([nil], nil),
      ([.broadband], .broadband),
    ])
  func testSoleVerdict(verdicts: [FilterSet?], expected: FilterSet?) {
    #expect(FilterSetLanes.soleVerdict(in: Self.inventory(verdicts)) == expected)
  }
}

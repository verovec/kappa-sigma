import AstroStackApp
import FilterKit
import ProcessKit
import StackKit
import Testing

/// What an import tells the profile proposal (card 0060): the camera from the light sets' colour,
/// the filter composition from the clip-filter verdicts (OSC) or the filters (mono), the target
/// from the sets' object.
@Suite("Profile inputs from an import inventory")
struct ProfileInputsTests {
  /// A light set of the test inventory.
  struct LightSet: Sendable {
    let object: String
    let filter: String
    let color: Bool
    let verdict: FilterSet

    init(_ object: String, _ filter: String, _ color: Bool, _ verdict: FilterSet) {
      self.object = object
      self.filter = filter
      self.color = color
      self.verdict = verdict
    }
  }

  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let sets: [LightSet]
    let expected: ProfileProposal.Inputs
    var testDescription: String { name }
  }

  static func inventory(_ sets: [LightSet]) -> Inventory {
    var inventory = Inventory(root: "", frames: [])
    let keyed = sets.enumerated().map { index, set in
      (
        SetKey(
          type: .light, object: set.object, filter: set.filter, exposureMs: 60_000 + index,
          gain: 100, offset: 50, bin: 1, session: "", color: set.color), set.verdict
      )
    }
    inventory.sets = keyed.map { FrameSet(key: $0.0, frames: [], indices: [], filterSet: $0.1) }
    let colours = Set(sets.map(\.color))
    inventory.colorModel = colours.count > 1 ? .mixed : (colours.first == true ? .osc : .mono)
    inventory.filterSets = Dictionary(
      keyed.filter { $0.1.isKnown }.map { ($0.0.id, $0.1) }, uniquingKeysWith: { $1 })
    return inventory
  }

  @Test(
    "camera, filters and target as the captures say",
    arguments: [
      Case(
        name: "OSC broadband + dual-band",
        sets: [
          LightSet("M 31", Filter.color, true, .broadband),
          LightSet("M 31", Filter.color, true, .dualband),
        ],
        expected: .init(object: "M 31", camera: .osc, filters: .broadbandDualband)),
      Case(
        name: "OSC dual-band only", sets: [LightSet("IC 1848", Filter.color, true, .dualband)],
        expected: .init(object: "IC 1848", camera: .osc, filters: .dualband)),
      Case(
        name: "OSC SII+OIII only", sets: [LightSet("IC 1848", Filter.color, true, .dualbandSII)],
        expected: .init(object: "IC 1848", camera: .osc, filters: .dualband)),
      Case(
        name: "OSC broadband + multi-band",
        sets: [
          LightSet("M 31", Filter.color, true, .broadband),
          LightSet("M 31", Filter.color, true, .multiband),
        ],
        expected: .init(object: "M 31", camera: .osc, filters: .broadbandDualband)),
      Case(
        name: "OSC two line clips, no broadband",
        sets: [
          LightSet("IC 1848", Filter.color, true, .dualband),
          LightSet("IC 1848", Filter.color, true, .dualbandSII),
        ],
        expected: .init(object: "IC 1848", camera: .osc, filters: .dualband)),
      Case(
        name: "OSC, verdict unknown", sets: [LightSet("M 45", Filter.color, true, .unknown)],
        expected: .init(object: "M 45", camera: .osc, filters: nil)),
      Case(
        name: "OSC, one set unclassified",
        sets: [
          LightSet("M 45", Filter.color, true, .broadband),
          LightSet("M 45", Filter.color, true, .unknown),
        ],
        expected: .init(object: "M 45", camera: .osc, filters: nil)),
      Case(
        name: "mono LRGB",
        sets: ["L", "R", "G", "B"].map { LightSet("NGC 891", $0, false, .unknown) },
        expected: .init(object: "NGC 891", camera: .mono, filters: .lrgb)),
      Case(
        name: "mono LRGB + Hα",
        sets: ["L", "R", "G", "B", "Ha"].map { LightSet("M 31", $0, false, .unknown) },
        expected: .init(object: "M 31", camera: .mono, filters: .lrgbHa)),
      Case(
        name: "mono, filters by their aliases",
        sets: ["Lum", "Red", "Green", "Blue", "Halpha"].map {
          LightSet("M 31", $0, false, .unknown)
        },
        expected: .init(object: "M 31", camera: .mono, filters: .lrgbHa)),
      Case(
        name: "mono SHO",
        sets: ["Ha", "OIII", "SII"].map { LightSet("NGC 7000", $0, false, .unknown) },
        expected: .init(object: "NGC 7000", camera: .mono, filters: .narrowband)),
      Case(
        name: "mixed rigs, two targets",
        sets: [
          LightSet("M 31", Filter.color, true, .broadband), LightSet("M 33", "L", false, .unknown),
        ],
        expected: .init(object: nil, camera: nil, filters: nil)),
    ])
  func testInputs(_ example: Case) {
    #expect(ProfileProposal.Inputs(inventory: Self.inventory(example.sets)) == example.expected)
  }
}

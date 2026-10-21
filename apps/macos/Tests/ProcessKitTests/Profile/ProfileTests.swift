import CryptoKit
import Foundation
import ProcessKit
import Testing

/// Profiles (card 0060): object × filters × camera → pipeline + preprocessing + « why » notes,
/// five builtins from the PO's validated recipes, a proposal with its reasons, user copies.
@Suite("Profiles — builtins, proposal from the inventory, user copies")
struct ProfileTests {
  static func registry() throws -> ProcessRegistry { try ProcessRegistry.standard() }

  @Test(
    "five builtins parse; every value exists, within its bounds, with a fr + en why"
  )
  func testBuiltinsLoadAndValidate() throws {
    let registry = try Self.registry()
    let builtins = try ProfileLibrary.builtins(registry: registry)
    #expect(
      builtins.map(\.id).sorted() == [
        "cluster-osc-broadband", "emission-osc-dualband", "galaxy-mono-lrgb-ha",
        "galaxy-osc-broadband-dualband", "nebula-mono-narrowband",
      ])
    for profile in builtins {
      for (index, step) in profile.steps.enumerated() {
        let type = try #require(
          registry.type(id: step.recipe.processID), "\(profile.id) step \(index)")
        for id in step.values.keys {
          let spec = try #require(type.schema.spec(id), "\(profile.id): \(id)")
          let given = try #require(step.values[id])
          #expect(try spec.validated(given) == given, "\(profile.id): \(id) inside its bounds")
          let note = try #require(step.why[id], "\(profile.id): \(id) has a why")
          #expect(!note.english.isEmpty && !note.french.isEmpty && note.english != note.french)
        }
      }
      for id in profile.preprocessing.knobs.keys {
        #expect(profile.preprocessing.why[id] != nil, "\(profile.id): knob \(id) has a why")
      }
      #expect(!profile.title.english.isEmpty && !profile.title.french.isEmpty)
      #expect(
        profile.pipeline.problems(registry: registry, present: [.color, .emission, .starless]) == []
      )
    }
  }

  @Test("a target listed by several profiles still proposes the one that fits the captures")
  func testSharedTarget() throws {
    let builtins = try ProfileLibrary.builtins(registry: Self.registry())
    // Both OSC galaxy and cluster profiles name « M 31 » here: the broadband capture fits the
    // cluster profile only, which lists the target too, so it is proposed.
    let shared = try builtins.map { profile -> Profile in
      guard profile.id == "cluster-osc-broadband" else { return profile }
      var object = try #require(
        try JSONSerialization.jsonObject(with: profile.json()) as? [String: Any])
      object["examples"] = ["M 31", "M 45"]
      return try Profile.load(
        JSONSerialization.data(withJSONObject: object), registry: Self.registry())
    }
    let proposal = ProfileProposal.propose(
      .init(object: "M 31", camera: .osc, filters: .broadband), among: shared)
    #expect(proposal.proposed?.id == "cluster-osc-broadband")
  }

  @Test("the galaxy profile carries the PO's HaPlus values")
  func testGalaxyValues() throws {
    let galaxy = try #require(
      try ProfileLibrary.builtins(registry: Self.registry()).first {
        $0.id == "galaxy-osc-broadband-dualband"
      })
    let screens = try #require(galaxy.steps.first { $0.recipe.processID == "emission-screens" })
    #expect(
      screens.values["haBlack"] == .number(0.115) && screens.values["haOpacity"] == .number(0.95))
    #expect(screens.mode == .stop, "the screens are where the PO adjusts: a breakpoint")
    let stars = try #require(galaxy.steps.first { $0.recipe.processID == "star-recomposition" })
    #expect(stars.values["chroma"] == .number(0.25))
  }

  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let inputs: ProfileProposal.Inputs
    let proposed: String?
    let reasons: [ProfileProposal.Reason]
    let candidates: Int
    var testDescription: String { name }
  }

  @Test(
    "the proposal follows camera, filters and target, with reasons; ambiguity proposes nothing",
    arguments: [
      Case(
        name: "OSC BB+DB M 31",
        inputs: .init(object: "M31", camera: .osc, filters: .broadbandDualband),
        proposed: "galaxy-osc-broadband-dualband",
        reasons: [.camera(.osc), .filters(.broadbandDualband), .onlyMatch], candidates: 1),
      Case(
        name: "OSC DB IC 1848", inputs: .init(object: "IC 1848", camera: .osc, filters: .dualband),
        proposed: "emission-osc-dualband",
        reasons: [.camera(.osc), .filters(.dualband), .onlyMatch], candidates: 1),
      Case(
        name: "mono LRGB", inputs: .init(object: "NGC 891", camera: .mono, filters: .lrgb),
        proposed: "galaxy-mono-lrgb-ha",
        reasons: [.camera(.mono), .filters(.lrgb), .onlyMatch], candidates: 1),
      Case(
        name: "unknown camera and filters",
        inputs: .init(object: "Sh2-129", camera: nil, filters: nil),
        proposed: nil, reasons: [], candidates: 5),
      Case(
        name: "OSC, filters unknown, target known",
        inputs: .init(object: "m 45", camera: .osc, filters: nil),
        proposed: "cluster-osc-broadband",
        reasons: [.camera(.osc), .object("M 45")], candidates: 3),
      Case(
        name: "OSC broadband M 31: not a cluster",
        inputs: .init(object: "M 31", camera: .osc, filters: .broadband),
        proposed: nil, reasons: [], candidates: 1),
      Case(
        name: "camera unknown, known target",
        inputs: .init(object: "M 31", camera: nil, filters: nil),
        proposed: nil, reasons: [], candidates: 5),
      Case(
        name: "OSC, filters unknown, target unknown",
        inputs: .init(object: "NGC 891", camera: .osc, filters: nil),
        proposed: nil, reasons: [], candidates: 3),
    ])
  func testProposalFromInventory(_ example: Case) throws {
    let proposal = ProfileProposal.propose(
      example.inputs, among: try ProfileLibrary.builtins(registry: Self.registry()))
    #expect(proposal.proposed?.id == example.proposed)
    #expect(proposal.reasons == example.reasons)
    #expect(proposal.candidates.count == example.candidates)
  }
}

import CryptoKit
import Foundation
import ProcessKit
import Testing

/// User profiles (card 0060): saving over a builtin makes a user copy; the builtin never changes.
@Suite("Profile library — user copies shadow builtins, never overwrite them")
struct ProfileLibraryTests {
  static func digest(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
  }

  @Test(
    "a value the user sets gets its why; an unreadable or knob-invalid copy is left out, listed")
  func testUserValuesAndRejectedCopies() throws {
    let registry = try ProcessRegistry.standard()
    var copy = try #require(
      try ProfileLibrary.builtins(registry: registry).first { $0.id == "emission-osc-dualband" })
    try copy.set("oiiiOpacity", to: .number(0.6), inStep: 3)
    #expect(copy.steps[3].why["oiiiOpacity"] == Profile.userValue)
    #expect(
      try Profile.load(copy.json(), registry: registry).steps[3].values["oiiiOpacity"]
        == .number(0.6))
    let stored = [
      "emission-osc-dualband": try copy.json(), "broken": Data("{}".utf8),
      "galaxy-osc-broadband-dualband": try copy.json(),
    ]
    let library = try ProfileLibrary(
      registry: registry, user: { stored }, save: { _, _ in },
      acceptsKnob: { id, _ in id != "trail_mask_k" })
    #expect(library.profiles.count == 5)
    #expect(
      Set(library.rejected.keys) == [
        "broken", "emission-osc-dualband", "galaxy-osc-broadband-dualband",
      ], "a knob refused too, and a copy saved under another profile's id")
  }

  @Test("saving over a builtin creates a user copy; the builtin's bytes are unchanged")
  func testUserProfileNeverOverwritesBuiltin() throws {
    let registry = try ProcessRegistry.standard()
    let url = try #require(ProfileLibrary.builtinURL(id: "emission-osc-dualband"))
    let before = try Self.digest(url)
    let builtin = try #require(
      try ProfileLibrary.builtins(registry: registry).first { $0.id == "emission-osc-dualband" })

    var mine = builtin
    try mine.set("lumaDesat", to: .number(0.5), inStep: 4)
    var stored: [String: Data] = [:]
    let library = try ProfileLibrary(
      registry: registry, user: { stored }, save: { stored[$0] = $1 })
    try library.save(mine)

    #expect(try Self.digest(url) == before, "the builtin file is untouched")
    #expect(stored.keys.sorted() == ["emission-osc-dualband"])
    let reloaded = try ProfileLibrary(
      registry: registry, user: { stored }, save: { stored[$0] = $1 })
    #expect(
      reloaded.profile(id: "emission-osc-dualband")?.steps[4].values["lumaDesat"] == .number(0.5))
    #expect(reloaded.profile(id: "emission-osc-dualband")?.isUserCopy == true)
    #expect(
      reloaded.builtin(id: "emission-osc-dualband") == builtin, "the builtin is still offered")
    #expect(
      reloaded.profiles.count == 5, "a user copy shadows its builtin, it does not add a sixth")
  }

  @Test(
    "a profile JSON round-trips; an unknown process, an out-of-bounds value, no why: refused"
  )
  func testJSONRoundTripAndRefusals() throws {
    let registry = try ProcessRegistry.standard()
    let galaxy = try #require(try ProfileLibrary.builtins(registry: registry).first)
    #expect(try Profile.load(galaxy.json(), registry: registry) == galaxy)
    let object = try #require(
      try JSONSerialization.jsonObject(with: galaxy.json()) as? [String: Any])
    func step(_ change: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
      { profile in
        var steps = profile["steps"] as? [[String: Any]] ?? []
        change(&steps[1])
        profile["steps"] = steps
      }
    }
    let refusals: [(String, (inout [String: Any]) -> Void)] = [
      ("newer format", { $0["schemaVersion"] = 2 }),
      ("unknown camera", { $0["camera"] = "dslr" }),
      ("unknown process", step { $0["process"] = "nope" }),
      ("value out of bounds", step { $0["values"] = ["enabled": 3] }),
      ("missing why", step { $0["why"] = [:] }),
      (
        "a why for a value not set",
        step {
          $0["why"] = ["strength": ["en": "x", "fr": "y"], "strenght": ["en": "x", "fr": "y"]]
        }
      ),
      ("a version beyond Int", { $0["schemaVersion"] = 1e300 }),
      ("locked as a number", step { $0["locked"] = 1 }),
      ("version as a boolean", { $0["schemaVersion"] = true }),
    ]
    for (name, mutate) in refusals {
      var copy = object
      mutate(&copy)
      #expect(throws: (any Error).self, "\(name)") {
        try Profile.load(JSONSerialization.data(withJSONObject: copy), registry: registry)
      }
    }
  }
}

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

  @Test("saving over a builtin creates a user copy; the builtin's bytes are unchanged")
  func testUserProfileNeverOverwritesBuiltin() throws {
    let registry = try ProcessRegistry.standard()
    let url = try #require(ProfileLibrary.builtinURL(id: "emission-osc-dualband"))
    let before = try Self.digest(url)
    let builtin = try #require(
      try ProfileLibrary.builtins(registry: registry).first { $0.id == "emission-osc-dualband" })

    var mine = builtin
    try mine.set("lumaDesat", to: .number(0.5), inStep: 3)
    var stored: [String: Data] = [:]
    let library = try ProfileLibrary(
      registry: registry, user: { stored }, save: { stored[$0] = $1 })
    try library.save(mine)

    #expect(try Self.digest(url) == before, "the builtin file is untouched")
    #expect(stored.keys.sorted() == ["emission-osc-dualband"])
    let reloaded = try ProfileLibrary(
      registry: registry, user: { stored }, save: { stored[$0] = $1 })
    #expect(
      reloaded.profile(id: "emission-osc-dualband")?.steps[3].values["lumaDesat"] == .number(0.5))
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

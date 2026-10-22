import Foundation
import StackKit
import TestSupport
import Testing

/// `RunScope` (card 0095): one run stacks the lights of one object; every calibration set of the
/// inventory travels with it, the set ids stay the ones the scan gave, nothing is merged or
/// picked in silence.
@Suite("RunScope — the lights of one object, every calibration set, stable ids")
struct RunScopeTests {
  /// The synthetic single night (TESTFIELD, L R G B) plus a second target shot with the same
  /// train on the same night: its lights only, the calibration is shared.
  static func twoObjects() throws -> Inventory {
    var inventory = try single()
    let others = inventory.frames.filter { $0.type == .light }.map { frame -> CaptureFrame in
      var copy = frame
      copy.object = "OTHER"
      copy.path = frame.path.replacingOccurrences(of: ".fit", with: "_other.fit")
      return copy
    }
    inventory.frames += others
    // A file nothing typed: in no set, it must survive the scoping like the calibration does.
    var stray = CaptureFrame(path: inventory.root + "/stray.fits")
    stray.type = .unknown
    inventory.frames.append(stray)
    inventory.regroup()
    return inventory
  }

  static func single() throws -> Inventory {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    return try MasterBuilderTests.scan("golden-single-night", under: root)
  }

  static func lightIDs(_ inventory: Inventory) -> [String] {
    inventory.sets.filter { $0.key.type == .light }.map(\.key.id)
  }

  @Test(
    "one scope per object, in name order, each with every light set of its object",
    .scratchDirectory)
  func testScopesPerObject() throws {
    let two = try Self.twoObjects()
    let scopes = RunScope.scopes(of: two)
    #expect(scopes.map(\.object) == ["OTHER", "TESTFIELD"])
    #expect(scopes.map(\.setIDs.count) == [4, 4])
    #expect(scopes.map(\.lights) == [12, 12])
    #expect(Set(scopes.flatMap(\.setIDs)) == Set(Self.lightIDs(two)))
    #expect(
      scopes.allSatisfy { scope in scope.setIDs.allSatisfy { $0.contains("|\(scope.object)|") } })

    let one = RunScope.scopes(of: try Self.single())
    #expect(one.count == 1 && one[0].object == "TESTFIELD" && one[0].setIDs.count == 4)
    #expect(RunScope.scopes(of: Inventory(root: "", frames: [])).isEmpty)
  }

  @Test(
    "scoping by object keeps that object's lights only, every calibration set, and the ids",
    .scratchDirectory)
  func testScopedInventoryKeepsCalibration() throws {
    var two = try Self.twoObjects()
    two.colorModel = .mono
    let testfield = try #require(RunScope.scopes(of: two).first { $0.object == "TESTFIELD" })
    let luminance = try #require(testfield.setIDs.first { $0.contains("|L|") })
    two.filterSets[luminance] = .broadband
    two.regroup()

    let scoped = two.scoped(testfield)
    #expect(Self.lightIDs(scoped) == testfield.setIDs, "its lights, in the scan's order")
    #expect(scoped.frames.filter { $0.type == .light }.allSatisfy { $0.object == "TESTFIELD" })
    let calibration = { (inventory: Inventory) in
      inventory.sets.filter { $0.key.type != .light }.map(\.key.id)
    }
    #expect(calibration(scoped) == calibration(two), "darks, flats and bias all travel")
    #expect(scoped.frames.count == two.frames.count - 12)
    #expect(scoped.frames.contains { $0.type == .unknown }, "a frame in no set stays")
    // The ids are the scan's: every override and verdict stored under them still applies.
    #expect(Set(scoped.sets.map(\.key.id)).isSubset(of: Set(two.sets.map(\.key.id))))
    #expect(scoped.sets.first { $0.key.id == luminance }?.filterSet == .broadband)
    #expect(scoped.filterSets == [luminance: .broadband])
    #expect(scoped.colorModel == .mono && scoped.root == two.root)
    // Each set's indices point at its own frames in the scoped array.
    for set in scoped.sets {
      #expect(set.indices.map { scoped.frames[$0] } == set.frames)
    }

    // A single object scoped to itself is the same inventory.
    let one = try Self.single()
    let whole = one.scoped(try #require(RunScope.scopes(of: one).first))
    #expect(whole.sets == one.sets && whole.frames == one.frames)

    // Ids nothing matches leave no light: the guard below, never a silent fallback.
    let none = two.scoped(
      RunScope(object: "GHOST", setIDs: ["light|GHOST|L|e1|g0o0b1|i0|t0|s:"], lights: 0))
    #expect(Self.lightIDs(none).isEmpty && calibration(none) == calibration(two))
  }

  @Test(
    "a scan that moved since the series were chosen names the sets the scope does not list",
    .scratchDirectory)
  func testUnlistedSets() throws {
    let two = try Self.twoObjects()
    let testfield = try #require(RunScope.scopes(of: two).first { $0.object == "TESTFIELD" })
    #expect(testfield.unlistedSets(in: two).isEmpty, "nothing moved: nothing unlisted")
    // A quarter of this object's lights regrouped under a longer exposure: new set ids.
    var moved = two
    for index in moved.frames.indices
    where moved.frames[index].object == "TESTFIELD" && moved.frames[index].type == .light
      && index % 4 == 0
    {
      moved.frames[index].exposureMs += 1000
    }
    moved.regroup()
    let unlisted = testfield.unlistedSets(in: moved)
    #expect(!unlisted.isEmpty)
    #expect(unlisted.allSatisfy { $0.contains("|TESTFIELD|") && !testfield.setIDs.contains($0) })
    let other = try #require(RunScope.scopes(of: two).first { $0.object == "OTHER" })
    #expect(other.unlistedSets(in: moved).isEmpty, "the other object did not move")
    // A listed set the scan no longer has counts too: never stacked on the remainder.
    var shrunk = testfield
    shrunk.setIDs.append("light|TESTFIELD|X|e1|g0o0b1|i0|t0|s:")
    #expect(shrunk.unlistedSets(in: two) == ["light|TESTFIELD|X|e1|g0o0b1|i0|t0|s:"])
    // A scope mixing a mono object with an OSC one is not a mixed run on its own.
    var osc = two
    for index in osc.frames.indices where osc.frames[index].object == "OTHER" {
      osc.frames[index].channels = 3
    }
    osc.regroup()
    osc.colorModel = .mixed
    #expect(osc.scoped(testfield).colorModel == .mono)
  }

  @Test("a scope round-trips through JSON under its wire keys")
  func testScopeJSON() throws {
    let scope = RunScope(object: "M 31", setIDs: ["a", "b"], lights: 77)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try #require(String(bytes: try encoder.encode(scope), encoding: .utf8))
    #expect(json == #"{"lights":77,"object":"M 31","set_ids":["a","b"]}"#)
    #expect(try JSONDecoder().decode(RunScope.self, from: Data(json.utf8)) == scope)
  }
}

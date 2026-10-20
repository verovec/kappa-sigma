import Foundation
import StackKit
import Testing

/// Translated from `session_test.go` (NightKeyIn, sessionSummary, warnUndatedSplit),
/// `exclude_test.go` and `subset_test.go`.
@Suite("Inventory — sessions, exclusions, subsets")
struct InventoryTests {
  static let night = FrameSetTests.night

  static func inventory(_ frames: [CaptureFrame]) -> Inventory {
    var inventory = Inventory(root: "/cap", frames: frames)
    inventory.regroup()
    return inventory
  }

  @Test(
    "night keys bucket at local noon in a FIXED zone",
    arguments: [
      ("2023-02-27T22:55:00", "2023-02-27"), ("2023-02-28T03:40:00", "2023-02-27"),
      ("2023-02-28T11:59:59", "2023-02-27"), ("2023-02-28T12:00:00", "2023-02-28"),
    ])
  func testNight_key(local: String, expected: String) throws {
    let cet = try #require(TimeZone(secondsFromGMT: 3600))
    // The same wall-clock in UTC, shifted back by the zone's hour.
    let ms = CaptureFrame.parseDateObs(local) - 3_600_000
    #expect(Night.key(ms: ms, in: cet) == expected)
    #expect(Night.key(ms: 0, in: cet).isEmpty)
    #expect(Night.key(ms: -5, in: cet).isEmpty)
  }

  @Test("an all-undated scan has no session summary")
  func testSessions_undated() {
    #expect(SessionInfo.summary([Self.night(.light, "L", "", 30000, 250)]).isEmpty)
  }

  @Test("sessions: counts, time window and light configs per night, undated last")
  func testSessions_summary() throws {
    var first = Self.night(.light, "L", "2023-02-27", 30000, 250)
    first.dateObsMs = 1000
    var red = Self.night(.light, "R", "2023-02-27", 30000, 250)
    red.dateObsMs = 5000
    var flat = Self.night(.flat, "L", "2023-02-27", 5, 0)
    flat.dateObsMs = 3000
    var second = Self.night(.light, "L", "2023-03-15", 60000, 400)
    second.dateObsMs = 9000
    let stray = Self.night(.light, "L", "", 30000, 250)

    let sessions = SessionInfo.summary([first, red, flat, second, stray])
    try #require(sessions.count == 3)
    #expect(sessions[0].key == "2023-02-27")
    #expect(sessions[0].startMs == 1000)
    #expect(sessions[0].endMs == 5000)
    #expect(sessions[0].counts == [.light: 2, .flat: 1])
    #expect(sessions[0].configs.map(\.filter) == ["L", "R"])
    #expect(sessions[0].configs.first?.count == 1)
    #expect(sessions[1].configs.first?.exposureMs == 60000)
    #expect(sessions[2].key.isEmpty)
    #expect(sessions[2].counts == [.light: 1])
  }

  @Test("two nights plus undated frames warn about the undated bucket")
  func testInventory_warnUndatedSplit() {
    var inventory = Self.inventory([
      Self.night(.light, "L", "2023-02-27", 30000, 250),
      Self.night(.light, "L", "2023-03-15", 30000, 250),
      Self.night(.light, "L", "", 30000, 250),
    ])
    inventory.warnUndatedSplit()
    #expect(inventory.warnings.count == 1)
    #expect(inventory.warnings.first?.contains("no DATE-OBS") == true)
  }

  static func excludable() -> Inventory {
    let lights =
      Array(repeating: Self.night(.light, "R", "", 120_000, 139), count: 3)
      + Array(repeating: Self.night(.light, "L", "", 120_000, 139), count: 4)
    return Self.inventory(lights + [Self.night(.dark, "", "", 120_000, 139)])
  }

  @Test("excluding a set by id drops its frames only")
  func testInventory_excludeSets() throws {
    var inventory = Self.excludable()
    let red = try #require(inventory.sets.first { $0.key.filter == "R" }).key.id
    let removed = inventory.excludeSets([red])
    #expect(removed.frames == 3)
    #expect(removed.sets == 1)
    #expect(inventory.frames.count == 5)
    #expect(!inventory.sets.contains { $0.key.filter == "R" })
  }

  @Test("an unknown id or an empty list excludes nothing", arguments: [["LIGHT|nope|X|e1|g0o0b1|i0|t0|s:"], []])
  func testInventory_excludeSetsNoOp(ids: [String]) {
    var inventory = Self.excludable()
    let removed = inventory.excludeSets(ids)
    #expect(removed.frames == 0)
    #expect(removed.sets == 0)
    #expect(inventory.frames.count == 8)
  }

  static func subsetFixture() -> Inventory {
    func frame(_ path: String, _ filter: String, _ night: String, _ type: FrameType) -> CaptureFrame {
      var frame = CaptureFrame(path: path)
      frame.type = type
      frame.filter = filter
      frame.exposureMs = 60000
      frame.gain = 200
      frame.session = night
      return frame
    }
    var inventory = Self.inventory([
      frame("/cap/p01/L1.fit", "L", "2026-01-01", .light),
      frame("/cap/p01/L2.fit", "L", "2026-01-02", .light),
      frame("/cap/p02/L3.fit", "L", "2026-01-01", .light),
      frame("/cap/p02/L4.fit", "L", "2026-01-02", .light),
      frame("/cap/darks/D1.fit", "", "", .dark),
    ])
    inventory.warnings = ["w1"]
    return inventory
  }

  @Test(
    "a subset regroups afresh: a panel keeps the night split, one night collapses it",
    arguments: [
      ("/cap/p01/", "", 3, true), ("", "2026-01-01", 3, false), ("", "", 5, true),
      ("none", "", 0, false),
    ])
  func testInventory_subset(prefix: String, night: String, count: Int, split: Bool) {
    let inventory = Self.subsetFixture()
    let subset = inventory.subset { frame in
      if prefix == "none" { return false }
      guard frame.type == .light else { return true }
      return frame.path.hasPrefix(prefix) && (night.isEmpty || frame.session == night)
    }
    #expect(subset.root == "/cap")
    #expect(subset.frames.count == count)
    #expect(subset.warnings == ["w1"])
    for set in subset.sets where set.key.type == .light {
      #expect(set.key.session.isEmpty != split)
    }
  }
}

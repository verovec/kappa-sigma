import Foundation
import ProjectKit
import TestSupport
import Testing

/// `calibration_masters` (migration 0002, card 0047): the library index a reindex keeps in step
/// with the folder.
@Suite("ProjectStore — the calibration library index")
struct CalibrationMastersStoreTests {
  static func row(_ name: String, type: String = "DARK", frames: Int = 10, hash: String = "h")
    -> CalibrationMasterRow
  {
    var row = CalibrationMasterRow(path: "/lib/\(name).fits", type: type)
    row.exposureMs = 300_000
    row.gain = 100
    row.offset = 50
    row.tempMilliC = -10000
    row.hasTemp = true
    row.session = "2026-09-22"
    row.recipe = "abc"
    row.frameCount = frames
    row.poolHash = hash
    row.width = 6248
    row.height = 4176
    row.fileBytes = 1_234
    row.fileMtimeMs = 1_790_000_000_000
    return row
  }

  @Test(
    "a sync inserts, updates what changed, deletes what is gone, and round-trips every field",
    .scratchDirectory)
  func testCalibrationMasters_sync() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let first = try store.syncCalibrationMasters([Self.row("a"), Self.row("b", type: "BIAS")])
    #expect(first == CalibrationSyncReport(inserted: 2, updated: 0, deleted: 0))
    #expect(try store.calibrationMasters() == [Self.row("a"), Self.row("b", type: "BIAS")])

    let second = try store.syncCalibrationMasters([
      Self.row("a", frames: 30, hash: "h2"), Self.row("c"),
    ])
    #expect(second == CalibrationSyncReport(inserted: 1, updated: 1, deleted: 1))
    #expect(try store.calibrationMasters().map(\.path) == ["/lib/a.fits", "/lib/c.fits"])
    #expect(try store.calibrationMasters().first?.frameCount == 30)

    let unchanged = try store.syncCalibrationMasters([
      Self.row("a", frames: 30, hash: "h2"), Self.row("c"),
    ])
    #expect(unchanged == CalibrationSyncReport(inserted: 0, updated: 0, deleted: 0))
  }

  @Test("a type outside the four masters is refused by the schema", .scratchDirectory)
  func testCalibrationMasters_typeCheck() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    #expect(throws: (any Error).self) {
      try package.store.syncCalibrationMasters([Self.row("x", type: "LIGHT")])
    }
    #expect(try package.store.calibrationMasters().isEmpty)
  }
}

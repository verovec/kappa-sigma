import AstroStackApp
import Foundation
import StackKit
import Testing

/// Add a night (card 0100): a night imported into a project that already has nights rescans every
/// night, so the Stacking stage shows the full re-stack the next run is.
extension DataScanTests {
  @Test(
    "adding a night to a project with nights rescans every night, the new one included",
    .scratchDirectory)
  func testAddNightRescansEveryNight() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let recorder = Recorder()
    let window = Self.window(project, recorder: recorder)
    for folder in ["/c/M31-DB", "/c/M31-BB"] {
      window.startImport()
      let sheet = try #require(window.importing)
      sheet.choose(folder: URL(fileURLWithPath: folder))
      await sheet.settled()
      window.add(sheet.request)
    }
    #expect(window.isScanning, "the second night's plan alone describes one night")
    await window.scanSettled()
    #expect(recorder.requests.count == 3, "two sheets, then one rescan of the project")
    #expect(Set(recorder.requests.last?.paths ?? []) == ["/c/M31-DB", "/c/M31-BB"])
    #expect(window.scan != nil)
    #expect(window.isScanning == false)
  }

  @Test("a night recorded without the sheet starts no scan", .scratchDirectory)
  func testAddWithoutSheetScansNothing() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let recorder = Recorder()
    let window = Self.window(project, recorder: recorder)
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.add(ImportRequest(paths: ["/c/M31-BB"]))
    #expect(window.isScanning == false)
    #expect(recorder.requests.isEmpty)
  }
}

extension DataScanTests {
  @Test(
    "the window's re-stack plan: every scanned night, the folders no stack was built from",
    .scratchDirectory)
  func testWindowRestackPlan() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = Self.window(project)
    #expect(window.restackPlan == nil, "no scan: nothing to say")
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.rescan()
    await window.scanSettled()
    #expect(window.restackPlan == RestackPlan(nights: 1, frames: 36, added: nil))

    let night = try #require(window.sources.first)
    try project.store.addStack(bundlePath: "stacks/one", sourceIDs: [night.id], paramsJSON: "{}")
    window.add(ImportRequest(paths: ["/c/M31-BB"]))
    window.rescan()
    await window.scanSettled()
    #expect(window.restackPlan?.added == 1, "M31-BB is new since stacks/one")
  }
}

extension DataScanTests {
  @Test(
    "a first import whose plan is not adopted starts no scan: only adding a night does",
    .scratchDirectory)
  func testFirstImportNotAdoptedScansNothing() throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let recorder = Recorder()
    let window = Self.window(project, recorder: recorder)
    window.startImport()
    let sheet = try #require(window.importing)
    sheet.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    // Added before the sheet's scan settled: its plan is not the project's scan.
    window.add(sheet.request)
    #expect(window.scan == nil)
    #expect(window.isScanning == false, "the project had no night before: no rescan of it")
  }
}

extension DataScanTests {
  @Test(
    "a night added before its sheet settled still rescans every night", .scratchDirectory)
  func testAddNightBeforeSheetSettled() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let recorder = Recorder()
    let window = Self.window(project, recorder: recorder)
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.startImport()
    let sheet = try #require(window.importing)
    sheet.choose(folder: URL(fileURLWithPath: "/c/M31-BB"))
    window.add(sheet.request)
    #expect(window.isScanning)
    await window.scanSettled()
    #expect(Set(recorder.requests.last?.paths ?? []) == ["/c/M31-DB", "/c/M31-BB"])
  }
}

extension DataScanTests {
  @Test(
    "Add again of folders already recorded (the retry) rescans nothing", .scratchDirectory)
  func testReAddScansNothing() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let recorder = Recorder()
    let window = Self.window(project, recorder: recorder)
    window.add(ImportRequest(paths: ["/c/M31-DB", "/c/M31-BB"]))
    window.startImport()
    let sheet = try #require(window.importing)
    sheet.choose(folder: URL(fileURLWithPath: "/c/nights/../M31-BB"))
    await sheet.settled()
    window.add(sheet.request)
    #expect(window.isScanning == false)
    #expect(recorder.requests.count == 1, "the sheet's scan only")
  }

  @Test(
    "while every night is rescanned with no plan yet, Run waits for it", .scratchDirectory)
  func testRunWaitsForTheRescan() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = Self.window(project)
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    #expect(window.awaitsRescan == false)
    window.startImport()
    let sheet = try #require(window.importing)
    sheet.choose(folder: URL(fileURLWithPath: "/c/M31-BB"))
    await sheet.settled()
    window.add(sheet.request)
    #expect(window.awaitsRescan)
    #expect(window.canRun == false, "the plan is on screen before a run starts")
    await window.scanSettled()
    #expect(window.awaitsRescan == false)
    #expect(window.canRun)
  }
}

extension DataScanTests {
  @Test("a Rescan the user asks for never holds Run back", .scratchDirectory)
  func testManualRescanKeepsRun() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = Self.window(project)
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.rescan()
    #expect(window.isScanning)
    #expect(window.awaitsRescan == false)
    #expect(window.canRun)
    await window.scanSettled()
  }
}

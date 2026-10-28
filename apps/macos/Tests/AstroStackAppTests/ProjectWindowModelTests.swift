import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// The project window: its sources come from the store; an import adds them, read-only; and the
/// live planner indexes the calibration library into the project before scanning.
@MainActor
@Suite("ProjectWindowModel and ImportPlanning — sources and the live planner")
struct ProjectWindowModelTests {
  static func package() throws -> ProjectPackage {
    try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("P.astrostack"))
  }

  @Test(
    "adding an import records each folder as a read-only night source and closes the sheet",
    .scratchDirectory)
  func testAddRecordsSources() throws {
    let project = try Self.package()
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    #expect(window.sources.isEmpty)

    window.startImport()
    #expect(window.importing != nil)
    window.add(ImportRequest(paths: ["/c/M31-DB", "/c/M31-BB"]))

    #expect(window.importing == nil)
    #expect(window.sources.map(\.path) == ["/c/M31-DB", "/c/M31-BB"])
    #expect(window.sources.allSatisfy { $0.kind == .night && $0.readOnly })
    #expect(window.error == nil)
  }

  @Test("a store that fails is reported, not swallowed", .scratchDirectory)
  func testStoreFailure() throws {
    let project = try Self.package()
    let store = project.store
    try project.close()
    let window = ProjectWindowModel(store: { store }, planning: { _ in ImportPlanningStub.empty })
    #expect(window.error != nil)
    window.startImport()
    window.add(ImportRequest(paths: ["/c/A"]))
    #expect(window.importing != nil, "the sheet stays open when the source cannot be recorded")
  }

  @Test("without a document store nothing is recorded, and the sheet says why")
  func testNoStore() {
    let window = ProjectWindowModel(store: { nil }, planning: { _ in ImportPlanningStub.empty })
    window.startImport()
    window.add(ImportRequest(paths: ["/c/A"]))
    #expect(window.sources.isEmpty)
    #expect(window.error == .projectClosed, "Add never fails silently")
  }

  @Test("the live planner reindexes the library into the project, then scans", .scratchDirectory)
  func testLivePlannerIndexesLibrary() async throws {
    let project = try Self.package()
    defer { try? project.close() }
    let scratch = try ScratchDirectory.url
    let library = scratch.appendingPathComponent("library")
    let capture = scratch.appendingPathComponent("pad1/pad2/pad3/capture")
    for folder in [library, capture] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    try Data("bias".utf8).write(to: library.appendingPathComponent("master_BIAS_g100o50_b1.fits"))

    let planning = ImportPlanning.live(store: project.store, library: library, timeZone: .gmt)
    let plan = try await planning(ImportRequest(paths: [capture.path]))
    #expect(try project.store.calibrationMasters().map(\.type) == ["BIAS"])

    try Data("flat".utf8).write(
      to: library.appendingPathComponent("master_FLAT_15000ms_g100o50_b1_0C.fits"))
    _ = try await planning(ImportRequest(paths: [capture.path]))
    #expect(
      try project.store.calibrationMasters().map(\.type) == ["BIAS"],
      "one sheet indexes the library once")
    #expect(plan.warnings.contains("no light frames or videos found"))
    #expect(plan.calibration.isEmpty)
  }

  @Test(
    "without a library folder the planner still scans: every master is the capture's own",
    .scratchDirectory)
  func testLivePlannerWithoutLibrary() async throws {
    let scratch = try ScratchDirectory.url
    let capture = scratch.appendingPathComponent("pad1/pad2/pad3/capture")
    try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
    let plan = try await ImportPlanning.plan(
      ImportRequest(paths: [capture.path]),
      index: LibraryIndex(store: nil, folder: scratch.appendingPathComponent("absent")),
      timeZone: .gmt)
    #expect(plan.inventory.frames.isEmpty)
    #expect(ImportPlanning.capturesFolder.path.hasSuffix("Documents/astro/captures"))
    #expect(ImportPlanning.libraryFolder.path.hasSuffix("Documents/astro/library"))
  }
}

/// A planner that answers an empty plan.
enum ImportPlanningStub {
  static let empty: ImportViewModel.Planning = { request in
    ImportPlan(inventory: Inventory(root: "", frames: []), library: [], request: request)
  }
}

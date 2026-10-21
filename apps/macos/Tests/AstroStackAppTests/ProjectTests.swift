import AstroStackApp
import Foundation
import ImageKit
import ProjectKit
import StackKit
import TestSupport
import Testing

/// A run started from the Stacking stage: the import is planned again, StackKit writes into the
/// project's `stacks/<run_id>/`, and a finished run becomes a stack the Studio opens.
@MainActor
@Suite("Project runs — the stack registry and the Studio hand-off")
struct ProjectTests {
  nonisolated static let runID = "20261021_210000"
  /// 2026-10-21 21:00:00 UTC.
  nonisolated static let start = Date(timeIntervalSince1970: 1_792_616_400)

  /// A run that writes a two-layer bundle into its output and finishes, recording its request.
  static func fakeRun(_ seen: Recorded<PreprocessRequest>) -> RunServices.Run {
    { request in
      seen.append(request)
      return AsyncThrowingStream(PreprocessEvent.self) { continuation in
        do {
          try FileManager.default.createDirectory(
            at: request.output, withIntermediateDirectories: true)
          let bundle = try writeBundle(in: request.output, runID: request.runID)
          var result = PreprocessResult(runID: request.runID)
          result.bundle = bundle
          continuation.yield(
            .progress(
              .init(
                step: 1, steps: 1, title: "writing the linear bundle", percent: nil,
                line: "")))
          continuation.yield(.finished(result))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  nonisolated static func writeBundle(in folder: URL, runID: String) throws -> LinearBundle {
    let header = try FITSFile.parse(Data(("END" + String(repeating: " ", count: 2877)).utf8))
      .header
    var inputs: [BundleWriter.Input] = []
    for (filter, file, planes) in [("RGB", "rgb_base", 3), ("Ha", "syn_Ha", 1)] {
      let image = AstroImage(
        width: 4, height: 3,
        planes: (0..<planes).map { plane in (0..<12).map { Float($0 + plane) / 100 } },
        metadata: ImageMetadata(header: header))
      let url = folder.appendingPathComponent(file + ".fits")
      try FITSFile.create(image, keeping: nil, at: url)
      inputs.append(
        BundleWriter.Input(
          filter: filter, file: url, source: file == "rgb_base" ? "rgb_base" : "syn"))
    }
    return try BundleWriter().write(runID: runID, colorModel: .osc, layers: inputs, to: folder)
  }

  struct Fixture {
    let project: ProjectPackage
    let window: ProjectWindowModel
    let planned: Recorded<ImportRequest>
    let ran: Recorded<PreprocessRequest>
    let work: URL
  }

  static func fixture(run: RunServices.Run? = nil, saved: Bool = true) throws -> Fixture {
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("M31.astrostack"))
    let planned = Recorded<ImportRequest>()
    let ran = Recorded<PreprocessRequest>()
    let work = scratch.appendingPathComponent("work")
    let services = RunServices(
      run: run ?? fakeRun(ran), now: { Self.start }, scratch: work, timeZone: .gmt)
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      services: { _ in
        ImportServices(planning: { request in
          planned.append(request)
          return try await ImportPlanningStub.empty(request)
        })
      },
      runs: services, isSaved: { saved })
    return Fixture(
      project: project, window: window, planned: planned, ran: ran, work: work)
  }

  @Test(
    "a finished run adds a stack pointing at its bundle, with its images, and opens the Studio",
    .scratchDirectory)
  func testStackRegisteredAndOpened() async throws {
    let fixture = try Self.fixture()
    defer { try? fixture.project.close() }
    let window = fixture.window
    var request = ImportRequest(paths: ["/c/M31-DB", "/c/M31-BB"])
    request.filterSets = ["night-2026-09-22": .dualband]
    window.add(request)

    window.startRun(mode: .nebula)
    #expect(window.statuses[.stacking] == .running)
    await window.run?.settled()

    let store = fixture.project.store
    let stack = try #require(try store.stacks().first)
    #expect(stack.bundlePath == "stacks/\(Self.runID)")
    #expect(stack.sourceIDs == window.sources.map(\.id))
    #expect(
      try JSONDecoder().decode(ImportRequest.self, from: Data(stack.paramsJSON.utf8)) == request)
    #expect(try store.images(stackID: stack.id).map(\.role) == ["RGB", "Ha"])

    #expect(fixture.planned.all == [request], "the import as the user left it")
    let ran = try #require(fixture.ran.all.first)
    #expect(ran.output == fixture.project.url.appendingPathComponent("stacks/\(Self.runID)"))
    #expect(ran.runID == Self.runID && ran.mode == .nebula)
    #expect(!FileManager.default.fileExists(atPath: ran.work.path), "Siril's work files removed")

    #expect(window.selection == .studio)
    #expect(window.studio?.source.layers.map(\.id) == ["RGB", "Ha"])
    #expect(window.studio?.title == "M31 · \(Self.runID)")
    #expect(window.statuses[.stacking] == .done)
    #expect(window.statuses[.studio] == .ready)
  }

  @Test(
    "every import's overrides and calibration choices reach the run",
    .scratchDirectory)
  func testImportsMergedIntoTheRun() async throws {
    let fixture = try Self.fixture()
    defer { try? fixture.project.close() }
    var first = ImportRequest(paths: ["/c/M31-DB"])
    first.filterSets = ["night-2026-09-22": .dualband]
    first.calibExclude = ["dark|RGB|g100o50b1|e300000|t-17"]
    fixture.window.add(first)
    var second = ImportRequest(paths: ["/c/M31-BB"])
    second.forceCalibration = true
    fixture.window.add(second)

    fixture.window.startRun()
    await fixture.window.run?.settled()

    let planned = try #require(fixture.planned.all.first)
    #expect(planned.paths == ["/c/M31-DB", "/c/M31-BB"])
    #expect(planned.filterSets == first.filterSets, "the second import keeps the dual-band night")
    let ran = try #require(fixture.ran.all.first)
    #expect(ran.settings.calibrationExcluded == first.calibExclude)
    #expect(ran.settings.forceCalibration, "the latest import's choice")
  }

  @Test("a second run in the same second gets its own stack folder", .scratchDirectory)
  func testRunIDsNeverCollide() async throws {
    let fixture = try Self.fixture()
    defer { try? fixture.project.close() }
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    fixture.window.startRun()
    await fixture.window.run?.settled()
    fixture.window.startRun()
    await fixture.window.run?.settled()

    #expect(fixture.ran.all.map(\.runID) == [Self.runID, Self.runID + "_2"])
    #expect(
      try fixture.project.store.stacks().map(\.bundlePath) == [
        "stacks/\(Self.runID)", "stacks/\(Self.runID)_2",
      ])
  }

  @Test(
    "a stored request that no longer decodes is reported, not run without it",
    .scratchDirectory)
  func testUnreadableStoredRequestReported() throws {
    let fixture = try Self.fixture()
    defer { try? fixture.project.close() }
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    try fixture.project.store.addStack(
      bundlePath: "stacks/old", sourceIDs: [], paramsJSON: #"{"color_model": "rgb"}"#)
    fixture.window.startRun()

    #expect(fixture.window.run == nil)
    #expect(fixture.window.error == .inspect(.unknownColorChoice("rgb")))
  }

  @Test("an untitled project asks to be saved before a run", .scratchDirectory)
  func testUnsavedProjectRefused() throws {
    let fixture = try Self.fixture(saved: false)
    defer { try? fixture.project.close() }
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    fixture.window.startRun()

    #expect(fixture.window.run == nil)
    #expect(fixture.window.error == .projectUnsaved)
    #expect(fixture.ran.all.isEmpty)
  }

  @Test("a project with only a legacy run offers no Run", .scratchDirectory)
  func testLegacyRunOnlyCannotRun() throws {
    let fixture = try Self.fixture()
    defer { try? fixture.project.close() }
    try fixture.project.store.addSource(kind: .legacyRun, path: "/runs/M_31/20261018_191749")
    fixture.window.refresh()

    #expect(!fixture.window.canRun)
    fixture.window.startRun()
    #expect(fixture.window.run == nil)
  }

  @Test("a reopened project shows its latest stack in the Studio", .scratchDirectory)
  func testReopenShowsLatestStack() async throws {
    let fixture = try Self.fixture()
    defer { try? fixture.project.close() }
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    fixture.window.startRun()
    await fixture.window.run?.settled()

    let reopened = ProjectWindowModel(
      store: { fixture.project.store }, folder: { fixture.project.url },
      planning: { _ in ImportPlanningStub.empty })
    #expect(reopened.studio == nil)
    await reopened.openStudio()
    #expect(reopened.studio?.source.runID == Self.runID)
    #expect(reopened.selection == .studio, "the stage the project was left on")
  }

  @Test("a cancelled run registers no stack and stays on Stacking", .scratchDirectory)
  func testCancelledRunRegistersNothing() async throws {
    let fixture = try Self.fixture(run: { _ in
      AsyncThrowingStream(PreprocessEvent.self) { $0.finish(throwing: CancellationError()) }
    })
    defer { try? fixture.project.close() }
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    fixture.window.select(.stacking)
    fixture.window.startRun()
    await fixture.window.run?.settled()

    #expect(fixture.window.run?.phase == .cancelled)
    #expect(try fixture.project.store.stacks().isEmpty)
    #expect(fixture.window.selection == .stacking)
    #expect(fixture.window.statuses[.stacking] == .ready)
    #expect(!FileManager.default.fileExists(atPath: fixture.work.path + "/run_\(Self.runID)"))
  }

  @Test("no run starts without a capture night, nor a second one while one runs", .scratchDirectory)
  func testRunGuards() async throws {
    let fixture = try Self.fixture()
    defer { try? fixture.project.close() }
    fixture.window.startRun()
    #expect(fixture.window.run == nil)

    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    fixture.window.startRun()
    let first = fixture.window.run
    fixture.window.startRun()
    #expect(fixture.window.run === first)
    await first?.settled()
    #expect(fixture.ran.all.count == 1)
  }

  @Test(
    "the run id is the legacy yyyyMMdd_HHmmss of the start, in the user's time zone",
    arguments: [("GMT", "20261021_210000"), ("Europe/Paris", "20261021_230000")])
  func testRunID(_ zone: String, _ expected: String) throws {
    let timeZone = try #require(TimeZone(identifier: zone))
    #expect(RunServices.runID(at: Self.start, in: timeZone) == expected)
  }
}

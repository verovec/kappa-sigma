import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import StackKit
import TestSupport
import Testing

/// The Export stage (card 0091): StarNet as the Studio's first batch step, the deliverable set
/// written through `DeliverableExport` and recorded in `exports`, the guard's refusals worded.
@MainActor
@Suite(
  "ExportStageModel — star separation, deliverable set, exports record",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct ExportStageModelTests {
  /// 2026-10-22 12:00 UTC.
  nonisolated static let noon = Date(timeIntervalSince1970: 1_792_670_400)

  static func services(
    _ tools: HostTools = HostTools { _ in .missing(path: "/usr/local/bin/starnet2") }
  ) throws -> ExportServices {
    let root = try ScratchDirectory.url
    return ExportServices(
      tools: tools, scratch: root.appendingPathComponent("work"), astro: root,
      now: { Self.noon }, timeZone: try #require(TimeZone(identifier: "UTC")))
  }

  static func model(
    _ opened: StudioModelTests.Opened, studio: StudioModel, services: ExportServices,
    onExported: @escaping () -> Void = {}
  ) throws -> ExportStageModel {
    let stack = try #require(try opened.package.store.stack(id: opened.stackID))
    return ExportStageModel(
      studio: studio, stack: stack, store: opened.package.store,
      packageFolder: { opened.package.url },
      services: services, onExported: onExported)
  }

  @Test("testStarSeparationBatchStep", .scratchDirectory)
  func testStarSeparationBatchStep() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let binary = try FakeStarNet.install(in: try ScratchDirectory.url)
    let model = try Self.model(
      opened, studio: studio,
      services: try Self.services(HostTools { _ in .found(path: binary, version: nil) }))
    #expect(!model.hasStarless)

    await model.separateStars()

    #expect(model.progress == FakeStarNet.percents.map { $0 / 100 })
    #expect(model.failure == nil && model.installCard == nil && !model.isSeparating)
    #expect(studio.steps.map(\.processID) == ["channel-combination", StarSeparation.id])
    #expect(studio.steps.last?.outputs.keys.sorted { $0.rawValue < $1.rawValue } == [.starless])
    #expect(model.hasStarless)
    // The fake copies its input: the starless is the head through a 16-bit TIFF.
    let starless = try #require(try studio.session.history.layers()[.starless])
    let worst =
      zip(starless.planes.joined(), studio.head.planes.joined())
      .map { abs($0 - $1) }.max() ?? 1
    #expect(worst <= 1 / 65535 + 1e-6)
    // The step survives a reopen of the project (its schema is not the registry's).
    #expect(try StudioModelTests.model(opened).steps.last?.processID == StarSeparation.id)
    // StarNet's TIFFs went with their run's folder.
    let work = try ScratchDirectory.url.appendingPathComponent("work")
    #expect((try? FileManager.default.contentsOfDirectory(atPath: work.path))?.isEmpty ?? true)
  }

  @Test("a missing StarNet shows its install card: no fallback, no step", .scratchDirectory)
  func testStarSeparationMissingTool() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let model = try Self.model(opened, studio: studio, services: try Self.services())

    await model.separateStars()

    #expect(model.installCard?.state == .missing)
    #expect(model.progress.isEmpty && model.failure == nil)
    #expect(studio.steps.map(\.processID) == ["channel-combination"])
    #expect(!model.hasStarless)
  }

  /// A Studio whose head has a starless layer written by a host-tool step.
  static func separated(_ opened: StudioModelTests.Opened) throws -> StudioModel {
    let studio = try StudioModelTests.model(opened)
    let head = studio.head
    let starless = AstroImage(
      width: head.width, height: head.height, planes: head.planes.map { $0.map { $0 * 0.5 } },
      metadata: head.metadata)
    try studio.apply(
      StarSeparation.id, params: ParamSet(schema: StarSeparation.schema), result: head,
      outputs: [.starless: starless])
    return studio
  }

  @Test("testWritesSetAndRecordsExport", .scratchDirectory)
  func testWritesSetAndRecordsExport() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try Self.separated(opened)
    var recorded = 0
    let model = try Self.model(
      opened, studio: studio, services: try Self.services(), onExported: { recorded += 1 })
    let folder = model.folder
    #expect(
      folder
        == opened.package.url.appendingPathComponent(
          "exports/run1/2026-10-22-120000", isDirectory: true))
    model.settings.nameTemplate = "M31-{name}"

    await model.export()

    let names = ExportSettings.Deliverable.allCases.map { "M31-\($0.rawValue).png" }
    #expect(model.failure == nil)
    #expect(model.written.map(\.lastPathComponent) == names)
    #expect(
      names.allSatisfy { name in
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
      })
    let store = opened.package.store
    let rows = try store.exports(stackID: opened.stackID)
    #expect(rows.count == 1 && rows.first?.files == names)
    #expect(rows.first?.folder == folder.path)
    let image = try #require(
      try store.images(stackID: opened.stackID).first { $0.role == "studio" })
    #expect(rows.first?.headStepID == image.headStepID && image.headStepID != nil)
    #expect(model.exports == rows && recorded == 1)
    // The journey reads it through the production facts path.
    let window = ProjectWindowModel(store: { store })
    #expect(window.statuses[.export] == .done)
  }

  @Test("testRefusesProtectedFolderWithReason", .scratchDirectory)
  func testRefusesProtectedFolderWithReason() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try Self.separated(opened)
    let model = try Self.model(opened, studio: studio, services: try Self.services())
    let runs = try ScratchDirectory.url.appendingPathComponent("runs/M_31/out")
    model.folder = runs

    await model.export()

    #expect(model.failure == .exportReadOnlyFolder(path: runs.path))
    #expect(String(localized: try #require(model.failure).message).contains(runs.path))
    #expect(!FileManager.default.fileExists(atPath: runs.path))
    #expect(try opened.package.store.exports(stackID: opened.stackID).isEmpty)
    #expect(model.written.isEmpty)
  }

  @Test("without a starless only the final image is written, as the head", .scratchDirectory)
  func testWithoutStarlessWritesTheFinalOnly() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let model = try Self.model(opened, studio: studio, services: try Self.services())
    #expect(
      model.unavailableDeliverables
        == Set(ExportSettings.Deliverable.allCases).subtracting([.final]))

    await model.export()

    #expect(model.failure == nil)
    #expect(model.written.map(\.lastPathComponent) == ["final.png"])
    #expect(try opened.package.store.exports(stackID: opened.stackID).first?.files == ["final.png"])
  }

  /// Turns of the main actor until `done` holds or 20 s passed (StarNet is a real process).
  static func wait(_ done: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(20)
    while !done(), ContinuousClock.now < deadline { await Task.yield() }
  }

  @Test("Cancel stops StarNet: no step, no failure shown", .scratchDirectory)
  func testCancelSeparation() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let slow = FakeStarNet.script.replacingOccurrences(
      of: "cp \"$2\" \"$4\"", with: "exec sleep 30")
    let binary = try ScratchDirectory.url.appendingPathComponent("starnet2")
    try Data(slow.utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let model = try Self.model(
      opened, studio: studio,
      services: try Self.services(HostTools { _ in .found(path: binary.path, version: nil) }))

    model.startSeparation()
    await Self.wait { model.progress.count == FakeStarNet.percents.count }
    model.cancelSeparation()
    await Self.wait { !model.isSeparating }

    #expect(model.failure == nil)
    #expect(studio.steps.map(\.processID) == ["channel-combination"])
  }

  @Test("the starless state follows the Studio: undo, then steps after it", .scratchDirectory)
  func testStarlessFollowsTheHistory() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try Self.separated(opened)
    let model = try Self.model(opened, studio: studio, services: try Self.services())
    #expect(model.hasStarless && model.stepsAfterStarless == 0)
    try studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    #expect(model.stepsAfterStarless == 1)
    try studio.undo()
    try studio.undo()
    #expect(!model.hasStarless && model.unavailableDeliverables.count == 4)
  }

  @Test("an export never replaces files: the same folder twice is refused", .scratchDirectory)
  func testRefusesToOverwrite() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let model = try Self.model(opened, studio: studio, services: try Self.services())
    let used = model.folder
    await model.export()
    let first = try #require(model.written.first)
    // The default moves on (a second later at least, even on a fixed clock).
    #expect(model.folder != used)

    model.folder = used
    await model.export()

    #expect(model.failure == .exportWouldOverwrite(path: first.path))
    #expect(try opened.package.store.exports(stackID: opened.stackID).count == 1)
  }

  @Test("the default folder follows the package where it is now", .scratchDirectory)
  func testDefaultFolderFollowsThePackage() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    var place = opened.package.url
    let stack = try #require(try opened.package.store.stack(id: opened.stackID))
    let model = ExportStageModel(
      studio: try StudioModelTests.model(opened), stack: stack, store: opened.package.store,
      packageFolder: { place }, services: try Self.services())
    place = try ScratchDirectory.url.appendingPathComponent("Moved.astrostack")
    #expect(model.folder.path.hasPrefix(place.path))
    let chosen = try ScratchDirectory.url.appendingPathComponent("Deliverables")
    model.folder = chosen
    #expect(model.folder == chosen)
  }

  @Test(
    "a step applied while StarNet runs is never overwritten: the separation is refused",
    .scratchDirectory)
  func testHistoryMovedDuringSeparation() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let flag = try ScratchDirectory.url.appendingPathComponent("go")
    let waiting = FakeStarNet.script.replacingOccurrences(
      of: "cp \"$2\" \"$4\"",
      with: "while [ ! -f '\(flag.path)' ]; do sleep 0.05; done; cp \"$2\" \"$4\"")
    let binary = try ScratchDirectory.url.appendingPathComponent("starnet2")
    try Data(waiting.utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let model = try Self.model(
      opened, studio: studio,
      services: try Self.services(HostTools { _ in .found(path: binary.path, version: nil) }))

    model.startSeparation()
    await Self.wait { model.progress.count == FakeStarNet.percents.count }
    try studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    try Data().write(to: flag)
    await Self.wait { !model.isSeparating }

    #expect(model.failure == .history(.movedDuring(StarSeparation.id)))
    #expect(studio.steps.map(\.processID) == ["channel-combination", "stretch"])
  }

  @Test("the StarNet step has its own history title, in the view's language")
  func testStarSeparationTitle() throws {
    let french = try #require(
      StarSeparation.title(of: StarSeparation.id, locale: Locale(identifier: "fr")))
    #expect(String(localized: french) == "Séparation des étoiles (StarNet)")
    #expect(StarSeparation.title(of: "stretch") == nil)
  }
}

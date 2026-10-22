import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0094 in the Studio: greyed until the head is solved; Apply runs the method chosen and
/// only it — a failure leaves the head as it was and names the manual route.
@MainActor
@Suite(
  "Colour calibration in the Studio — solved head, one method, no fallback",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct ColourCalibrationProcessTests {
  nonisolated static let lists = [
    "log: OSC Sensors", "log: Sony IMX571", "log: Running command: spcc_list",
    "log: OSC Filters", "log: UV/IR Block", "log: Running command: spcc_list",
    "log: White References", "log: Average Spiral Galaxy",
  ]
  nonisolated static let solved = [
    "log: Found a solution for color calibration using 319 stars. Factors:",
    "log: After renormalization, the following coefficients are applied", "log: K0: 0.758",
    "log: K1: 0.929", "log: K2: 1.000",
  ]
  nonisolated static let failed = [
    "log: Not enough stars", "log: Error in line 5 ('spcc'): no solution.",
  ]

  /// A Siril answering `spcc_list` with `lists`, then the calibration with `run` (Siril's pixels
  /// halved on success).
  final class FakeSiril: Sendable {
    let succeeds: Bool
    private let scripts = Mutex<[String]>([])
    init(succeeds: Bool) { self.succeeds = succeeds }
    var calls: [String] { scripts.withLock { $0 } }

    var runner: SirilRunner {
      SirilRunner(run: { script, directory, onLine in
        let text = script.render()
        self.scripts.withLock { $0.append(text) }
        if text.contains("spcc_list") {
          for line in ColourCalibrationProcessTests.lists { onLine(SirilLine(parsing: line)) }
          return ""
        }
        let lines =
          self.succeeds
          ? ColourCalibrationProcessTests.solved : ColourCalibrationProcessTests.failed
        for line in lines { onLine(SirilLine(parsing: line)) }
        guard self.succeeds else {
          throw SirilError.scriptFailed(
            exitCode: 1, hint: SirilOutput.errorHint(log: lines.joined(separator: "\n")))
        }
        let input = try FITSFile.read(at: directory.appendingPathComponent("input.fits")).image()
        input.planes = input.planes.map { $0.map { $0 * 0.5 } }
        try FITSFile.create(
          input, keeping: nil, at: directory.appendingPathComponent("calibrated.fits"))
        return ""
      })
    }
  }

  struct Opened {
    let project: StudioModelTests.Opened
    let workspace: StudioWorkspaceModel
    let siril: FakeSiril
  }

  /// A Studio whose head is solved (a plate-solve step whose tool adds the solution) when `solve`.
  static func open(succeeds: Bool = true, solve: Bool = true) async throws -> Opened {
    let project = try StudioModelTests.project()
    let siril = FakeSiril(succeeds: succeeds)
    let catalogues = try ScratchDirectory.url.appendingPathComponent("catalogues")
    try FileManager.default.createDirectory(at: catalogues, withIntermediateDirectories: true)
    try Data().write(to: catalogues.appendingPathComponent("siril_cat1_healpix8_xpsamp_0.dat"))
    let support = try ScratchDirectory.url.appendingPathComponent("Support")
    let solveTool = StudioTool { image, _, _ in
      image.metadata.wcs = WCS(
        header: try PlateSolveProcessTests.header(PlateSolveProcessTests.solution))
      return StudioToolResult(image: image, report: nil)
    }
    let colour = ColourCalibrationTool.tool(scratch: try ScratchDirectory.url) {
      ColourCalibrator(siril: siril.runner, support: support, catalogues: catalogues)
    }
    let studio = try StudioModel(
      store: project.package.store, stackID: project.stackID, packageFolder: project.package.url,
      stackFolder: project.folder, bundle: StudioModelTests.bundle())
    let workspace = try StudioWorkspaceModel(
      studio: studio, base: [.color],
      tools: [PlateSolveProcess.id: solveTool, ColourCalibrationProcess.id: colour])
    if solve {
      workspace.choose(PlateSolveProcess.id)
      await workspace.runTool()
    }
    return Opened(project: project, workspace: workspace, siril: siril)
  }

  static func entry(_ workspace: StudioWorkspaceModel) -> StudioWorkspaceModel.Entry? {
    workspace.catalogue.flatMap(\.entries).first { $0.id == ColourCalibrationProcess.id }
  }

  @Test("greyed until the head carries a solution; enabled once solved", .scratchDirectory)
  func testRequiresSolvedHeader() async throws {
    let opened = try await Self.open(solve: false)
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    #expect(Self.entry(workspace)?.unavailable == .unsolved)
    #expect(
      StudioCatalogueView.reason(.unsolved, locale: Locale(identifier: "en"))
        == "Solve the image first (plate solving)")
    workspace.choose(PlateSolveProcess.id)
    await workspace.runTool()
    #expect(workspace.studio.head.metadata.wcs != nil)
    #expect(Self.entry(workspace)?.unavailable == nil)
  }

  @Test("SPCC: Siril's pixels recorded, the factors reported", .scratchDirectory)
  func testApplies() async throws {
    let opened = try await Self.open()
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    let before = workspace.studio.head.planes
    workspace.choose(ColourCalibrationProcess.id)
    #expect(await workspace.runTool())
    #expect(workspace.studio.steps.last?.processID == ColourCalibrationProcess.id)
    #expect(workspace.studio.head.planes == before.map { $0.map { $0 * 0.5 } })
    #expect(workspace.studio.head.metadata.wcs != nil, "the solution stays")
    let report = try #require(workspace.toolReport)
    #expect(
      String(localized: report(Locale(identifier: "en")))
        == "SPCC: R × 0.758, G × 0.929, B × 1, from 319 stars.")
  }

  @Test(
    "an SPCC failure: Siril's reason and the manual route, no PCC, head unchanged",
    .scratchDirectory)
  func testNoFallbackOnFailure() async throws {
    let opened = try await Self.open(succeeds: false)
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    let (steps, head) = (workspace.studio.steps.count, workspace.studio.head.planes)
    workspace.choose(ColourCalibrationProcess.id)
    #expect(await workspace.runTool() == false)
    #expect(workspace.studio.steps.count == steps && workspace.studio.head.planes == head)
    let error = ColourCalibrationError.failed(
      reason: "Not enough stars; Error in line 5 ('spcc'): no solution.")
    #expect(workspace.failure == UserFacingError(error).message)
    #expect(String(localized: UserFacingError(error).message).contains("Colour balance"))
    #expect(opened.siril.calls.filter { $0.contains("\nspcc ") }.count == 1, "SPCC once")
    #expect(opened.siril.calls.allSatisfy { !$0.contains("\npcc ") }, "no PCC after it")
  }

  @Test("unticked: Apply records the image itself, Siril never runs", .scratchDirectory)
  func testUntickedNeedsNoTool() async throws {
    let opened = try await Self.open()
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    let head = workspace.studio.head.planes
    workspace.choose(ColourCalibrationProcess.id)
    try #require(workspace.panel).set("enabled", .flag(false))
    await withCheckedContinuation { done in
      StudioUndo.apply(workspace, undoManager: UndoManager()) { done.resume() }
    }
    #expect(workspace.studio.steps.last?.processID == ColourCalibrationProcess.id)
    #expect(workspace.studio.head.planes == head)
    #expect(opened.siril.calls.isEmpty)
  }

  @Test("the panel's values as the request; PCC drops the names")
  func testRequest() throws {
    var params = ParamSet(schema: ColourCalibrationProcess.schema)
    let spcc = ColourCalibrationTool.request(params)
    #expect(
      spcc.method
        == .spcc(
          sensor: "Sony IMX571", filter: "UV/IR Block", whiteReference: "Average Spiral Galaxy"))
    #expect(spcc.limitMag == nil && spcc.catalogue == .localGaia)
    #expect(spcc.backgroundTolerance.below == 2.8 && spcc.backgroundTolerance.above == 2)
    try params.set("method", .choice("pcc"))
    try params.set("limitMag", .number(15))
    try params.set("catalogue", .choice("online-gaia"))
    let pcc = ColourCalibrationTool.request(params)
    #expect(pcc.method == .pcc && pcc.limitMag == 15 && pcc.catalogue == .online)
  }

  @Test("the report names Siril's imprecise-fit warning, in both languages")
  func testReportWarning() throws {
    let report = try #require(
      ColourCalibrationReport(lines: [
        "using 12 stars", "K0: 1", "K1: 0.9", "K2: 0.8",
        "The photometric color calibration seems to have found an imprecise solution",
      ]))
    let english = String(
      localized: ColourCalibrationTool.report(report, pcc: true, locale: Locale(identifier: "en")))
    let french = String(
      localized: ColourCalibrationTool.report(report, pcc: true, locale: Locale(identifier: "fr")))
    #expect(
      english.hasPrefix("PCC: R × 1, G × 0.9, B × 0.8, from 12 stars;")
        && english.contains("imprecise"))
    #expect(french.contains("G × 0,9") && french.contains("imprécis"))
  }
}

extension ColourCalibrationProcessTests {
  @Test(
    "every colour-calibration failure is a sentence of its own, in both languages",
    arguments: [
      ColourCalibrationError.unsolved, .unknownName(kind: .sensor, name: "Sony IMX999"),
      .unknownName(kind: .filter, name: "x"), .unknownName(kind: .whiteReference, name: "x"),
      .noFactors,
      .catalogueMissing(path: "/x"), .failed(reason: "no stars"), .noOutput(path: "/x/c.fits"),
    ])
  func testSentences(error: ColourCalibrationError) {
    #expect(UserFacingError(error) == .colourCalibration(error))
    var english = UserFacingError(error).message
    english.locale = Locale(identifier: "en")
    var french = UserFacingError(error).message
    french.locale = Locale(identifier: "fr")
    #expect(!String(localized: english).isEmpty)
    #expect(String(localized: english) != String(localized: french))
  }
}

extension ColourCalibrationProcessTests {
  @Test("no star count printed: none shown, Siril's warning kept")
  func testReportWithoutStars() throws {
    let plain = try #require(ColourCalibrationReport(lines: ["K0: 1", "K1: 0.9", "K2: 0.8"]))
    let warned = try #require(
      ColourCalibrationReport(lines: ["K0: 1", "K1: 0.9", "K2: 0.8", "an imprecise solution"]))
    let en = Locale(identifier: "en")
    #expect(
      String(localized: ColourCalibrationTool.report(plain, pcc: false, locale: en))
        == "SPCC: R × 1, G × 0.9, B × 0.8.")
    #expect(
      String(localized: ColourCalibrationTool.report(warned, pcc: false, locale: en)).hasSuffix(
        "extract the background first."))
  }
}

extension ColourCalibrationProcessTests {
  @Test(
    "under a mask a host tool is refused: it would not apply what the mask shows", .scratchDirectory
  )
  func testMaskRefused() async throws {
    let opened = try await Self.open()
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    let steps = workspace.studio.steps.count
    workspace.choose(ColourCalibrationProcess.id)
    workspace.mask = Mask(source: .luminosityRange(low: 0.2, high: 1, softness: 0.1))
    #expect(await workspace.runTool() == false)
    #expect(
      workspace.failure == .app("A host tool works on the whole image: clear the mask first."))
    #expect(workspace.studio.steps.count == steps && opened.siril.calls.isEmpty)
  }
}

extension ColourCalibrationProcessTests {
  @Test("a mask drawn while the tool runs: nothing recorded", .scratchDirectory)
  func testMaskDrawnDuringRun() async throws {
    let gate = AsyncStream<Void>.makeStream()
    let tool = StudioTool { image, _, _ in
      for await _ in gate.stream { break }
      return StudioToolResult(image: image, report: nil)
    }
    let project = try StudioModelTests.project()
    defer { try? project.package.close() }
    let studio = try StudioModel(
      store: project.package.store, stackID: project.stackID, packageFolder: project.package.url,
      stackFolder: project.folder, bundle: StudioModelTests.bundle())
    let workspace = try StudioWorkspaceModel(
      studio: studio, base: [.color], tools: [PlateSolveProcess.id: tool])
    workspace.choose(PlateSolveProcess.id)
    let steps = workspace.studio.steps.count
    await withCheckedContinuation { done in
      workspace.startTool { _ in done.resume() }
      Task { @MainActor in
        workspace.mask = Mask(source: .luminosityRange(low: 0.2, high: 1, softness: 0.1))
        gate.continuation.yield()
      }
    }
    #expect(workspace.studio.steps.count == steps)
    #expect(
      workspace.failure == .app("A host tool works on the whole image: clear the mask first."))
  }
}

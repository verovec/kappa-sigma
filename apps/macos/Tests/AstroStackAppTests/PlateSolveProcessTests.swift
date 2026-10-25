import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import RenderKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0093 in the Studio: the header's pointing and optics are offered, never set; Apply runs
/// Siril (here a fake that writes Siril's solved file) and records the head with the solution,
/// which the history keeps and the viewer's readout reads.
@MainActor
@Suite(
  "Plate solving in the Studio — suggestions, Apply through Siril, WCS kept",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct PlateSolveProcessTests {
  nonisolated static func header(_ lines: [String]) throws -> FITSHeader {
    var text = lines.map { $0.padding(toLength: 80, withPad: " ", startingAt: 0) }.joined()
    text += "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    return try FITSFile.parse(Data(text.utf8)).header
  }

  static let stackHeader = [
    "OBJECT  = 'M 31'", "OBJCTRA = '00 42 49.089'", "OBJCTDEC= '+41 16 15.592'",
    "FOCALLEN=                 249.", "XPIXSZ  =     3.75999999046326",
  ]
  nonisolated static let solution = [
    "CTYPE1  = 'RA---TAN'", "CTYPE2  = 'DEC--TAN'", "CRPIX1  = 4.5", "CRPIX2  = 4.5",
    "CRVAL1  = 10.7032408167172", "CRVAL2  = 41.2714040033193", "CD1_1   = -1.7E-04",
    "CD1_2   = 8.5E-04", "CD2_1   = -8.5E-04", "CD2_2   = -1.7E-04",
    "PLTSOLVD=                    T",
  ]

  /// A Siril that answers `platesolve` with the recorded lines and writes `solved.fits`.
  final class FakeSiril: Sendable {
    private let scripts = Mutex<[String]>([])
    var calls: [String] { scripts.withLock { $0 } }

    var runner: SirilRunner {
      SirilRunner(run: { script, directory, onLine in
        self.scripts.withLock { $0.append(script.render()) }
        let input = try FITSFile.read(at: directory.appendingPathComponent("input.fits")).image()
        for line in [
          "log: Up is +258.45 deg CounterclockWise wrt. N", "log: Resolution:      3.117 arcsec/px",
          "log: Image center: alpha: 00 42 48.778, delta: +41 16 17.054",
          "log: Fetched 1336 stars from Gaia DR3 astrometry catalogue",
        ] { onLine(SirilLine(parsing: line)) }
        try FITSFile.create(
          input, keeping: try PlateSolveProcessTests.header(PlateSolveProcessTests.solution),
          at: directory.appendingPathComponent("solved.fits"))
        return ""
      })
    }
  }

  struct Opened {
    let project: StudioModelTests.Opened
    let workspace: StudioWorkspaceModel
    let siril: FakeSiril
  }

  static func open(tools: [String: StudioTool]? = nil) throws -> Opened {
    let project = try StudioModelTests.project()
    let siril = FakeSiril()
    let catalogues = try ScratchDirectory.url.appendingPathComponent("catalogues")
    try FileManager.default.createDirectory(at: catalogues, withIntermediateDirectories: true)
    try Data().write(to: catalogues.appendingPathComponent("siril_cat_healpix8_astro.dat"))
    let support = try ScratchDirectory.url.appendingPathComponent("Support")
    let tool = PlateSolveTool.tool(scratch: try ScratchDirectory.url) {
      PlateSolver(siril: siril.runner, support: support, catalogues: catalogues)
    }
    let studio = try StudioModel(
      store: project.package.store, stackID: project.stackID, packageFolder: project.package.url,
      stackFolder: project.folder, bundle: StudioModelTests.bundle(),
      header: try header(stackHeader))
    let workspace = try StudioWorkspaceModel(
      studio: studio, base: [.color], tools: tools ?? [PlateSolveProcess.id: tool])
    return Opened(project: project, workspace: workspace, siril: siril)
  }

  @Test("the header's offers first, then the catalogue object's; nothing taken", .scratchDirectory)
  func testPlateSolveOffersHeaderThenCatalogue() throws {
    let opened = try Self.open()
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    workspace.catalogueObject = {
      SkyObject(name: "M31", raDeg: 10.684793, decDeg: 41.269065, source: .messier)
    }
    workspace.choose(PlateSolveProcess.id)
    let panel = try #require(workspace.panel)
    #expect(
      panel.suggestions.map(\.reason) == Array(repeating: PlateSolveProcess.fromHeader, count: 4)
        + [PlateSolveProcess.fromCatalogue, PlateSolveProcess.fromCatalogue])
    #expect(panel.suggestions.suffix(2).map(\.value) == [.text("10.684793"), .text("41.269065")])
    #expect(panel.suggestions.last?.subject == "M31")
    #expect(panel.params == ParamSet(schema: PlateSolveProcess.schema), "nothing taken")
    #expect(panel.solved == nil, "the stack header carries no solution")
    let english = Locale(identifier: "en")
    #expect(
      ProcessPanelModel.words(
        reason: PlateSolveProcess.fromCatalogue, subject: "Sh2-132", locale: english)
        == "From the catalogue (Sh2-132)")
    #expect(
      ProcessPanelModel.words(
        reason: PlateSolveProcess.fromCatalogue, subject: "Sh2-132",
        locale: Locale(identifier: "fr"))
        == "Depuis le catalogue (Sh2-132)")
    let solved = try #require(
      PlateSolveStatus(
        wcs: WCS(header: try Self.header(Self.solution)), width: 8, height: 8))
    #expect(
      ProcessPanelModel.solvedWords(solved, locale: english)
        == "Already solved: centre 00h42m48.8s +41°16′17″, 3.12″/px")
  }

  @Test(
    "the header's values are offered, the panel stays empty; Apply refuses empty coordinates",
    .scratchDirectory)
  func testSuggestionsNeverApplied() async throws {
    let opened = try Self.open()
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    workspace.choose(PlateSolveProcess.id)
    let panel = try #require(workspace.panel)
    let reason = PlateSolveProcess.fromHeader
    #expect(
      panel.suggestions == [
        Suggestion(paramID: "ra", value: .text("00 42 49.089"), reason: reason),
        Suggestion(paramID: "dec", value: .text("+41 16 15.592"), reason: reason),
        Suggestion(paramID: "focalMm", value: .number(249), reason: reason),
        Suggestion(paramID: "pixelSizeUm", value: .number(3.75999999046326), reason: reason),
      ])
    #expect(panel.params == ParamSet(schema: PlateSolveProcess.schema), "nothing taken yet")

    await workspace.runTool()
    #expect(workspace.studio.steps.count == 1, "only the channel combination")
    #expect(
      workspace.failure == UserFacingError(PlateSolveTool.InputError.coordinatesMissing).message)
    #expect(opened.siril.calls.isEmpty, "Siril never ran")

    panel.take(reason: reason)
    #expect(panel.params.text("ra") == "00 42 49.089")
    #expect(panel.params.number("focalMm") == 249)
  }

  @Test(
    "the solve's step keeps the solution: readout, undo, redo, the step's file", .scratchDirectory)
  func testWCSKeptInHistory() async throws {
    let opened = try Self.open()
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    workspace.choose(PlateSolveProcess.id)
    let panel = try #require(workspace.panel)
    panel.take(reason: PlateSolveProcess.fromHeader)
    let before = workspace.studio.head.planes

    await workspace.runTool()
    #expect(workspace.failure == nil)
    #expect(
      workspace.studio.steps.map(\.processID) == [
        ChannelCombinationProcess.id, PlateSolveProcess.id,
      ])
    #expect(workspace.studio.head.planes == before, "a solve never changes a pixel")
    // OBJCTRA 00 42 49.089 / OBJCTDEC +41 16 15.592, as taken, in degrees.
    #expect(opened.siril.calls.first?.contains("platesolve 10.70453") == true)
    #expect(opened.siril.calls.first?.contains(",41.27099") == true)
    #expect(
      opened.siril.calls.first?.contains(
        "-force -focal=249 -pixelsize=3.75999999046326 -catalog=localgaia -noflip") == true)
    let readout = try #require(PixelReadout(image: workspace.viewer.model.image, x: 3, y: 3))
    let sky = try #require(readout.sky, "the viewer reads RA/Dec now")
    // Within a pixel (3.1″) of the reference pixel's position.
    #expect(abs(sky.ra - 10.7032408167172) < 2e-3 && abs(sky.dec - 41.2714040033193) < 1e-3)
    let step = try #require(workspace.studio.steps.last)
    let file = try FITSFile.read(
      at: workspace.studio.session.history.directory.appendingPathComponent(step.file))
    #expect(file.header.string("PLTSOLVD") == "T")
    #expect(file.header.string("OBJECT") == "M 31", "the stack's own cards stay")
    let report = try #require(workspace.toolReport)
    #expect(String(localized: report(Locale(identifier: "en"))).contains("3.117″/px"))

    try workspace.undo()
    #expect(workspace.studio.head.metadata.wcs == nil)
    try workspace.redo()
    #expect(workspace.studio.head.metadata.wcs != nil)
  }

  @Test("a head moved during the run, or a stop: nothing is recorded", .scratchDirectory)
  func testNothingRecordedOffHead() async throws {
    let gate = AsyncStream<Void>.makeStream()
    let tool = StudioTool { image, _, _ in
      for await _ in gate.stream { break }
      try Task.checkCancellation()
      return StudioToolResult(image: image, report: nil)
    }
    let opened = try Self.open(tools: [PlateSolveProcess.id: tool])
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    workspace.choose(PlateSolveProcess.id)

    await withCheckedContinuation { done in
      workspace.startTool { _ in done.resume() }
      Task { @MainActor in
        try? workspace.undo()
        gate.continuation.yield()
      }
    }
    #expect(workspace.studio.steps.isEmpty)
    #expect(
      workspace.failure == .app("The image changed while the tool ran: nothing was recorded."))

    await withCheckedContinuation { done in
      workspace.startTool { _ in done.resume() }
      workspace.cancelTool()
    }
    #expect(workspace.studio.steps.isEmpty)
    #expect(workspace.failure == .app("Stopped: nothing was recorded."))
    #expect(workspace.toolRun == nil)
  }

  @Test(
    "without its tool, plate solving is refused, never recorded from its preview", .scratchDirectory
  )
  func testNoTool() async throws {
    let opened = try Self.open(tools: [:])
    defer { try? opened.project.package.close() }
    opened.workspace.choose(PlateSolveProcess.id)
    await opened.workspace.runTool()
    #expect(
      opened.workspace.failure == UserFacingError(StudioError.needsTool("plate-solve")).message)
    #expect(opened.workspace.studio.steps.count == 1)
  }
}

extension PlateSolveProcessTests {
  @Test("a second Apply while the tool runs is refused with a sentence", .scratchDirectory)
  func testSecondApplyRefused() async throws {
    let gate = AsyncStream<Void>.makeStream()
    let tool = StudioTool { image, _, _ in
      for await _ in gate.stream { break }
      return StudioToolResult(image: image, report: nil)
    }
    let opened = try Self.open(tools: [PlateSolveProcess.id: tool])
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    workspace.choose(PlateSolveProcess.id)
    await withCheckedContinuation { done in
      workspace.startTool { _ in done.resume() }
      workspace.startTool { recorded in #expect(!recorded) }
      #expect(workspace.failure == .app("A tool is already running: wait for it, or stop it."))
      gate.continuation.yield()
    }
    #expect(workspace.studio.steps.last?.processID == PlateSolveProcess.id)
  }
}

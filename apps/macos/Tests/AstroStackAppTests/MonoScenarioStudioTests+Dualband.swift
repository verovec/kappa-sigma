import AstroStackApp
import ProcessKit
import StackKit
import Testing

/// Card 0162: an OSC run through a dual-band clip alone keeps its colour base and also brings
/// the Hα and [OIII] layers, so the emission processes are offered and the dual-band profile runs.
extension MonoScenarioStudioTests {
  static let emissionProcesses = [EmissionScreensProcess.id, LineInjectionProcess.id]

  static func catalogueReasons(_ workspace: StudioWorkspaceModel) -> [String: StudioUnavailable?] {
    let entries = workspace.catalogue.flatMap(\.entries)
    return Dictionary(
      uniqueKeysWithValues: emissionProcesses.compactMap { id in
        entries.first { $0.id == id }.map { (id, $0.unavailable) }
      })
  }

  @Test(
    "testDualbandOnlyEmission: screens and injection offered, Hα and [OIII] rows, no SII row",
    .scratchDirectory)
  func testDualbandOnlyEmission() throws {
    let (workspace, opened) = try Self.workspace(.oscDualband)
    defer { try? opened.package.close() }
    let reasons = Self.catalogueReasons(workspace)
    #expect(reasons.count == Self.emissionProcesses.count)
    for id in Self.emissionProcesses {
      #expect(
        reasons[id] == .some(nil), "\(id) must be offered: \(String(describing: reasons[id]))")
    }
    for id in Self.emissionProcesses {
      workspace.choose(id)
      let panel = try #require(workspace.panel)
      panel.showsAdvanced = true
      let ids = panel.visibleSpecs.map(\.id)
      #expect(ids.contains { $0.hasPrefix("ha") } && ids.contains { $0.hasPrefix("oiii") }, "\(id)")
      #expect(!ids.contains { $0.hasPrefix("sii") }, "\(id): no SII layer, no SII row")
      workspace.closePanel()
    }
  }

  @Test(
    "testBroadbandBaseAlone: without the line layers both processes say what is missing",
    .scratchDirectory)
  func testBroadbandBaseAlone() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: Self.bundle(["RGB": 3]))
    let workspace = try StudioWorkspaceModel(studio: studio, base: [StudioBundle.role(of: .rgb)])
    for (id, reason) in Self.catalogueReasons(workspace) {
      #expect(reason == .missing([.emission]), "\(id)")
    }
  }

  @Test(
    "testDualbandProfileRuns: emission-osc-dualband runs on the dual-band-only bundle, no refusal",
    .scratchDirectory)
  func testDualbandProfileRuns() async throws {
    let (workspace, opened) = try Self.workspace(.oscDualband)
    defer { try? opened.package.close() }
    let registry = try ProcessRegistry.standard()
    let profile = try #require(
      try ProfileLibrary.builtins(registry: registry).first { $0.id == "emission-osc-dualband" })
    let planes = try #require(Self.expected[.oscDualband]).planes
    let present = Set(planes.keys.map { StudioBundle.role(of: LinearBundle.Role(filter: $0)) })
    let problems = profile.pipeline.stepProblems(registry: registry, present: present)
    #expect(problems == problems.map { _ in [] }, "no step refused: \(problems)")
    let sidebar = try PipelineSidebarModel(
      workspace: workspace, pipeline: profile.pipeline, store: opened.package.store, base: present)
    workspace.pipeline = sidebar
    await sidebar.run()
    #expect(sidebar.failure == nil)
    #expect(sidebar.stoppedAt == 3 && workspace.panel?.type.id == EmissionScreensProcess.id)
  }
}

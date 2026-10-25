import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Card 0121 through the window model: a split scope's lane values and processing choice reach
/// the run and its record; a scope that does not split records neither, as before 0121.
@MainActor
@Suite("Project runs — lane knobs and the processing choice applied and recorded")
struct ProjectLaneKnobTests {
  /// A saved project whose planner scans M 31 over a broadband and a dual-band night, scanned.
  static func project() async throws -> (
    project: ProjectPackage, window: ProjectWindowModel, ran: Recorded<PreprocessRequest>
  ) {
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("M31.astrostack"))
    let ran = Recorded<PreprocessRequest>()
    let inventory = KnobPanelViewModelTests.inventory([.broadband, .dualband])
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      services: { _ in
        ImportServices(planning: { request in
          ImportPlan(inventory: inventory, library: [], request: request)
        })
      },
      runs: RunServices(
        run: ProjectTests.fakeRun(ran), now: { ProjectTests.start },
        scratch: scratch.appendingPathComponent("work"), timeZone: .gmt))
    window.add(ImportRequest(paths: ["/c/M 31"]))
    window.rescan()
    await window.scanSettled()
    return (project, window, ran)
  }

  @Test("a split run applies and records the lane values and « Per channel »", .scratchDirectory)
  func testSplitRunRecordsLanes() async throws {
    let (project, window, ran) = try await Self.project()
    defer { try? project.close() }
    #expect(window.series.laneColumns == [.broadband, .dualband])
    window.knobs.set("stack_reject", to: .choice("sigma"), lane: .dualband)
    window.knobs.processing = .perChannel
    window.startRun()
    await ProjectScopeTests.queueSettled(window)

    let patch = KnobPatch(values: ["stack_reject": .choice("sigma")])
    #expect(ran.all.first?.laneOverrides == [.dualband: patch])
    let stack = try #require(try project.store.latestStack())
    let record = try StackRecord(stack: stack)
    #expect(record.laneKnobs == [.dualband: patch] && record.processing == .perChannel)
  }

  @Test(
    "with the dual-band night unchecked, the run records no lane and one flow", .scratchDirectory)
  func testUnsplitRunRecordsNoLane() async throws {
    let (project, window, ran) = try await Self.project()
    defer { try? project.close() }
    window.knobs.set("stack_reject", to: .choice("sigma"), lane: .dualband)
    window.knobs.processing = .perChannel
    let dualband = try #require(
      window.series.groups.flatMap(\.nights).flatMap(\.series).first { $0.filterSet == .dualband })
    window.series.set(dualband.id, checked: false)
    window.startRun()
    await ProjectScopeTests.queueSettled(window)

    #expect(ran.all.first?.laneOverrides.isEmpty == true)
    let stack = try #require(try project.store.latestStack())
    #expect(!stack.paramsJSON.contains("lane_knobs") && !stack.paramsJSON.contains("processing"))
  }
}

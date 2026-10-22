import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import SwiftUI
import StackKit
import TestSupport
import Testing

/// Card 0095 through the window model: one run per object with a checked series, queued in the
/// table's order, each stack recorded with its object and scope; the Studio opens the chosen stack.
@MainActor
@Suite("Project runs — one run per object, the chosen stack")
struct ProjectScopeTests {
  /// The queue runs until no run is going (a finished run starts the next scope).
  static func queueSettled(_ window: ProjectWindowModel) async {
    while let run = window.run, run.isRunning { await run.settled() }
  }

  /// A saved project whose planner scans M 31 and IC 1848 together, scanned once.
  static func twoObjects() async throws -> (
    project: ProjectPackage, window: ProjectWindowModel, ran: Recorded<PreprocessRequest>
  ) {
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("M31.astrostack"))
    let ran = Recorded<PreprocessRequest>()
    let inventory = StackingStageModelTests.inventory(objects: ["M 31", "IC 1848"])
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      services: { _ in
        ImportServices(planning: { request in
          ImportPlan(inventory: inventory, library: [], request: request)
        })
      },
      runs: RunServices(
        run: ProjectTests.fakeRun(ran), now: { ProjectTests.start },
        scratch: scratch.appendingPathComponent("work"),
        timeZone: .gmt))
    window.add(ImportRequest(paths: ["/c/M 31", "/c/IC 1848"]))
    window.rescan()
    await window.scanSettled()
    return (project, window, ran)
  }

  @Test(
    "two objects in one project queue two runs, one stack each with its object and scope",
    .scratchDirectory)
  func testTwoObjectsQueueTwoRuns() async throws {
    let (project, window, ran) = try await Self.twoObjects()
    defer { try? project.close() }
    #expect(window.series.scopes.map(\.object) == ["IC 1848", "M 31"])

    window.startRun()
    #expect(window.statuses[.stacking] == .running)
    await Self.queueSettled(window)

    #expect(ran.all.count == 2, "one run per object, in order")
    let lights = ran.all.map { Set($0.inventory.frames.filter { $0.type == .light }.map(\.object)) }
    #expect(lights == [["IC 1848"], ["M 31"]])
    #expect(
      ran.all.allSatisfy { $0.inventory.sets.contains { $0.key.type == .dark } },
      "calibration travels")
    let stacks = try project.store.stacks()
    #expect(stacks.map(\.object) == ["IC 1848", "M 31"])
    #expect(
      stacks.map(\.bundlePath) == [
        "stacks/\(ProjectTests.runID)", "stacks/\(ProjectTests.runID)_2",
      ])
    for stack in stacks {
      let record = try StackRecord(stack: stack)
      #expect(record.scope?.object == stack.object && record.scope?.lights == 3)
      let scope = try JSONDecoder().decode(
        RunScope.self, from: Data(try #require(stack.scopeJSON).utf8))
      #expect(scope == record.scope)
    }
    #expect(
      window.selectedStackID == stacks.last?.id, "the Studio shows the last stack of the queue")
    #expect(window.studio?.source.object == "M 31")
    #expect(window.selection == .studio)

    // One series unchecked: its object leaves the queue.
    let ic1848 = try #require(window.series.groups.first { $0.object == "IC 1848" })
    for series in ic1848.nights.flatMap(\.series) { window.series.set(series.id, checked: false) }
    #expect(window.series.scopes.map(\.object) == ["M 31"])
    window.startRun()
    await Self.queueSettled(window)
    #expect(ran.all.count == 3)
    #expect(try project.store.stacks().map(\.object) == ["IC 1848", "M 31", "M 31"])
  }

  @Test(
    "the Studio opens the chosen stack; the choice persists and survives a reopen",
    .scratchDirectory)
  func testStudioAndExportOpenChosenStack() async throws {
    let fixture = try ProjectTests.fixture()
    defer { try? fixture.project.close() }
    let store = fixture.project.store
    let folder = fixture.project.url
    var stacks: [ProjectStack] = []
    for (runID, object) in [("A", "M 31"), ("B", "IC 1848")] {
      let output = folder.appendingPathComponent("stacks/\(runID)")
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      _ = try ProjectTests.writeBundle(in: output, runID: runID)
      stacks.append(
        try store.addStack(
          bundlePath: "stacks/\(runID)", sourceIDs: [], paramsJSON: "{}", object: object,
          scopeJSON: #"{"object":"\#(object)","set_ids":["x"],"lights":36}"#))
    }
    let window = fixture.window
    window.refresh()
    #expect(window.stacks.map(\.id) == stacks.map(\.id))
    #expect(window.selectedStackID == nil)
    await window.openStudio()
    #expect(window.studio?.source.runID == "B", "nothing chosen: the latest")

    window.selectStack(stacks[0].id)
    #expect(window.selectedStackID == stacks[0].id && window.studio == nil)
    await window.openStudio()
    #expect(window.studio?.source.runID == "A" && window.studio?.source.object == "M 31")
    #expect(try store.setting("workspace.stack") == "\(stacks[0].id)")
    let label = window.stackLabel(stacks[0], locale: Locale(identifier: "en"))
    #expect(label.hasPrefix("M 31 · ") && label.hasSuffix(" · 36 lights"))

    let reopened = ProjectWindowModel(
      store: { store }, folder: { folder }, planning: { _ in ImportPlanningStub.empty })
    #expect(reopened.selectedStackID == stacks[0].id)
    reopened.selectStack(999)
    #expect(reopened.selectedStackID == stacks[0].id, "a stack that does not exist is not chosen")
    try store.setSetting("workspace.stack", to: "999")
    let stale = ProjectWindowModel(
      store: { store }, folder: { folder }, planning: { _ in ImportPlanningStub.empty })
    #expect(stale.selectedStackID == nil, "a deleted stack reads as no choice")
  }
  @Test(
    "the Stacking stage lists a checkbox per series; the Studio offers the stack picker",
    .scratchDirectory)
  func testStagesShowSeriesAndPicker() async throws {
    let (project, window, _) = try await Self.twoObjects()
    defer { try? project.close() }
    window.select(.stacking)
    let stacking = AccessibilityAuditTests.entries(ProjectWindowView(model: window))
    #expect(AccessibilityAudit.problems(stacking) == [])
    let series = stacking.map(\.id).filter { $0.hasPrefix("fr.astrostack.stage.stacking.series.") }
    #expect(series.count == 2, "\(stacking.map(\.id))")
    #expect(
      stacking.contains { $0.id == "fr.astrostack.stage.stacking.run" && $0.label.contains("2") })

    window.startRun()
    await Self.queueSettled(window)
    window.select(.studio)
    let studio = AccessibilityAuditTests.entries(ProjectWindowView(model: window))
    #expect(AccessibilityAudit.problems(studio) == [])
    #expect(studio.contains { $0.id == "fr.astrostack.stage.studio.stack" })
  }
}

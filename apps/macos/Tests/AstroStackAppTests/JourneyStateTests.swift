import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// The journey's stage states, derived from what the project holds — never a selection (R2: the
/// app shows where a project stands, the user decides where to go).
@MainActor
@Suite("JourneyState — stage states from the project's facts")
struct JourneyStateTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let name: String
    let facts: ProjectFacts
    let expected: [JourneyStage: StageStatus]
    var testDescription: String { name }
  }

  nonisolated static let rows: [Row] = [
    Row(
      name: "empty project", facts: ProjectFacts(),
      expected: [
        .data: .toDo, .calibration: .unavailable(.needsSources),
        .review: .unavailable(.needsSources), .stacking: .unavailable(.needsSources),
        .studio: .unavailable(.needsStack), .export: .unavailable(.needsStack),
      ]),
    Row(
      name: "sources only", facts: ProjectFacts(summary: ProjectSummary(sources: 2)),
      expected: [
        .data: .done, .calibration: .ready, .review: .ready, .stacking: .ready,
        .studio: .unavailable(.needsStack), .export: .unavailable(.needsStack),
      ]),
    Row(
      name: "plan with missing calibration",
      facts: ProjectFacts(summary: ProjectSummary(sources: 1), calibrationGaps: 3),
      expected: [
        .data: .done, .calibration: .attention(3), .review: .ready, .stacking: .ready,
        .studio: .unavailable(.needsStack), .export: .unavailable(.needsStack),
      ]),
    Row(
      name: "calibration complete",
      facts: ProjectFacts(summary: ProjectSummary(sources: 1), calibrationGaps: 0),
      expected: [
        .data: .done, .calibration: .done, .review: .ready, .stacking: .ready,
        .studio: .unavailable(.needsStack), .export: .unavailable(.needsStack),
      ]),
    Row(
      name: "stack running",
      facts: ProjectFacts(summary: ProjectSummary(sources: 1), stacksRunning: 1),
      expected: [
        .data: .done, .calibration: .ready, .review: .ready, .stacking: .running,
        .studio: .unavailable(.needsStack), .export: .unavailable(.needsStack),
      ]),
    Row(
      name: "stack done",
      facts: ProjectFacts(summary: ProjectSummary(sources: 1, stacks: 1, images: 4)),
      expected: [
        .data: .done, .calibration: .ready, .review: .ready, .stacking: .done, .studio: .ready,
        .export: .ready,
      ]),
    Row(
      name: "Studio history",
      facts: ProjectFacts(
        summary: ProjectSummary(sources: 1, stacks: 1, images: 4, historySteps: 6)),
      expected: [
        .data: .done, .calibration: .ready, .review: .ready, .stacking: .done, .studio: .done,
        .export: .ready,
      ]),
    Row(
      name: "export done",
      facts: ProjectFacts(
        summary: ProjectSummary(sources: 1, stacks: 1, images: 4, historySteps: 6),
        deliverables: 3),
      expected: [
        .data: .done, .calibration: .ready, .review: .ready, .stacking: .done, .studio: .done,
        .export: .done,
      ]),
    Row(
      name: "frames reviewed",
      facts: ProjectFacts(summary: ProjectSummary(sources: 1), framesReviewed: true),
      expected: [
        .data: .done, .calibration: .ready, .review: .done, .stacking: .ready,
        .studio: .unavailable(.needsStack), .export: .unavailable(.needsStack),
      ]),
  ]

  @Test("each project state gives every stage its status", arguments: rows)
  func testDerive(_ row: Row) {
    let derived = JourneyState.derive(from: row.facts)
    #expect(Set(derived.keys) == Set(JourneyStage.allCases), "every stage has a status")
    for stage in JourneyStage.allCases {
      #expect(derived[stage] == row.expected[stage], "\(stage)")
    }
  }

  @Test("deriving the states never changes the selected stage", .scratchDirectory)
  func testNeverSelectsAStage() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let model = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    #expect(model.selection == .data)
    model.select(.review)

    try project.store.addSource(kind: .night, path: "/captures/M31/2026-10-18")
    model.refresh()
    #expect(model.statuses[.data] == .done)
    #expect(model.selection == .review, "a new state never moves the user")

    model.add(ImportRequest(paths: ["/captures/M31/2026-10-19"]))
    #expect(model.selection == .review)
  }
}

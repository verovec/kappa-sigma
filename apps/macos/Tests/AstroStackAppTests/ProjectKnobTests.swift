import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// The Stacking panel's knobs through a run: applied as shown, recorded with the stack, restored
/// when the project reopens (card 0070).
@MainActor
@Suite("Project runs — the knob patch applied, recorded and restored")
struct ProjectKnobTests {
  @Test(
    "the panel's knobs reach the run and are recorded; a reopened project's panel restores them",
    .scratchDirectory)
  func testKnobsRecordedAndRestored() async throws {
    let fixture = try ProjectTests.fixture()
    defer { try? fixture.project.close() }
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    fixture.window.knobs.set("fwhm_sigma", to: .number(3.5))
    fixture.window.knobs.set("register_2pass", to: .flag(true))
    fixture.window.startRun(mode: .nebula)
    await fixture.window.run?.settled()

    let ran = try #require(fixture.ran.all.first)
    #expect(
      ran.mode == .nebula && ran.settings.grading.fwhmSigma == 3.5 && ran.settings.register2Pass)
    #expect(ran.settings.backgroundDegree == 2, "the rest is the nebula preset")
    let stack = try #require(try fixture.project.store.latestStack())
    let record = try JSONDecoder().decode(StackRecord.self, from: Data(stack.paramsJSON.utf8))
    #expect(record.mode == .nebula)
    #expect(
      record.knobs
        == KnobPatch(values: ["fwhm_sigma": .number(3.5), "register_2pass": .flag(true)]))

    let reopened = ProjectWindowModel(
      store: { fixture.project.store }, folder: { fixture.project.url },
      planning: { _ in ImportPlanningStub.empty })
    #expect(reopened.knobs.mode == .nebula && reopened.knobs.patch == record.knobs)
  }

  @Test("a record written before the knobs reads as the deepsky preset, untouched")
  func testRecordWithoutKnobs() throws {
    let record = try JSONDecoder().decode(
      StackRecord.self, from: Data(#"{"path": "/c/M31-DB"}"#.utf8))
    #expect(record == StackRecord(request: ImportRequest(paths: ["/c/M31-DB"])))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(
      String(bytes: try encoder.encode(record), encoding: .utf8)
        == #"{"mode":"deepsky","path":"\/c\/M31-DB"}"#)
  }
}

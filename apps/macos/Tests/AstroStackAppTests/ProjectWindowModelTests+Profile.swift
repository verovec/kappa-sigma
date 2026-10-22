import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

/// The profile the knobs' help words (card 0086): the one every capture night kept — a night
/// without one or a different one words nothing, a legacy run has no say, and a change of
/// nights is looked up again.
@MainActor
@Suite("Project window — the kept profile the knobs' help words")
struct ProjectWindowModelProfileTests {
  static let galaxy = "galaxy-osc-broadband-dualband"
  static let emission = "emission-osc-dualband"

  @Test("every night the same profile → that profile; a legacy run has no say", .scratchDirectory)
  func testAgreedProfile() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let store = project.store
    _ = try store.addSource(kind: .night, path: "/captures/night-1")
    try store.setProfile(Self.galaxy, kind: .night, path: "/captures/night-1")
    _ = try store.addSource(kind: .legacyRun, path: "/runs/78")
    let model = ProjectWindowModel(
      store: { store }, planning: { _ in ImportPlanningStub.empty })
    #expect(model.knobs.profile?.id == Self.galaxy)

    // A second night with the same profile keeps it; one with another, or none, drops it.
    _ = try store.addSource(kind: .night, path: "/captures/night-2")
    try store.setProfile(Self.galaxy, kind: .night, path: "/captures/night-2")
    model.refresh()
    #expect(model.knobs.profile?.id == Self.galaxy)
    try store.setProfile(Self.emission, kind: .night, path: "/captures/night-2")
    model.refresh()
    #expect(model.knobs.profile == nil)
    try store.setProfile(Self.galaxy, kind: .night, path: "/captures/night-2")
    model.refresh()
    #expect(model.knobs.profile?.id == Self.galaxy, "looked up again once the nights agree")
    try store.setProfile(nil, kind: .night, path: "/captures/night-2")
    model.refresh()
    #expect(model.knobs.profile == nil, "a night without a profile counts")
  }

  @Test("an id no profile resolves to words nothing", .scratchDirectory)
  func testUnknownProfile() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    _ = try project.store.addSource(kind: .night, path: "/captures/night-1")
    try project.store.setProfile("gone", kind: .night, path: "/captures/night-1")
    let model = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    #expect(model.knobs.profile == nil)
  }
}

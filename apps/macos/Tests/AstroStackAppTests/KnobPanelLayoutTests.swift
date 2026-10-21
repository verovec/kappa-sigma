import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The Stacking panel's settings as the user meets them: every knob with the disclosure open,
/// moved ones with their reset, and a recorded value this build refuses shown, in fr and en.
@MainActor
@Suite("Knob panel — advanced open, edits badged, refused values shown")
struct KnobPanelLayoutTests {
  @Test(
    "every knob lays out, moved ones and the refused record included", .scratchDirectory,
    arguments: ["en", "fr"])
  func testPanelLaysOut(_ language: String) throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let night = try project.store.addSource(kind: .night, path: "/c/M31-DB")
    try project.store.addStack(
      bundlePath: "stacks/old", sourceIDs: [night.id],
      paramsJSON: #"{"path": "/c/M31-DB", "mode": "nebula", "knobs": {"no_such_knob": 1}}"#)
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      planning: { _ in ImportPlanningStub.empty })
    #expect(window.knobs.mode == .nebula && window.knobs.ignored == ["no_such_knob"])
    window.knobs.showsAdvanced = true
    window.knobs.set("fwhm_sigma", to: .number(3.5))
    window.knobs.set("register_2pass", to: .flag(true))
    window.knobs.set("stack_reject", to: .choice("sigma"))
    window.knobs.set("scnr", to: .number(1))
    window.select(.stacking)

    let host = ImportSheetTests.host(
      ProjectWindowView(model: window).environment(\.locale, Locale(identifier: language))
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 640 && host.fittingSize.height >= 400)
    host.sizingOptions = [.minSize]
    host.layoutSubtreeIfNeeded()
    #expect(window.knobs.changedCount == 4)
    if language == "en" { try RunPanelTests.attach(host, "knob-panel-advanced.png") }
  }
}

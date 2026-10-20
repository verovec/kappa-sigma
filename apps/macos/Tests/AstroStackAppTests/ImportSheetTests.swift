import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The Import sheet and the project window laid out offscreen in every state the plan can put
/// them in: empty, scanning, failed, a plan with a colour light, gaps, an exclusion, warnings.
@MainActor
@Suite("ImportSheet and ProjectWindowView — every state lays out")
struct ImportSheetTests {
  static func host<Content: View>(_ view: Content) -> NSHostingView<Content> {
    let host = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    return host
  }

  @Test("empty, then a full plan with overrides, gaps and an exclusion, then a failure")
  func testSheetStates() async throws {
    let planner = ImportViewModelTests.FakePlanner()
    let model = ImportViewModel(planning: planner.planning)
    var added: [ImportRequest] = []
    let host = Self.host(ImportSheet(model: model, onAdd: { added.append($0) }, onCancel: {}))
    let empty = host.fittingSize

    model.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    await model.settled()
    let plan = try #require(model.plan)
    let rows = plan.nights.flatMap(\.sets)
    model.setFilterSet(.dualband, for: rows[0])
    model.mapFilter("Ha", to: "ignore")
    model.exclude(rows[1])
    let cell = try #require(model.plan?.calibration.first?.cells.last)
    model.setIncluded(false, cell)
    await model.settled()
    host.layoutSubtreeIfNeeded()
    #expect(model.plan?.calibration.first?.hasGap == true, "no dark nor flat in the fake capture")
    #expect(host.fittingSize.height > empty.height, "the plan fills the sheet")

    planner.failure = InspectError.noFolders
    model.rescan()
    await model.settled()
    host.layoutSubtreeIfNeeded()
    #expect(model.error != nil)
    #expect(added.isEmpty)
  }

  @Test("the project window lists its sources once a capture is added", .scratchDirectory)
  func testProjectWindowStates() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("P.astrostack"))
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    let host = Self.host(ProjectWindowView(model: window))
    window.startImport()
    host.layoutSubtreeIfNeeded()
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    host.layoutSubtreeIfNeeded()
    #expect(window.sources.count == 1)
    #expect(host.fittingSize.width >= 640)
  }
}

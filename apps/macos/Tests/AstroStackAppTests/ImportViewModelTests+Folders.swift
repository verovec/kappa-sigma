import AstroStackApp
import Foundation
import StackKit
import Testing

/// Several capture folders chosen in one panel (card 0174): one request, one scan, the folders a
/// chosen one already covers shown as dropped.
extension ImportViewModelTests {
  static func urls(_ paths: [String]) -> [URL] { paths.map { URL(fileURLWithPath: $0) } }

  @Test("choosing two nights scans both in one request and starts over like one folder")
  func testChooseFolders_ScansAllInOneRequest() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    let rows = try #require(model.plan?.nights.first?.sets)
    model.mapFilter("Ha", to: "ignore")
    model.exclude(rows[1])
    model.chooseProfile(.none)
    await model.settled()
    planner.requests = []

    model.choose(folders: Self.urls(["/c/M31-DB", "/c/M31-BB"]))
    await model.settled()
    #expect(planner.requests == [ImportRequest(paths: ["/c/M31-BB", "/c/M31-DB"])])
    #expect(model.request == ImportRequest(paths: ["/c/M31-BB", "/c/M31-DB"]))
    #expect(model.excludedRows.isEmpty)
    #expect(model.profileChoice == .proposed)
    #expect(model.droppedFolders.isEmpty)
  }

  @Test("a folder inside another chosen one is dropped from the request and exposed")
  func testChooseFolders_ReportsDroppedNested() async throws {
    let planner = FakePlanner()
    let model = ImportViewModel(planning: planner.planning)
    model.choose(folders: Self.urls(["/c/M31/n1", "/c/M31"]))
    await model.settled()
    #expect(planner.requests.map(\.paths) == [["/c/M31"]])
    #expect(model.droppedFolders == [.init(path: "/c/M31/n1", ancestor: "/c/M31")])

    // A later choice without overlap clears the dropped list.
    model.choose(folder: URL(fileURLWithPath: "/c/M45"))
    await model.settled()
    #expect(model.droppedFolders.isEmpty)
  }

  @Test("cancelling a new selection's scan puts the last scan's folders back, dropped ones too")
  func testChooseFolders_CancelRestoresDropped() async throws {
    let planner = FakePlanner()
    let model = ImportViewModel(planning: planner.planning)
    model.choose(folders: Self.urls(["/c/M31", "/c/M31/n1"]))
    await model.settled()
    model.choose(folders: Self.urls(["/c/M45", "/c/M45/n2"]))
    #expect(model.droppedFolders == [.init(path: "/c/M45/n2", ancestor: "/c/M45")])
    model.cancelScan()
    #expect(model.request.paths == ["/c/M31"])
    #expect(model.droppedFolders == [.init(path: "/c/M31/n1", ancestor: "/c/M31")])

    // Cancelling the first scan of all leaves nothing chosen.
    let fresh = ImportViewModel(planning: planner.planning)
    fresh.choose(folders: Self.urls(["/c/M31", "/c/M31/n1"]))
    fresh.cancelScan()
    #expect(fresh.request.paths.isEmpty && fresh.droppedFolders.isEmpty)
  }

  @Test("a panel that fails says so apart from the scan, and the next choice clears it")
  func testChooseFolders_PanelFailureShown() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    model.panelFailed(CocoaError(.fileReadNoPermission))
    #expect(model.panelError != nil)
    #expect(model.error == nil, "the scan did not fail")
    #expect(model.request == ImportRequest(paths: ["/c/M31-DB"]))
    #expect(planner.requests.count == 1, "no scan for a selection that never came")

    model.choose(folder: URL(fileURLWithPath: "/c/M45"))
    #expect(model.panelError == nil)
  }

  @Test("a panel failure before anything is chosen keeps the empty sheet and its cancel")
  func testChooseFolders_PanelFailureKeepsEmptyState() {
    let planner = FakePlanner()
    let model = ImportViewModel(planning: planner.planning)
    model.panelFailed(CocoaError(.fileReadNoPermission))
    #expect(ImportSheet.content(of: model) == .empty)
    model.panelFailed(CocoaError(.fileReadNoPermission))
    model.choose(folders: Self.urls(["/c/M31", "/c/M31/n1"]))
    model.cancelScan()
    #expect(model.request.paths.isEmpty && model.droppedFolders.isEmpty)
  }

  @Test("dismissing the panel is no failure")
  func testChooseFolders_PanelCancelSilent() {
    let model = ImportViewModel(planning: FakePlanner().planning)
    model.panelFailed(CocoaError(.userCancelled))
    #expect(model.panelError == nil)
  }

  @Test("an empty selection changes nothing")
  func testChooseFolders_EmptyIsNoOp() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    model.choose(folders: [])
    await model.settled()
    #expect(planner.requests.count == 1, "no second scan")
    #expect(model.request == ImportRequest(paths: ["/c/M31-DB"]))
  }
}

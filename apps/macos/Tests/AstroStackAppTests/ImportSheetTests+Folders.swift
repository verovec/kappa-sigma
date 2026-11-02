import AppKit
import AstroStackApp
import Foundation
import StackKit
import SwiftUI
import Testing

/// The Import sheet with several folders chosen in one panel (card 0174): the header names them,
/// a folder another one covers shows as dropped, every state lays out in each language.
extension ImportSheetTests {
  @Test(
    "the header names no folder, the one folder, or how many",
    arguments: zip(
      [[], ["/c/M31"], ["/c/M31-BB", "/c/M31-DB", "/c/M45"]],
      [
        ImportSheet.Header.none, .folder("/c/M31"),
        .folders(["/c/M31-BB", "/c/M31-DB", "/c/M45"]),
      ]))
  func testHeader_NamesTheChosenFolders(_ paths: [String], _ expected: ImportSheet.Header) {
    #expect(ImportSheet.header(of: paths) == expected)
  }

  @Test("three folders and a dropped one lay out, the badge in the sheet", arguments: ["en", "fr"])
  func testSheetStates_SeveralFolders(_ language: String) async throws {
    let planner = ImportViewModelTests.FakePlanner()
    let model = ImportViewModel(planning: planner.planning)
    let host = Self.host(
      ImportSheet(model: model, onAdd: { _ in }, onCancel: {})
        .environment(\.locale, Locale(identifier: language)))
    model.choose(folders: ImportViewModelTests.urls(["/c/M31-BB", "/c/M31-DB", "/c/M45"]))
    await model.settled()
    host.layoutSubtreeIfNeeded()
    let plain = host.fittingSize

    model.choose(
      folders: ImportViewModelTests.urls(["/c/M31-BB", "/c/M31-DB", "/c/M45", "/c/M45/flats"]))
    await model.settled()
    host.layoutSubtreeIfNeeded()
    #expect(model.droppedFolders.count == 1)
    #expect(host.fittingSize.height > plain.height, "the dropped folder's badge takes a row")
    #expect(host.fittingSize.width == plain.width, "the badge never widens the sheet")
    let oneDropped = host.fittingSize

    // A whole target with its fifteen nights selected: one badge, not fifteen rows.
    let nights = (1...15).map { "/c/M45/n\($0)" }
    model.choose(folders: ImportViewModelTests.urls(["/c/M45", "/c/M31"] + nights))
    await model.settled()
    host.layoutSubtreeIfNeeded()
    #expect(model.droppedFolders.count == 15)
    #expect(host.fittingSize.height == oneDropped.height, "the dropped folders take one row")

    // A dropped path far wider than the sheet: the badge stays short, the sheet as it was.
    let long = "/c/M45/" + String(repeating: "captures/", count: 40)
    model.choose(folders: ImportViewModelTests.urls(["/c/M31-BB", "/c/M31-DB", "/c/M45", long]))
    await model.settled()
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width == plain.width, "a long dropped path never widens the sheet")
  }

  @Test("the folder list of the header lays every folder out")
  func testFolderList_LaysOutEveryFolder() {
    let one = Self.host(ImportFolderList(folders: ["/c/M31"])).fittingSize
    let three = Self.host(ImportFolderList(folders: ["/c/M31-BB", "/c/M31-DB", "/c/M45"]))
      .fittingSize
    #expect(three.height > one.height)
  }

  @Test(
    "a dropped row says why in each language, before its ancestor",
    arguments: zip(["en", "fr"], ["already included in", "déjà inclus dans"]))
  func testDroppedMessage_NamesTheAncestor(_ language: String, _ expected: String) {
    var words = ImportFolderList.includedIn
    words.locale = Locale(identifier: language)
    #expect(String(localized: words) == expected)
  }

  @Test("a short list shows every row; from scrollingLines on it scrolls in a fixed height")
  func testFolderList_BoundedHeight() {
    let rows = ImportFolderList.scrollingLines
    #expect(!ImportFolderList.scrolls(lines: rows - 1) && ImportFolderList.scrolls(lines: rows))
    let folders = (1...120).map { "/c/M31/n\($0)" }
    let short = Self.host(ImportFolderList(folders: Array(folders.prefix(rows - 1)))).fittingSize
    let three = Self.host(ImportFolderList(folders: Array(folders.prefix(3)))).fittingSize
    let season = Self.host(ImportFolderList(folders: folders)).fittingSize
    #expect(short.height > three.height, "no row hidden below the cap")
    #expect(season.height <= ImportFolderList.maxHeight + 40, "the fixed height plus its padding")
    let nested = ImportFolders.Nested(path: "/c/M31/n1", ancestor: "/c/M31")
    let dropped = Self.host(ImportFolderList(dropped: [nested])).fittingSize
    let plain = Self.host(ImportFolderList(folders: ["/c/M31/n1"])).fittingSize
    #expect(dropped.height > plain.height, "the reason sits under the path")
  }

  @Test(
    "dropped rows take two lines: just under the threshold and over it, the list stays bounded",
    arguments: [7, 8, 40])
  func testFolderList_DroppedBounded(_ count: Int) {
    #expect(ImportFolderList.scrollingLines == 16, "7 rows sit under the threshold, 8 reach it")
    let nested = (1...count).map {
      ImportFolders.Nested(path: "/c/M45/n\($0)", ancestor: "/c/M45")
    }
    let list = Self.host(ImportFolderList(dropped: nested)).fittingSize
    #expect(list.height <= ImportFolderList.maxHeight + 40)
  }
}

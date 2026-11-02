import Foundation
import StackKit
import Testing

/// The folders one panel returned, as one import scans them (card 0174): every chosen folder once,
/// a folder inside another chosen one dropped and said so, the order independent of the clicks.
@Suite("ImportRequest.folders — several capture folders in one import")
struct ImportRequestFoldersTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let chosen: [String]
    let paths: [String]
    let dropped: [ImportFolders.Nested]
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(name: "one folder", chosen: ["/c/M31"], paths: ["/c/M31"], dropped: []),
    Case(
      name: "one folder keeps the spelling it was chosen with",
      chosen: ["/c/nights/../M31-DB"], paths: ["/c/nights/../M31-DB"], dropped: []),
    Case(
      name: "siblings kept, sorted by path", chosen: ["/c/M31-DB", "/c/M31-BB", "/c/IC1848"],
      paths: ["/c/IC1848", "/c/M31-BB", "/c/M31-DB"], dropped: []),
    Case(
      name: "exact duplicate removed, trailing slash included",
      chosen: ["/c/M31/", "/c/M31", "/c/nights/../M31"], paths: ["/c/M31"], dropped: []),
    Case(
      name: "nested child dropped and reported with its ancestor",
      chosen: ["/c/M31/2026-10-18", "/c/M31", "/c/M45"], paths: ["/c/M31", "/c/M45"],
      dropped: [.init(path: "/c/M31/2026-10-18", ancestor: "/c/M31")]),
    Case(
      name: "a grandchild names the chosen ancestor, not the dropped child",
      chosen: ["/c/M31/n1/flats", "/c/M31/n1", "/c/M31"], paths: ["/c/M31"],
      dropped: [
        .init(path: "/c/M31/n1", ancestor: "/c/M31"),
        .init(path: "/c/M31/n1/flats", ancestor: "/c/M31"),
      ]),
    Case(
      name: "a nested folder chosen twice is reported once",
      chosen: ["/c/M31/n1", "/c/M31", "/c/M31/n1/"], paths: ["/c/M31"],
      dropped: [.init(path: "/c/M31/n1", ancestor: "/c/M31")]),
    Case(
      name: "a name prefix is not a parent", chosen: ["/c/M31", "/c/M31-DB"],
      paths: ["/c/M31", "/c/M31-DB"], dropped: []),
    Case(
      name: "everything inside the root", chosen: ["/c", "/"], paths: ["/"],
      dropped: [.init(path: "/c", ancestor: "/")]),
    Case(name: "nothing chosen", chosen: [], paths: [], dropped: []),
  ]

  @Test("duplicates removed, nested folders dropped with their ancestor", arguments: cases)
  func testFolders_Normalisation(_ row: Case) {
    let folders = ImportRequest.folders(row.chosen.map { URL(fileURLWithPath: $0) })
    #expect(folders.paths == row.paths)
    #expect(folders.dropped == row.dropped)
  }

  @Test("one folder makes the request a single-folder import always made")
  func testFolders_OneFolderRequestUnchanged() {
    let folders = ImportRequest.folders([URL(fileURLWithPath: "/c/M31")])
    #expect(ImportRequest(paths: folders.paths) == ImportRequest(paths: ["/c/M31"]))
  }
}

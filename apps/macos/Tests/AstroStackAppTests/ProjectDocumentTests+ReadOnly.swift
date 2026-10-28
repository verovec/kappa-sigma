import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

/// Card 0101: the folders the app reads (R7) never receive a project — the same rule, and the
/// same sentence, as an export (`ExportGuard`).
extension ProjectDocumentTests {
  /// One save target under a fake home: its folder, and whether the save is refused.
  nonisolated struct SaveCase: Sendable, CustomTestStringConvertible {
    let folder: String
    let viaLink: Bool
    let refused: Bool
    /// The astro root, relative to the fake home; the default when `nil` (card 0148).
    var astro: String?
    var testDescription: String { "\(viaLink ? "link → " : "")\(folder)" }
  }

  nonisolated static let saveCases = [
    SaveCase(folder: "Documents/astro/captures/IC1848", viaLink: false, refused: true),
    SaveCase(folder: "Documents/astro/runs/IC1848", viaLink: false, refused: true),
    SaveCase(folder: "Documents/astro/library", viaLink: false, refused: true),
    SaveCase(folder: "Documents/astro/fixtures", viaLink: false, refused: true),
    SaveCase(folder: "Documents/Astro/Captures", viaLink: false, refused: true),
    SaveCase(folder: "Documents/astro/captures/IC1848", viaLink: true, refused: true),
    SaveCase(folder: "Documents/astro/projects", viaLink: false, refused: false),
    SaveCase(folder: "AstroStack/Projects", viaLink: false, refused: false),
    SaveCase(
      folder: "Volumes/SSD/astro/captures/M31", viaLink: false, refused: true,
      astro: "Volumes/SSD/astro"),
    SaveCase(
      folder: "Documents/astro/captures/IC1848", viaLink: false, refused: false,
      astro: "Volumes/SSD/astro"),
  ]

  @Test(
    "Save and Save As refuse a folder under captures/runs/library/fixtures, links resolved",
    .scratchDirectory, arguments: saveCases)
  func testRefusesSavingUnderCaptures(_ row: SaveCase) throws {
    let home = try ScratchDirectory.url.appendingPathComponent("home")
    let real = home.appendingPathComponent(row.folder)
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    var folder = real
    if row.viaLink {
      folder = home.appendingPathComponent("Desktop/shortcut")
      try FileManager.default.createDirectory(
        at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: real)
    }
    let target = folder.appendingPathComponent("IC 1848.astrostack")

    for operation in [NSDocument.SaveOperationType.saveOperation, .saveAsOperation] {
      let document = try ProjectDocument(type: Self.type)
      let astro = home.appendingPathComponent(row.astro ?? "Documents/astro")
      document.astro = { astro }
      let untitled = try #require(document.packageURL)
      if row.refused {
        let error = #expect(throws: (any Error).self) {
          try document.writeSafely(to: target, ofType: Self.type, for: operation)
        }
        #expect(error?.localizedDescription.contains("which the app never writes") == true)
        #expect(
          !FileManager.default.fileExists(
            atPath: real.appendingPathComponent(
              target.lastPathComponent
            ).path), "nothing written there")
        #expect(document.packageURL == untitled, "the document stays where it was")
        document.close()
      } else {
        try document.writeSafely(to: target, ofType: Self.type, for: operation)
        #expect(document.packageURL == target)
        document.close()
        try FileManager.default.removeItem(at: target)
      }
    }
  }

  @Test(
    "a project already under captures is refused on open, the document unchanged", .scratchDirectory
  )
  func testRefusesOpeningUnderCaptures() throws {
    let home = try ScratchDirectory.url.appendingPathComponent("home")
    let folder = home.appendingPathComponent("Documents/astro/captures/IC1848")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let stray = folder.appendingPathComponent("test-build.astrostack")
    try ProjectPackage.create(at: stray).close()
    let document = try ProjectDocument(type: Self.type)
    let astro = home.appendingPathComponent("Documents/astro")
    document.astro = { astro }
    let untitled = try #require(document.packageURL)
    defer { document.close() }

    let error = #expect(throws: (any Error).self) {
      try document.read(from: stray, ofType: Self.type)
    }

    #expect(error?.localizedDescription.contains("which the app never writes") == true)
    #expect(document.packageURL == untitled)
  }
}

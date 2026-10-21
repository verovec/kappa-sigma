import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The journey as a user walks it (PO report 2026-10-21): a stage that shows a state shows what
/// it means, and a greyed action says what ungreys it.
@MainActor
@Suite("Journey flow — Calibration shows its masters, an untitled project offers Save")
struct JourneyFlowTests {
  final class Calls {
    var edited = 0
    var saved = 0
  }

  static func window(
    _ project: ProjectPackage, saved: Bool = true, calls: Calls = Calls()
  ) -> ProjectWindowModel {
    ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      services: { _ in ImportServices(planning: { DataScanTests.gapPlan($0) }) },
      isSaved: { saved }, edited: { calls.edited += 1 }, save: { calls.saved += 1 })
  }

  @Test(
    "Add tells the document the project changed, so an untitled one asks before closing",
    .scratchDirectory)
  func testAddMarksEdited() throws {
    let project = try ProjectWorkspaceTests.project()
    defer { try? project.close() }
    let calls = Calls()
    let model = Self.window(project, saved: false, calls: calls)

    model.add(ImportRequest(paths: ["/captures/M31-DB"]))

    #expect(calls.edited == 1)
  }

  @Test("an untitled project needs a save before a run; Save asks the document", .scratchDirectory)
  func testUntitledOffersSave() throws {
    let project = try ProjectWorkspaceTests.project()
    defer { try? project.close() }
    let calls = Calls()
    let untitled = Self.window(project, saved: false, calls: calls)
    untitled.add(ImportRequest(paths: ["/captures/M31-DB"]))
    #expect(untitled.needsSave)

    untitled.save()

    #expect(calls.saved == 1)
    #expect(!Self.window(project).needsSave, "a saved project runs as is")
  }

  @Test(
    "the Import sheet shows only Add's failure, never an error of Run left in the window",
    .scratchDirectory)
  func testImportSheetErrorIsAddsOwn() throws {
    let project = try ProjectWorkspaceTests.project()
    defer { try? project.close() }
    let model = Self.window(project, saved: false)
    model.add(ImportRequest(paths: ["/captures/M31-DB"]))
    model.startRun()
    #expect(model.error == .projectUnsaved)

    model.startImport()

    #expect(model.importError == nil)
    #expect(model.error == .projectUnsaved, "the window keeps its own error")
    model.closeImport()
  }

  @Test("an Add that records nothing leaves an untitled project unchanged")
  func testFailedAddNotEdited() {
    let calls = Calls()
    let model = ProjectWindowModel(
      store: { nil }, isSaved: { false }, edited: { calls.edited += 1 })

    model.add(ImportRequest(paths: ["/captures/M31-DB"]))

    #expect(calls.edited == 0)
    #expect(model.importError == .projectClosed)
  }

  @Test(
    "a titled project is written in place: recording a legacy run leaves nothing to save",
    .scratchDirectory)
  func testTitledProjectNotEdited() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: ProjectPackage.typeIdentifier)
    defer { document.close() }

    try document.importLegacyRun(
      LegacyRunSource(folder: try LegacyRunWindowTests.run(in: ScratchDirectory.url)))

    #expect(!document.isDocumentEdited)
  }

  @Test("the library file a calibration cell applies, nothing for a build or a gap")
  func testLibraryPath() {
    #expect(
      ImportFormat.libraryPath(.library(path: "/l/dark.fits", frames: 5)) == "/l/dark.fits")
    #expect(ImportFormat.libraryPath(.build(frames: 12)) == nil)
    #expect(
      ImportFormat.libraryPath(.excluded(.library(path: "/l/d.fits", frames: 1))) == nil)
    #expect(ImportFormat.libraryPath(.missing) == nil)
  }

  struct Variant: Sendable, CustomTestStringConvertible {
    let scanned: Bool
    let saved: Bool
    let language: String
    var testDescription: String {
      "\(scanned ? "scanned" : "empty")-\(saved ? "saved" : "untitled")-\(language)"
    }
  }

  nonisolated static let variants = [false, true].flatMap { scanned in
    [false, true].flatMap { saved in
      ["en", "fr"].map { Variant(scanned: scanned, saved: saved, language: $0) }
    }
  }

  @Test(
    "Calibration and Stacking lay out, scanned or not, saved or not, in fr and en",
    .scratchDirectory, arguments: variants)
  func testPanesLayOut(_ variant: Variant) async throws {
    let project = try ProjectWorkspaceTests.project()
    defer { try? project.close() }
    let model = Self.window(project, saved: variant.saved)
    model.add(ImportRequest(paths: ["/captures/M31-DB"]))
    if variant.scanned {
      model.rescan()
      await model.scanSettled()
      #expect(model.coverage?.rows.count == 1)
    }
    for stage in [JourneyStage.calibration, .stacking] {
      model.select(stage)
      let host = ImportSheetTests.host(
        ProjectWindowView(model: model)
          .environment(\.locale, Locale(identifier: variant.language)))
      host.layoutSubtreeIfNeeded()
      #expect(host.fittingSize.width >= 640 && host.fittingSize.height >= 400)
      if variant.scanned && !variant.saved {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        Attachment.record(png, named: "\(stage)-\(variant.language).png")
      }
    }
  }
}

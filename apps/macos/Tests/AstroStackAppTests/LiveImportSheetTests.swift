import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The Import sheet over the real M31-DB capture and the real calibration library, as the app
/// plans it, rendered to a PNG attachment (the screenshot of the card's manual check).
@MainActor
@Suite(
  "Live import sheet — M31-DB against the real library", .liveFixtures, .tags(.live),
  .serialized, .timeLimit(.minutes(5)))
struct LiveImportSheetTests {
  @Test(
    "the sheet shows the night, the 36 lights and the masters the run would use",
    .scratchDirectory)
  func testLiveImportSheet_m31db() async throws {
    let capture = ImportPlanning.capturesFolder.appendingPathComponent("M31-DB")
    guard FileManager.default.fileExists(atPath: capture.path) else {
      try Test.cancel("M31-DB absent under ~/Documents/astro/captures")
    }
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("P.astrostack"))
    defer { try? project.close() }
    let paris = try #require(TimeZone(identifier: "Europe/Paris"))
    let model = ImportViewModel(
      planning: ImportPlanning.live(store: project.store, timeZone: paris))
    model.choose(folder: capture)
    await model.settled()

    let plan = try #require(model.plan, "\(model.error ?? "")")
    let lights = plan.nights.flatMap(\.sets).filter { $0.type == .light }
    #expect(lights.map(\.count) == [36])
    let cells = try #require(plan.calibration.first).cells
    #expect(cells.allSatisfy { $0.status != .missing }, "\(cells.map(\.status))")

    let host = NSHostingView(
      rootView: ImportSheet(model: model, onAdd: { _ in }, onCancel: {})
        .background(Color(nsColor: .windowBackgroundColor)))
    // Offscreen there is no window to paint behind the text: pin a light, opaque rendering.
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 1100, height: 1400)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    Attachment.record(png, named: "import-sheet-m31-db.png")
    if let path = ProcessInfo.processInfo.environment["IMPORT_SCREENSHOT"] {
      try png.write(to: URL(fileURLWithPath: path))
    }
  }
}

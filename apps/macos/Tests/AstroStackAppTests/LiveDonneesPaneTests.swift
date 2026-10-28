import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The Données stage over the real M31-DB capture and the real library, rescanned as the user
/// would, rendered to a PNG attachment (card 0078's manual check).
@MainActor
@Suite(
  "Live Données pane — M31-DB integration and coverage", .liveFixtures, .tags(.live), .serialized,
  .timeLimit(.minutes(5)))
struct LiveDonneesPaneTests {
  @Test(
    "the night of 2026-09-22: 36 lights, and its library dark, flat and bias", .scratchDirectory)
  func testLiveDonnees_m31db() async throws {
    let capture = ImportPlanning.capturesFolder.appendingPathComponent("M31-DB")
    guard FileManager.default.fileExists(atPath: capture.path) else {
      try Test.cancel("M31-DB absent under ~/Documents/astro/captures")
    }
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let paris = try #require(TimeZone(identifier: "Europe/Paris"))
    let model = ProjectWindowModel(
      store: { project.store },
      planning: { ImportPlanning.live(store: $0, timeZone: paris) })
    model.add(ImportRequest(paths: [capture.path]))
    model.select(.data)
    model.rescan()
    await model.scanSettled()

    let integration = try #require(model.integration, "\(model.error?.errorDescription ?? "")")
    let night = try #require(integration.rows.first { $0.night == "2026-09-22" })
    #expect(night.frames == 36)
    let row = try #require(model.coverage?.rows.first { $0.night == "2026-09-22" })
    #expect(
      row.cells.allSatisfy {
        if case .library = $0.status { true } else { false }
      }, "\(row.cells.map(\.status))")
    #expect(model.statuses[.calibration] == .done)

    let host = NSHostingView(
      rootView: ProjectWindowView(model: model, projects: .empty)
        .environment(\.locale, Locale(identifier: "fr"))
        .background(Color(nsColor: .windowBackgroundColor)))
    // Offscreen there is no window to paint behind the text: pin a light, opaque rendering.
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    Attachment.record(png, named: "donnees-m31-db.png")
    if let path = ProcessInfo.processInfo.environment["DONNEES_SCREENSHOT"] {
      try png.write(to: URL(fileURLWithPath: path))
    }
  }
}

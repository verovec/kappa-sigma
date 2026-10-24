import AppKit
import AstroStackApp
import Foundation
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Card 0130's manual check, offscreen: the SH2-132 project's object card from the installed
/// Siril's catalogue, rendered in French and English and attached as PNG (the window capture
/// needs a Screen Recording grant the worker's terminal does not have).
@MainActor
@Suite(
  "Live object card — SH2-132 from the installed Siril (fr, en)", .liveFixtures, .tags(.live),
  .enabled(
    if: FileManager.default.isExecutableFile(atPath: SirilTool.path()), "siril-cli absent"),
  .timeLimit(.minutes(1)))
struct LiveObjectCardRenderTests {
  @Test("the SH2-132 project's object card lays out and is attached", arguments: ["fr", "en"])
  func testSh2132Card(language: String) async throws {
    let objects = ObjectSearchModel()
    await objects.load(projectObject: "SH2-132")
    let object = try #require(objects.selected)
    #expect(object.name == "Sh2-132")
    let host = NSHostingView(
      rootView: ObjectCard(object: object) {}.frame(width: 520, height: 360)
        .environment(\.locale, Locale(identifier: language))
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(png.count > 1000)
    Attachment.record(png, named: "object-card-sh2-132-\(language).png")
  }
}

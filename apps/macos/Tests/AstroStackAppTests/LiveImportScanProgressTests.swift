import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The card's manual check, headless: the real planner on the real M31-BB capture. The counter
/// moves while headers are read, the sheet shows it (rendered to a PNG attachment), and Cancel
/// stops the scan at once.
@MainActor
@Suite(
  "Live import scan progress — M31-BB read with a moving counter, then cancelled", .liveFixtures,
  .tags(.live), .serialized, .timeLimit(.minutes(5)))
struct LiveImportScanProgressTests {
  @Test("the counter moves, the sheet shows it, Cancel returns at once", .scratchDirectory)
  func testScanProgressOnM31() async throws {
    let capture = ImportPlanning.capturesFolder.appendingPathComponent("M31-BB")
    guard FileManager.default.fileExists(atPath: capture.path) else {
      try Test.cancel("M31-BB absent under ~/Documents/astro/captures")
    }
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("P.astrostack"))
    defer { try? project.close() }
    let live = ImportPlanning.services(store: project.store).planning
    // The test hears the same steps as the model, to wait for a real count without sleeping.
    let (heard, tell) = AsyncStream.makeStream(of: ScanProgress.self)
    let model = ImportViewModel(planning: { request, progress in
      try await live(request) { step in
        progress(step)
        tell.yield(step)
      }
    })
    model.choose(folder: capture)
    for await step in heard {
      if case .reading(let done, _) = step, done >= 2 * ScanProgress.readingStep { break }
    }
    for _ in 0..<100_000 where !Self.counting(model.progress) { await Task.yield() }
    #expect(Self.counting(model.progress), "\(String(describing: model.progress))")
    #expect(ImportSheet.content(of: model) == .scanning)
    try Self.screenshot(model)

    let start = ContinuousClock.now
    model.cancelScan()
    #expect(!model.isScanning && model.progress == nil && model.request.paths.isEmpty)
    await model.settled()
    #expect(ContinuousClock.now - start < .seconds(5), "the scan stops at the next file")
    tell.finish()
  }

  static func counting(_ progress: ScanProgress?) -> Bool {
    if case .reading(let done, let total) = progress { done > 0 && done < total } else { false }
  }

  static func screenshot(_ model: ImportViewModel) throws {
    let host = NSHostingView(
      rootView: ImportSheet(model: model, onAdd: { _ in }, onCancel: {})
        .environment(\.locale, Locale(identifier: "fr"))
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    Attachment.record(png, named: "import-scan-progress-m31.png")
    if let path = ProcessInfo.processInfo.environment["IMPORT_SCREENSHOT"] {
      try png.write(to: URL(fileURLWithPath: path))
    }
  }
}

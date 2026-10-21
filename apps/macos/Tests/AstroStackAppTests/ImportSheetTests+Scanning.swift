import AppKit
import AstroStackApp
import Foundation
import StackKit
import SwiftUI
import Testing

extension ImportSheetTests {
  static func showsPlan(_ model: ImportViewModel) -> Bool {
    if case .plan = ImportSheet.content(of: model) { true } else { false }
  }

  @Test(
    "a first scan shows its progress, never « No capture »; a rescan keeps the plan in view",
    arguments: [("en", NSAppearance.Name.aqua), ("fr", .darkAqua)])
  func testScanningStates(language: String, appearance: NSAppearance.Name) async throws {
    let first = ImportViewModelTests.SteppedPlanner(steps: ImportViewModelTests.steps)
    let model = ImportViewModel(planning: first.planning)
    let host = Self.host(
      ImportSheet(model: model, onAdd: { _ in }, onCancel: {})
        .environment(\.locale, Locale(identifier: language)))
    host.appearance = NSAppearance(named: appearance)
    #expect(ImportSheet.content(of: model) == .empty)

    model.choose(folder: URL(fileURLWithPath: "/c/M31"))
    #expect(ImportSheet.content(of: model) == .scanning, "not « No capture » before any report")
    await ImportViewModelTests.until { model.progress == .reading(done: 32, total: 70) }
    host.layoutSubtreeIfNeeded()
    #expect(ImportSheet.content(of: model) == .scanning)
    #expect(host.fittingSize.width >= 820)
    first.release()
    await model.settled()
    #expect(Self.showsPlan(model))

    model.rescan()
    host.layoutSubtreeIfNeeded()
    #expect(Self.showsPlan(model) && model.isScanning, "the plan stays")
    model.cancelScan()
    #expect(Self.showsPlan(model) && !model.isScanning)
  }

  @Test(
    "every phase lays out in each language",
    arguments: [
      ScanProgress.library, .reading(done: 1_234, total: 3_480), .reading(done: 0, total: 0),
      .classifying,
    ])
  func testScanProgressView(progress: ScanProgress) {
    for language in ["en", "fr"] {
      for compact in [false, true] {
        let host = Self.host(
          ImportScanProgressView(progress: progress, compact: compact) {}
            .environment(\.locale, Locale(identifier: language)))
        #expect(host.fittingSize.width > 0)
      }
    }
  }
}

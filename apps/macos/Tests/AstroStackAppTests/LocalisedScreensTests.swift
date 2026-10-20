import AppKit
import AstroStackApp
import Foundation
import Metal
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The screens migrated by cards 0073–0074 laid out in each language, in the states no other
/// suite renders: the calibration plan with its master disclosures, a master that cannot be
/// measured, a legacy run layer that failed to load.
@MainActor
@Suite("Localised screens — calibration plan, master errors, legacy run failures in fr and en")
struct LocalisedScreensTests {
  static func host<Content: View>(_ view: Content, _ language: String) -> NSHostingView<some View> {
    ImportSheetTests.host(view.environment(\.locale, Locale(identifier: language)))
  }

  @Test(
    "the calibration plan offers a disclosure per master, in each language",
    arguments: ["en", "fr"])
  func testCalibrationPlanWithMasters(_ language: String) async throws {
    let recorder = MasterInspectViewModelTests.Recorder()
    let (sheet, _) = try await MasterInspectViewModelTests.model(recorder)
    #expect(sheet.masters != nil && sheet.plan?.calibration.first?.cells.first?.master != nil)
    let host = Self.host(ImportSheet(model: sheet, onAdd: { _ in }, onCancel: {}), language)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 820)
  }

  @Test("a master that cannot be measured says why, in each language", arguments: ["en", "fr"])
  func testMasterError(_ language: String) async throws {
    let recorder = MasterInspectViewModelTests.Recorder()
    recorder.inspectFailure = CalibrationError.unreadableMaster("/lib/dark.fits")
    let (_, model) = try await MasterInspectViewModelTests.model(recorder)
    let host = Self.host(MasterInspectView(model: model), language)
    await model.load()
    host.layoutSubtreeIfNeeded()
    #expect(model.error == .calibration(.unreadableMaster("/lib/dark.fits")))
    #expect(model.error?.message.text(language).contains("/lib/dark.fits") == true)
  }

  @Test("a flat master shows its vignetting, signed, in each language", arguments: ["en", "fr"])
  func testFlatVignetting(_ language: String) async throws {
    let recorder = MasterInspectViewModelTests.Recorder()
    recorder.stats = MasterStats(
      type: .flat, width: 10, height: 10, planes: [[Float](repeating: 0.4, count: 100)])
    #expect(recorder.stats.vignettingPct != nil)
    let (_, model) = try await MasterInspectViewModelTests.model(recorder)
    let host = Self.host(MasterInspectView(model: model), language)
    await model.load()
    host.layoutSubtreeIfNeeded()
    #expect(model.inspection?.stats.vignettingPct != nil)
  }

  @Test(
    "a legacy run layer that fails to load shows why above the viewer, in each language",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil), .scratchDirectory,
    arguments: ["en", "fr"])
  func testLegacyRunFailure(_ language: String) async throws {
    let folder = try LegacyRunWindowTests.run(in: ScratchDirectory.url)
    let model = try await LegacyRunModel.open(folder: folder)
    let host = Self.host(LegacyRunView(model: model), language)
    try Data("broken".utf8).write(to: folder.appendingPathComponent("syn_Ha.fits"))
    await #expect(throws: (any Error).self) { try await model.select("Ha") }
    host.layoutSubtreeIfNeeded()
    #expect(model.failure?.text(language).hasPrefix("syn_Ha.fits") == true)
  }
}

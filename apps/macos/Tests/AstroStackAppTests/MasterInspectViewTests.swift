import AppKit
import AstroStackApp
import Foundation
import ImageKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The master disclosure laid out in its states, its text, and the live services' measure of a
/// master written to disk.
@MainActor
@Suite("MasterInspectView, MasterFormat and the live master services")
struct MasterInspectViewTests {
  @Test("the disclosure lays out empty, then with stats, warnings, alternatives and progress")
  func testDisclosureStates() async throws {
    let recorder = MasterInspectViewModelTests.Recorder()
    recorder.stats = MasterStats(
      type: .dark, width: 10, height: 10,
      planes: [[Float](repeating: 0.01, count: 90) + [Float](repeating: 1, count: 10)])
    let (_, model) = try await MasterInspectViewModelTests.model(recorder)
    let host = ImportSheetTests.host(MasterInspectView(model: model))
    let empty = host.fittingSize
    await model.load()
    await model.rebuild()
    recorder.existing = "/lib/dark.fits"
    await model.rebuild()
    #expect(model.pendingReplace != nil)
    host.layoutSubtreeIfNeeded()
    #expect(!model.warnings.isEmpty)
    #expect(host.fittingSize.height > empty.height, "stats, warnings and notes fill it")
  }

  @Test(
    "values, percentages, names and verdicts read as written",
    arguments: zip(
      [
        english.significant(0.0076334, digits: 5), english.percent(-3.333).plain,
        english.percent(59.19).plain,
        MasterFormat.name("/lib/master_FLAT_15000ms_g100o50_b1_0C.fits"),
        MasterFormat.verdict(.chosen).text("en"), MasterFormat.verdict(.otherSensor("")).text("en"),
        MasterFormat.verdict(.otherSensor("1 master from another sensor")).text("en"),
      ],
      [
        "0.0076334", "−3.33 %", "+59.19 %", "master_FLAT_15000ms_g100o50_b1_0C.fits", "applied",
        "another sensor", "1 master from another sensor",
      ]))
  func testFormat(text: String, expected: String) {
    #expect(text == expected)
  }

  @Test(
    "matches and forced verdicts say why",
    arguments: [MasterAlternative.Verdict.matches, .needsForce])
  func testVerdictReasons(verdict: MasterAlternative.Verdict) {
    #expect(MasterFormat.verdict(verdict).text("en").count > 10)
    #expect(MasterFormat.verdict(verdict).text("fr") != MasterFormat.verdict(verdict).text("en"))
  }

  @Test("the live services measure a master on disk, off the main actor", .scratchDirectory)
  func testLiveInspect() async throws {
    let url = try ScratchDirectory.url.appendingPathComponent("master_BIAS_g100o50_b1.fits")
    let end = "END".padding(toLength: 2880, withPad: " ", startingAt: 0)
    let image = AstroImage(
      width: 8, height: 8, planes: [[Float](repeating: 0.0076, count: 64)],
      metadata: ImageMetadata(header: try FITSFile.parse(Data(end.utf8)).header))
    try FITSFile.create(image, keeping: nil, at: url)
    let services = try #require(ImportPlanning.services(store: nil).masters)
    let inspection = try await services.inspect(url.path)
    #expect(inspection.master.type == .bias)
    #expect(inspection.width == 8 && inspection.frames == 0)
    #expect(abs(inspection.stats.median - 0.0076) < 1e-6)
    #expect(inspection.warnings.isEmpty)
  }
}

/// The English values the master disclosure tests read.
private let english = AstroFormat(locale: Locale(identifier: "en_US"))

extension String {
  /// The text with its no-break spaces written as plain spaces.
  fileprivate var plain: String { replacing("\u{a0}", with: " ") }
}

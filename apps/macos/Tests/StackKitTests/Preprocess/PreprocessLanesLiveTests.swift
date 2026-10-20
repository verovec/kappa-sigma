import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// Card 0081's acceptance on real data: M31 broadband (three nights) + dual-band (2026-09-22,
/// marked dual-band by the user's override, as for the PO's run #78). The two kinds stack as two
/// lanes, the dual-band master is registered onto the broadband grid and separated, and the
/// bundle carries the colour base plus `syn_Ha` and `syn_OIII` with their `continuum_k`. The
/// deepsky preset runs as shown, the cross-frame trail mask at k = 3 included.
@Suite(
  "Live preprocess — M31 broadband + dual-band lanes", .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(
    if: BuildConfiguration.optimized,
    "120 frames of 26 MP need an optimized build: just test-heavy"),
  .serialized, .timeLimit(.minutes(60)))
struct PreprocessLanesLiveTests {
  static let dualbandNight = "2026-09-22"

  @Test("two lanes; the bundle: RGB + syn_Ha + syn_OIII with continuum_k", .scratchDirectory)
  func testMixedCaptureLive() async throws {
    let oracle = try LiveInventoryOracleTests.liveCase("m31-bb-db")
    let roots = ["M31-DB", "M31-BB"].flatMap { capture in
      ["lights", "darks", "flats", "bias"].map {
        LiveInventoryOracleTests.captures.appendingPathComponent(capture).appendingPathComponent($0)
          .path
      }
    }
    guard roots.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else {
      try Test.cancel("captures M31-DB/M31-BB absent under ~/Documents/astro/captures")
    }
    let builder = InventoryBuilder(
      timeZone: try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone"))
    let scanned = try builder.scan(paths: roots)
    let night = try #require(
      scanned.sets.first { $0.key.type == .light && $0.key.session == Self.dualbandNight })
    var overrides = InspectOverrides()
    overrides.filterSets[night.key.id] = .dualband
    let inventory = try builder.scan(paths: roots, overrides: overrides)
    let plan = try Preprocessor.plan(inventory)
    #expect(plan.channels["RGB"]?.count == 3 && plan.channels["RGB-dualband"]?.count == 1)

    let root = try ScratchDirectory.url
    let out = root.appendingPathComponent("out/M_31/lanes")
    let request = PreprocessRequest(
      inventory: inventory, output: out, work: root.appendingPathComponent("work/lanes"),
      runID: "lanes")
    #expect(request.settings.trailMaskK == 3)
    let tools = Preprocessor.Tools(runner: .live(binary: try SirilTool.locate()))
    let result = try await Preprocessor(tools: tools).perform(request) { _ in }

    #expect(result.channels.map(\.filter).sorted() == ["RGB", "RGB-dualband"])
    #expect(
      result.channels.allSatisfy { $0.error == nil },
      "\(result.channels.map { "\($0.filter): \($0.error ?? "ok")" }) — \(result.warnings)")
    #expect(result.notes.contains { $0.hasPrefix("mixed filter sets") })
    let bundle = try #require(result.bundle)
    // Canonical filter order: the lines first, the colour base after.
    #expect(bundle.layers.map(\.id) == ["Ha", "OIII", "RGB"])
    #expect(bundle.layers.map(\.role) == [.line, .line, .rgb])
    #expect(bundle.layers.prefix(2).map(\.file) == ["syn_Ha.fits", "syn_OIII.fits"])
    #expect(bundle.layers.prefix(2).allSatisfy { $0.source == "syn" && ($0.continuumK ?? 0) > 0 })
    #expect(bundle.layers[2].continuumK == nil)
    #expect(try BundleWriter.read(from: out) == bundle)
  }
}

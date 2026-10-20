import Foundation
import StackKit
import TestSupport
import Testing

/// Run #78 (`M_31/20261018_191749`), the E12 parity reference, when present.
enum RunSeventyEight {
  static var folder: URL? {
    let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
    let run = (home ?? FileManager.default.homeDirectoryForCurrentUser)
      .appendingPathComponent("Documents/astro/runs/M_31/20261018_191749")
    return FileManager.default.fileExists(atPath: run.appendingPathComponent("run.json").path)
      ? run : nil
  }
}

/// Run #78 opened as the Studio opens it.
@Suite(
  "Live legacy bundle builder", .liveFixtures, .tags(.live), .serialized,
  .enabled(if: RunSeventyEight.folder != nil, "run #78 absent"), .timeLimit(.minutes(5)))
struct LiveLegacyBundleBuilderTests {

  @Test("the bundle built from run #78 has the writer's roles, grid and stats")
  func testBuildsSameBundleAsWriter() throws {
    let folder = try #require(RunSeventyEight.folder)
    let source = try LegacyRunSource(folder: folder)
    #expect(source.layers.map(\.id) == ["RGB", "Ha", "OIII"])
    #expect(source.layers.map(\.role) == [.rgb, .line, .line])
    #expect(source.layers.map(\.frames) == [76, 34, 34])
    #expect(source.layers.map(\.file) == ["rgb_base.fits", "syn_Ha.fits", "syn_OIII.fits"])

    let bundle = try LinearBundle.build(fromLegacyRun: source)
    // The base is the post-crop linear image (coverage crop of the 6248×4176 masters).
    #expect(bundle.grid.width == 5967 && bundle.grid.height == 3763)
    #expect(bundle.colorModel == .osc && bundle.runID == "20261018_191749")
    // The 0048 writer's measurement of the same inputs: one implementation, same numbers.
    let writer = try BundleWriter().measure(
      runID: "20261018_191749", colorModel: .osc,
      layers: source.layers.map {
        BundleWriter.Input(
          filter: $0.id, file: folder.appendingPathComponent($0.file), source: $0.source)
      })
    #expect(bundle == writer)
    for layer in bundle.layers {
      #expect(
        layer.stats.bg > 0 && layer.stats.madn > 0 && layer.stats.sky <= layer.stats.bg + 1e-9)
    }
  }
}

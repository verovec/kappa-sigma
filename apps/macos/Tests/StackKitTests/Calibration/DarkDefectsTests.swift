import Foundation
import StackKit
import TestSupport
import Testing

/// `DarkDefects` is `calib/defects.go`: cases translated from `defects_test.go`, with its
/// deterministic LCG noise ported bit for bit.
@Suite("DarkDefects — hot, cold and unstable pixels of a dark pool")
struct DarkDefectsTests {
  /// The Go fixture's LCG.
  struct LCG {
    var state: UInt64
    mutating func next() -> Double {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Double(state >> 11) / Double(1 << 53)
    }
  }

  /// `count` TOP-DOWN darks: a noisy 0.2 floor, or `pixel(frame, x, y)` where non-negative.
  static func pool(
    _ folder: URL, count: Int, width: Int, height: Int, pixel: (Int, Int, Int) -> Double
  ) throws -> [String] {
    try (0..<count).map { frame in
      var random = LCG(state: UInt64(100 + frame))
      let plane = (0..<width * height).map { index -> Float in
        let floor = 0.2 + (random.next() - 0.5) * 0.02
        let planted = pixel(frame, index % width, index / width)
        return Float(planted >= 0 ? planted : floor)
      }
      return try FloatFITS.write(
        folder.appendingPathComponent("dark\(frame).fits"), width: width, height: height,
        planes: [plane],
        cards: [TestFITS.card("ROWORDER", "'TOP-DOWN'")]
      ).path
    }
  }

  @Test("an always-hot, a dead and a flickering pixel are each flagged", .scratchDirectory)
  func testFindsHotColdAndUnstable() throws {
    let folder = try ScratchDirectory.url
    let paths = try Self.pool(folder, count: 12, width: 32, height: 32) { frame, x, y in
      switch (x, y) {
      case (5, 7): 0.8
      case (11, 3): 0.0
      case (20, 9): frame % 2 == 0 ? 0.4 : 0.0
      default: -1
      }
    }
    let defects = try #require(DarkDefects.scan(paths))
    #expect(defects.width == 32 && defects.topDown)
    let kinds = Dictionary(
      uniqueKeysWithValues: defects.pixels.map { ("\($0.x),\($0.y)", $0.kind) })
    #expect(kinds["5,7"] == "H" && kinds["11,3"] == "C" && kinds["20,9"] == "H")
    #expect(defects.unstable >= 1 && defects.hot >= 1 && defects.cold >= 1)
  }

  @Test("Siril's list flips y for TOP-DOWN frames, keeps it for bottom-up ones")
  func testSirilList() {
    var defects = DarkDefects(width: 64, height: 64, topDown: true)
    defects.pixels = [.init(x: 10, y: 20, kind: "H"), .init(x: 40, y: 50, kind: "C")]
    #expect(defects.sirilList == "P 10 43 H\nP 40 13 C\n")
    defects.topDown = false
    #expect(defects.sirilList == "P 10 20 H\nP 40 50 C\n")
  }

  @Test("under eight frames nothing is scanned; the cap keeps the strongest", .scratchDirectory)
  func testFewFramesAndCap() throws {
    let few = try Self.pool(
      try ScratchDirectory.url.appendingPathComponent("few"), count: 5, width: 16, height: 16
    ) { _, _, _ in -1 }
    #expect(DarkDefects.scan(few) == nil)
    let hot = try Self.pool(
      try ScratchDirectory.url.appendingPathComponent("hot"), count: 10, width: 32, height: 32
    ) { _, x, y in
      y == 15 && (2..<22).contains(x) ? 0.6 + Double(x) * 0.02 : -1
    }
    let capped = try #require(DarkDefects.scan(hot))
    #expect(capped.truncated && capped.pixels.count <= 5 && capped.pixels.allSatisfy { $0.x >= 17 })
  }

  @Test(
    "the sidecar is written beside the master, and removed when the pool shrinks", .scratchDirectory
  )
  func testBuild() throws {
    let folder = try ScratchDirectory.url
    let paths = try Self.pool(
      folder.appendingPathComponent("pool"), count: 12, width: 24, height: 24
    ) { _, x, y in
      x == 4 && y == 5 ? 0.9 : -1
    }
    let master = folder.appendingPathComponent("master_DARK_25000ms_g200o30_b1_-15C.fits").path
    #expect(DarkDefects.build(master: master, frames: paths)?.hasPrefix("dark defect map:") == true)
    let list = DarkDefects.listPath(of: master)
    #expect(
      list == folder.appendingPathComponent("master_DARK_25000ms_g200o30_b1_-15C_defects.lst").path)
    #expect(FileManager.default.fileExists(atPath: list))
    #expect(DarkDefects.build(master: master, frames: Array(paths.prefix(5))) == nil)
    #expect(!FileManager.default.fileExists(atPath: list))
  }

  @Test(
    "the separable 5-median equals the sort of each clamped window",
    arguments: [(7, 5), (1, 9), (12, 3)])
  func testMedianFilterMatchesSortedWindows(width: Int, height: Int) {
    var random = LCG(state: 7)
    let values = (0..<width * height).map { _ in Float(random.next()) }
    func reference(_ source: [Float], lines: Int, length: Int, index: (Int, Int) -> Int) -> [Float]
    {
      var out = source
      for line in 0..<lines {
        for position in 0..<length {
          let window = (max(0, position - 2)...min(length - 1, position + 2))
            .map { source[index(line, $0)] }.sorted()
          out[index(line, position)] = window[window.count / 2]
        }
      }
      return out
    }
    let rows = reference(values, lines: height, length: width) { $0 * width + $1 }
    let expected = reference(rows, lines: width, length: height) { $1 * width + $0 }
    #expect(DarkDefects.medianFilter5(values, width: width, height: height) == expected)
  }
}

import CryptoKit
import Foundation
import Metal
import ProcessKit
import TestSupport
import Testing

/// The recording: the GPU it was made on and one digest per case.
struct LineKernelRecording: Codable, Equatable {
  static let fixture = "kernels/line-kernels.sha256.json"

  var gpu: String
  var digests: [String: String]

  static var isRecording: Bool { ProcessInfo.processInfo.environment["RECORD"] == "1" }

  /// The committed recording, if the bundle has one.
  static var recorded: Self? {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(fixture)", withExtension: nil),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }

  /// Whether this Mac's GPU made the recording (or is making it).
  static var onRecordedGPU: Bool {
    guard let device = MTLCreateSystemDefaultDevice() else { return false }
    return isRecording || recorded?.gpu == device.name
  }
}

/// The line kernels (injection, screens) give the bits they gave before the N-line rewrite (card
/// 0136): sha256 of every Float32 output on the oracle inputs, recorded on the unrolled kernels
/// with the GPU's name. Bit-exact only holds on that GPU, so another one skips; CI keeps the
/// oracle tolerances. `RECORD=1` re-records.
@Suite(
  "Live kernel transition — line kernels bit-identical to the recorded unrolled ones",
  .liveFixtures, .tags(.live),
  .enabled(if: LineKernelRecording.onRecordedGPU, "the recording was made on another GPU"),
  .timeLimit(.minutes(1)))
struct LiveKernelTransitionTests {
  /// One render: its name and output planes.
  typealias Render = (name: String, planes: [[Float]])

  /// Every injection oracle row, the zero-gain copy, and the lines compaction reorders.
  static func injectionRenders() throws -> [Render] {
    var zeroBase = LineInjectionProcessTests.planes["RGB"] ?? []
    zeroBase[0][0] = -0.0
    var renders = try LineInjectionProcessTests.oracleCases.map { row in
      (
        "injection · \(row.name)",
        try LineInjectionProcessTests.render(row.values, masked: row.masked)
      )
    }
    let extra: [(String, [String: Double])] = [
      ("three lines", ["haGain": 1, "haContinuumK": 0.5, "oiiiGain": 2, "siiGain": 3]),
      ("SII alone", ["siiGain": 2, "siiGreen": 0.5]),
      ("Hα and SII", ["haGain": 1, "siiGain": 2, "oiiiBlack": 0.1]),
    ]
    renders += try extra.map { ("injection · \($0.0)", try LineInjectionProcessTests.render($0.1)) }
    renders.append(
      ("injection · zero gains", try LineInjectionProcessTests.render([:], base: zeroBase)))
    return renders
  }

  /// Every screen formula row, the boost, and several lines at once.
  static func screenRenders() throws -> [Render] {
    let line = ScreensTests.lineRamp()
    let stats = LayerStats(channels: [ScreensTests.haStats])
    let layers = ["Ha": [line], "OIII": [line.map { $0 * 0.8 }], "SII": [line.reversed()]]
    let layerStats = ["Ha": stats, "OIII": stats, "SII": stats]
    func render(_ values: [String: ParamValue], base: Float) throws -> [[Float]] {
      try ScreensTests.render(
        ScreensTests.params(values), base: Array(repeating: base, count: line.count),
        layers: layers, layerStats: layerStats)
    }
    var renders = try ScreensTests.formulaRows.map { alpha, tint, base in
      (
        "screens · \(alpha) \(tint) \(base)",
        try render(
          [
            "haOpacity": .number(alpha), "haTint": .choice(tint), "haBlack": .number(0.115),
          ], base: Float(base))
      )
    }
    let extra: [(String, [String: ParamValue])] = [
      (
        "boost",
        [
          "haEnabled": .flag(false), "oiiiEnabled": .flag(true), "oiiiBoost": .number(1.25),
          "oiiiOpacity": .number(1),
        ]
      ),
      (
        "three lines",
        ["oiiiEnabled": .flag(true), "siiEnabled": .flag(true), "siiOpacity": .number(0.6)]
      ),
      ("OIII alone", ["haEnabled": .flag(false), "oiiiEnabled": .flag(true)]),
      ("SII alone", ["haEnabled": .flag(false), "siiEnabled": .flag(true)]),
    ]
    renders += try extra.map { ("screens · \($0.0)", try render($0.1, base: 0.2)) }
    return renders
  }

  /// sha256 of the planes' bit patterns, little-endian, plane after plane.
  static func digest(_ planes: [[Float]]) -> String {
    var hash = SHA256()
    for plane in planes {
      let bytes = plane.flatMap { value in
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
      }
      hash.update(data: Data(bytes))
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }

  @Test("the line kernels' outputs equal the recording bit for bit on its GPU")
  func testOldAndNewKernelsAreBitIdentical() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renders = try Self.injectionRenders() + Self.screenRenders()
    let current = LineKernelRecording(
      gpu: device.name,
      digests: Dictionary(uniqueKeysWithValues: renders.map { ($0.name, Self.digest($0.planes)) }))
    if LineKernelRecording.isRecording {
      let root = URL(fileURLWithPath: try ModuleBoundary.packageRoot(from: #filePath))
      let file = root.appendingPathComponent(
        "Tests/ProcessKitTests/Fixtures/\(LineKernelRecording.fixture)")
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try (encoder.encode(current) + Data("\n".utf8)).write(to: file)
      #expect(
        try JSONDecoder().decode(LineKernelRecording.self, from: Data(contentsOf: file)) == current)
      return
    }
    let recorded = try #require(LineKernelRecording.recorded)
    #expect(Set(recorded.digests.keys) == Set(current.digests.keys))
    for (name, digest) in recorded.digests.sorted(by: { $0.key < $1.key }) {
      #expect(current.digests[name] == digest, "\(name)")
    }
  }
}

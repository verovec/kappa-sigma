import Metal
import ProcessKit
import StackKit
import Testing

/// Card 0141: Hβ and [NII] inject like the three first lines — the kernel against the CPU
/// oracle on a bundle of the five line layers.
extension LineInjectionProcessTests {
  /// The bundle plus an Hβ and an [NII] layer.
  static let fiveLinePlanes = planes.merging([
    "Hb": [plane(seed: 24, in: 0...0.25)],
    "NII": [plane(seed: 25, in: 0...0.15)],
  ]) { $1 }

  /// The continuum reference of each line with a k (Hβ against blue, card 0141).
  static let fiveLineReferences = references.merging(["Hb": "RGB.b", "NII": "RGB.r"]) { $1 }

  /// The bundle statistics plus the Hβ and [NII] fits, each with its reference plane.
  static let fiveLineStats = layerStats.merging([
    "Hb": LayerStats(
      channels: [ChannelStats(median: 0.03, madn: 0.002, minimum: 0, maximum: 0.25)],
      continuumK: 0.3, continuumReference: "RGB.b"),
    "NII": LayerStats(
      channels: [ChannelStats(median: 0.02, madn: 0.002, minimum: 0, maximum: 0.15)],
      continuumK: 0.5, continuumReference: "RGB.r"),
  ]) { $1 }

  static let newLineCases = [
    Case(name: "Hβ only", values: ["hbGain": 1.5]),
    Case(name: "[NII] into red", values: ["niiGain": 2, "niiContinuumK": 0.5]),
    Case(
      name: "five lines active",
      values: [
        "haGain": 1, "oiiiGain": 1.5, "siiGain": 2, "hbGain": 1, "hbContinuumK": 0.3,
        "niiGain": 3, "niiBlack": 0.02,
      ]),
  ]

  @Test("Hβ and [NII]: the kernel equals the CPU oracle (max |Δ| ≤ 1e-6)", arguments: newLineCases)
  func testNewLinesMatchCPUOracle(row: Case) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let base = Self.planes["RGB"] ?? []
    let params = try Self.params(row.values)
    let lines = try LineInjectionOracle.lines(
      params: params, planes: Self.fiveLinePlanes, references: Self.fiveLineReferences)
    let expected = LineInjectionOracle.inject(base, lines: lines)
    var layers: [String: GPUImage] = [:]
    for (id, planes) in Self.fiveLinePlanes {
      layers[id] = try GPUImage(
        device: device, width: Self.width, height: Self.height, planes: planes)
    }
    let out = try ProcessRunner(device: device).run(
      LineInjectionProcess(params: params, device: device),
      input: try GPUImage(device: device, width: Self.width, height: Self.height, planes: base),
      stats: LayerStats(channels: []), layers: layers, layerStats: Self.fiveLineStats, mask: nil
    ).read()
    let deltas = zip(out.joined(), expected.joined()).map { abs(Double($0) - Double($1)) }
    #expect(deltas.count == 3 * Self.width * Self.height)
    #expect(deltas.max() ?? .infinity <= 1e-6)
    #expect(out != base, "the case injects something")
  }

  @Test("Hβ goes into blue, [NII] into red: their default shares")
  func testNewLineShares() throws {
    let params = ParamSet(schema: LineInjectionProcess.schema)
    #expect(["Red", "Green", "Blue"].map { params.number("hb" + $0) } == [0, 0, 1])
    #expect(["Red", "Green", "Blue"].map { params.number("nii" + $0) } == [1, 0, 0])
  }
}

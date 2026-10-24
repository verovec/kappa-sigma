import Metal
import ProcessKit
import Testing

extension LineInjectionProcessTests {
  @Test("a NaN line pixel adds nothing there (fmax), as the oracle says; its neighbours inject")
  func testNaNLinePixelAddsNothing() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var planes = Self.planes
    planes["Ha"]?[0][5] = .nan
    var layers = try Self.layers(device: device)
    layers["Ha"] = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: planes["Ha"] ?? [])
    let base = planes["RGB"] ?? []
    let input = try GPUImage(device: device, width: Self.width, height: Self.height, planes: base)
    let out = try ProcessRunner(device: device).run(
      LineInjectionProcess(params: Self.params(["haGain": 2]), device: device), input: input,
      stats: LayerStats(channels: []), layers: layers, layerStats: Self.layerStats
    ).read()
    let lines = try LineInjectionOracle.lines(
      params: Self.params(["haGain": 2]), planes: planes, references: Self.references)
    let expected = LineInjectionOracle.inject(base, lines: lines)
    #expect(out[0][5] == base[0][5])
    #expect(zip(out.joined(), expected.joined()).allSatisfy { abs($0 - $1) <= 1e-6 })
    #expect(out[0][6] != base[0][6])
  }

  @Test("at k = 0 no reference is read: an infinite line pixel injects infinity, not nothing")
  func testInfiniteLinePixelAtZeroK() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var layers = try Self.layers(device: device)
    var ha = Self.planes["Ha"] ?? []
    ha[0][3] = .infinity
    layers["Ha"] = try GPUImage(device: device, width: Self.width, height: Self.height, planes: ha)
    let input = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: Self.planes["RGB"] ?? [])
    let out = try ProcessRunner(device: device).run(
      LineInjectionProcess(params: Self.params(["haGain": 1]), device: device), input: input,
      stats: LayerStats(channels: []), layers: layers, layerStats: Self.layerStats
    ).read()
    #expect(out[0][3] == .infinity)
  }

  @Test("where a line adds nothing the base keeps its bits, −0.0 included")
  func testNoExcessKeepsBits() throws {
    var base = Self.planes["RGB"] ?? []
    let ha = Self.planes["Ha"]?[0] ?? []
    let index = try #require(ha.indices.first { ha[$0] < 0.15 })
    base[0][index] = -0.0
    let out = try Self.render(["haGain": 1, "haBlack": 0.15], base: base)
    #expect(out[0][index].bitPattern == (-0.0 as Float).bitPattern)
  }
}

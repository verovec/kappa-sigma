import Metal
import ProcessKit
import Testing

@Suite(
  "ChannelCombination: slots ← layers with weight and black, palettes as slot templates",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct CombinationTests {
  static let size = (width: 4, height: 2)

  /// Bundle layers with distinct, recognisable values per plane and pixel.
  static func layers(device: MTLDevice, ids: [String]) throws -> [String: GPUImage] {
    var layers: [String: GPUImage] = [:]
    for (index, id) in ids.enumerated() {
      let planes = id == "RGB" ? 3 : 1
      let values: [[Float]] = (0..<planes).map { plane in
        (0..<8).map { Float(index * 100 + plane * 10 + $0) / 1000 }
      }
      layers[id] = try GPUImage(device: device, width: 4, height: 2, planes: values)
    }
    return layers
  }

  static func render(
    _ params: ParamSet, layers: [String: GPUImage], device: MTLDevice
  ) throws -> [[Float]] {
    let process = try ChannelCombinationProcess(params: params, device: device)
    // The node builds its image from the layers: its input only sets the size.
    let base = try GPUImage(device: device, width: 4, height: 2, channels: 3)
    return try ProcessRunner(device: device).run(
      process, input: base, stats: LayerStats(channels: []), layers: layers
    ).read()
  }

  @Test(
    "each slot is w·max(x − black, 0); weight 1 / black 0 is a plain copy",
    arguments: [(1.0, 0.0), (2.0, 0.0), (1.0, 0.003), (0.5, 0.25)])
  func testSlotWeightsAndBlack(weight: Double, black: Double) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let layers = try Self.layers(device: device, ids: ["RGB", "Ha", "OIII"])
    var params = try Palette.hoo.params()
    for slot in ["r", "g", "b"] {
      try params.set("\(slot)Weight", .number(weight))
      try params.set("\(slot)Black", .number(black))
    }
    let out = try Self.render(params, layers: layers, device: device)
    let ha = layers["Ha"]?.read()[0] ?? []
    let oiii = layers["OIII"]?.read()[0] ?? []
    let expected = [ha, oiii, oiii].map { plane in
      plane.map { Float(weight) * max($0 - Float(black), 0) }
    }
    #expect(out == expected)
  }

  @Test(
    "palettes map layers to the documented slots",
    arguments: [
      (Palette.natural, ["RGB.r", "RGB.g", "RGB.b"]), (.hoo, ["Ha", "OIII", "OIII"]),
      (.sho, ["SII", "Ha", "OIII"]), (.hos, ["Ha", "OIII", "SII"]),
      (.foraxx, ["Ha", "Ha*OIII", "OIII"]), (.lrgb, ["R", "G", "B"]),
    ])
  func testPaletteSlots(palette: Palette, sources: [String]) throws {
    let params = try palette.params()
    #expect(["r", "g", "b"].map { params.choice("\($0)Source") } == sources)
    #expect(params.choice("lSource") == (palette == .lrgb ? "L" : "none"))
  }

  @Test("Foraxx green is √(Hα·OIII); natural copies the OSC base planes")
  func testDerivedSources() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let layers = try Self.layers(device: device, ids: ["RGB", "Ha", "OIII"])
    let foraxx = try Self.render(try Palette.foraxx.params(), layers: layers, device: device)
    let ha = layers["Ha"]?.read()[0] ?? []
    let oiii = layers["OIII"]?.read()[0] ?? []
    let mean = zip(ha, oiii).map { ($0 * $1).squareRoot() }
    #expect(zip(foraxx[1], mean).allSatisfy { abs($0 - $1) <= 1.0 / 65535 })
    let natural = try Self.render(try Palette.natural.params(), layers: layers, device: device)
    #expect(natural == layers["RGB"]?.read())
  }

  @Test("L replaces the luminance at its opacity: 0 keeps RGB, 1 gives the L layer's luma")
  func testLuminanceSlot() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let layers = try Self.layers(device: device, ids: ["R", "G", "B", "L"])
    var params = try Palette.lrgb.params()
    try params.set("lOpacity", .number(0))
    let plain = try Self.render(params, layers: layers, device: device)
    #expect(plain == ["R", "G", "B"].map { layers[$0]?.read()[0] ?? [] })
    try params.set("lOpacity", .number(1))
    let full = try Self.render(params, layers: layers, device: device)
    let luminance = layers["L"]?.read()[0] ?? []
    for pixel in 0..<8 {
      let luma = 0.2126 * full[0][pixel] + 0.7152 * full[1][pixel] + 0.0722 * full[2][pixel]
      #expect(abs(luma - luminance[pixel]) <= 1.0 / 65535)
    }
  }

  @Test(
    "a palette missing a layer is unavailable with the reason; rendering refuses, no fallback",
    arguments: [
      (Palette.hoo, Set(["RGB", "Ha"]), "HOO needs an OIII layer"),
      (.sho, Set(["Ha", "OIII"]), "SHO needs an SII layer"),
      (.lrgb, Set(["R", "G", "B"]), "LRGB needs an L layer"),
      (.natural, Set(["Ha"]), "Natural needs an RGB layer"),
    ] as [(Palette, Set<String>, String)])
  func testMissingLayerIsExplicit(palette: Palette, present: Set<String>, reason: String) throws {
    let params = try palette.params()
    #expect(ChannelCombinationProcess.unavailableReason(params: params, present: present) == reason)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let layers = try Self.layers(device: device, ids: Array(present))
    #expect(throws: ProcessError.missingLayer(String(reason.split(separator: " ")[3]))) {
      _ = try Self.render(params, layers: layers, device: device)
    }
  }
}

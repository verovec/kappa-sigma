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

  @Test("a palette replaces the sources only: weights, blacks and L opacity are kept")
  func testPaletteKeepsTuning() throws {
    var params = try Palette.hoo.params()
    try params.set("rWeight", .number(1.8))
    try params.set("gBlack", .number(0.02))
    try params.set("lOpacity", .number(0.4))
    let switched = try Palette.sho.apply(to: params)
    #expect(switched.number("rWeight") == 1.8 && switched.number("gBlack") == 0.02)
    #expect(switched.number("lOpacity") == 0.4)
    #expect(switched.choice("rSource") == "SII")
    #expect(Palette.matching(switched) == .sho)
    var edited = switched
    try edited.set("rSource", .choice("Ha"))
    #expect(Palette.matching(edited) == nil)
    #expect(
      ChannelCombinationProcess.unavailableReason(params: edited, present: ["OIII"])
        == "This combination needs the Ha layer")
  }

  @Test("a mono working image still gets an RGB result; a layer of another size is refused")
  func testOutputAndLayerSizes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let layers = try Self.layers(device: device, ids: ["R", "G", "B", "L"])
    let process = try ChannelCombinationProcess(params: Palette.lrgb.params(), device: device)
    let mono = try GPUImage(device: device, width: 4, height: 2, channels: 1)
    let out = try ProcessRunner(device: device).run(
      process, input: mono, stats: LayerStats(channels: []), layers: layers)
    #expect(out.planes.count == 3)
    var wrong = layers
    wrong["G"] = try GPUImage(device: device, width: 2, height: 1, channels: 1)
    #expect(throws: ProcessError.sizeMismatch) {
      _ = try ProcessRunner(device: device).run(
        process, input: mono, stats: LayerStats(channels: []), layers: wrong)
    }
  }

  @Test(
    "a palette missing a layer is unavailable with the reason; rendering refuses, no fallback",
    arguments: [
      (Palette.hoo, Set(["RGB", "Ha"]), "HOO needs the OIII layer"),
      (.sho, Set(["Ha", "OIII"]), "SHO needs the SII layer"),
      (.lrgb, Set(["R", "G", "B"]), "LRGB needs the L layer"),
      (.natural, Set(["Ha"]), "Natural needs the RGB layer"),
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

  /// The combination a bundle opens on (card 0138): the palette its layers spell, else a grey
  /// of its first layer — an OSC bundle gets exactly the schema's defaults.
  struct Initial: CustomTestStringConvertible, Sendable {
    let name: String
    let layers: [String: Int]
    let sources: [String]
    var testDescription: String { name }
  }

  static let initials: [Initial] = [
    Initial(
      name: "OSC → natural", layers: ["RGB": 3], sources: ["RGB.r", "RGB.g", "RGB.b", "none"]),
    Initial(
      name: "OSC + Hα + OIII → natural", layers: ["RGB": 3, "Ha": 1, "OIII": 1],
      sources: ["RGB.r", "RGB.g", "RGB.b", "none"]),
    Initial(
      name: "LRGB → lrgb", layers: ["L": 1, "R": 1, "G": 1, "B": 1], sources: ["R", "G", "B", "L"]),
    Initial(
      name: "RGB → rgb, no luminance", layers: ["R": 1, "G": 1, "B": 1],
      sources: ["R", "G", "B", "none"]),
    Initial(
      name: "SHO → sho", layers: ["SII": 1, "Ha": 1, "OIII": 1],
      sources: ["SII", "Ha", "OIII", "none"]),
    Initial(
      name: "HOO → hoo", layers: ["Ha": 1, "OIII": 1], sources: ["Ha", "OIII", "OIII", "none"]),
    Initial(
      name: "a 3-plane Hα spells no palette: grey of its planes", layers: ["Ha": 3, "OIII": 1],
      sources: ["Ha.r", "Ha.g", "Ha.b", "none"]),
    Initial(
      name: "L + SII → grey of the base, L", layers: ["L": 1, "SII": 1],
      sources: ["L", "L", "L", "none"]),
    Initial(
      name: "a colour-shaped custom layer alone → grey of its planes", layers: ["Ha 7nm": 3],
      sources: ["Ha 7nm.r", "Ha 7nm.g", "Ha 7nm.b", "none"]),
    Initial(name: "Hα → grey Hα", layers: ["Ha": 1], sources: ["Ha", "Ha", "Ha", "none"]),
  ]

  @Test("testInitialParams", arguments: initials)
  func testInitialParams(row: Initial) throws {
    let params = try ChannelCombinationProcess.initialParams(planes: row.layers)
    #expect(ChannelCombinationProcess.slotSources.map { params.choice($0) } == row.sources)
  }

  @Test("testInitialParams_OSC_isTheSchemaDefault: step 0 of an OSC stack keeps its bytes")
  func testInitialParams_OSC_isTheSchemaDefault() throws {
    let osc = try ChannelCombinationProcess.initialParams(planes: ["RGB": 3, "Ha": 1, "OIII": 1])
    #expect(osc == ParamSet(schema: ChannelCombinationProcess.schema))
  }

  @Test("a plane token of any 3-plane layer reads that plane, as `RGB.g` does (card 0138)")
  func testPlaneTokenOfAnyColourLayer() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var layers = try Self.layers(device: device, ids: ["RGB"])
    layers["Ha 7nm"] = layers["RGB"]
    var params = ParamSet(schema: ChannelCombinationProcess.schema)
    for (slot, plane) in zip(["rSource", "gSource", "bSource"], LayerPlane.planeNames) {
      try params.set(slot, .choice("Ha 7nm.\(plane)"))
    }
    let custom = try Self.render(params, layers: layers, device: device)
    let natural = try Self.render(
      ParamSet(schema: ChannelCombinationProcess.schema), layers: layers, device: device)
    #expect(custom == natural)
  }

  /// The palettes a bundle offers (card 0139): every source token among the bundle's (a plane
  /// needs a colour layer, a product two 1-plane lines), in catalogue order.
  struct Available: CustomTestStringConvertible, Sendable {
    let name: String
    let planes: [String: Int]
    let expected: [Palette]
    var testDescription: String { name }
  }

  static let availables: [Available] = [
    Available(name: "OSC", planes: ["RGB": 3], expected: [.natural]),
    Available(
      name: "OSC + Hα + OIII", planes: ["RGB": 3, "Ha": 1, "OIII": 1],
      expected: [.natural, .hoo, .foraxx]),
    Available(name: "LRGB", planes: ["L": 1, "R": 1, "G": 1, "B": 1], expected: [.lrgb, .rgb]),
    Available(name: "RGB", planes: ["R": 1, "G": 1, "B": 1], expected: [.rgb]),
    Available(
      name: "SHO", planes: ["SII": 1, "Ha": 1, "OIII": 1], expected: [.hoo, .sho, .hos, .foraxx]),
    Available(name: "L + Hα", planes: ["L": 1, "Ha": 1], expected: []),
    Available(
      name: "a 3-plane Hα + OIII: a palette reads whole lines", planes: ["Ha": 3, "OIII": 1],
      expected: []),
  ]

  @Test("testPaletteAvailable", arguments: availables)
  func testPaletteAvailable(row: Available) {
    #expect(Palette.available(planes: row.planes) == row.expected)
  }

  @Test("a palette's layers are the ids its sources read, once each")
  func testPaletteLayers() {
    #expect(Palette.natural.layers == ["RGB"])
    #expect(Palette.foraxx.layers == ["Ha", "OIII"])
    #expect(Palette.lrgb.layers == ["R", "G", "B", "L"])
  }
}

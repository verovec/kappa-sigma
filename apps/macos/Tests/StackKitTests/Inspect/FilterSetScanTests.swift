import FilterKit
import StackKit
import Testing

/// Translated from `internal/inspect/filtersetscan_test.go`: per-set verdicts over real pixels,
/// the bias pedestal, overrides, normalized pixels, the durable map and the night verdict.
@Suite("FilterSetClassifier.annotate — per light set, above the scan's bias pedestal")
struct FilterSetScanTests {
  static let biasADU = 500.0

  struct Missing: Error {}

  static func mosaic(_ r: Double, _ g: Double, _ b: Double, size: Int = 8) -> PixelPlanes {
    var pixels = [Float](repeating: 0, count: size * size)
    for y in 0..<size {
      for x in 0..<size {
        let value = y % 2 == 0 && x % 2 == 0 ? r : y % 2 == 1 && x % 2 == 1 ? b : g
        pixels[y * size + x] = Float(value)
      }
    }
    return PixelPlanes(width: size, height: size, planes: [pixels])
  }

  static func starfield(
    sky: (Double, Double, Double), starFraction: Double, starADU: Double
  ) -> PixelPlanes {
    let size = 64
    var image = mosaic(sky.0, sky.1, sky.2, size: size)
    let every = Int(1 / starFraction)
    for y in 0..<size {
      for x in 0..<size where ((y / 2) * (size / 2) + x / 2) % every == 0 {
        image.planes[0][y * size + x] += Float(starADU)
      }
    }
    return image
  }

  static func reader(_ images: [String: PixelPlanes]) -> PixelReader {
    PixelReader(
      planes: { path in
        guard let image = images[path] else { throw Missing() }
        return image
      },
      centerSample: { _, _ in throw Missing() })
  }

  static func osc(_ path: String, _ type: FrameType, exposureMs: Int) -> CaptureFrame {
    var frame = CaptureFrame(path: path)
    frame.type = type
    frame.bayer = "RGGB"
    frame.filter = Filter.color
    frame.exposureMs = exposureMs
    frame.gain = 100
    frame.offset = 50
    frame.binX = 1
    frame.binY = 1
    frame.eGain = 1
    return frame
  }

  static func inventory(_ frames: [CaptureFrame]) -> Inventory {
    var inventory = Inventory(root: "", frames: frames)
    inventory.colorModel = inventory.lightColorModel
    inventory.regroup()
    return inventory
  }

  static func id(_ inventory: Inventory, _ type: FrameType, _ exposureMs: Int) -> String {
    inventory.sets.first { $0.key.type == type && $0.key.exposureMs == exposureMs }?.key.id ?? "-"
  }

  static let dualAndBias = reader([
    "dual.fits": mosaic(biasADU + 6, biasADU + 3, biasADU + 2),
    "bias.fits": mosaic(biasADU, biasADU, biasADU),
  ])

  @Test("two colour nights separated purely by their pixels; calibration sets never classified")
  func testFilterSetScan_annotation() {
    var inventory = Self.inventory([
      Self.osc("dual.fits", .light, exposureMs: 120_000),
      Self.osc("broad.fits", .light, exposureMs: 300_000),
      Self.osc("bias.fits", .bias, exposureMs: 0),
    ])
    #expect(inventory.colorModel == .osc)
    let reader = Self.reader([
      "dual.fits": Self.mosaic(Self.biasADU + 6, Self.biasADU + 3, Self.biasADU + 2),
      "broad.fits": Self.mosaic(Self.biasADU + 70, Self.biasADU + 95, Self.biasADU + 105),
      "bias.fits": Self.mosaic(Self.biasADU, Self.biasADU, Self.biasADU),
    ])
    FilterSetClassifier.annotate(&inventory, overrides: [:], pixels: reader)
    #expect(inventory.filterSets[Self.id(inventory, .light, 120_000)] == .dualband)
    #expect(inventory.filterSets[Self.id(inventory, .light, 300_000)] == .broadband)
    #expect(inventory.filterSets[Self.id(inventory, .bias, 0)] == nil)
    for set in inventory.sets {
      #expect(set.filterSet == (inventory.filterSets[set.key.id] ?? .unknown))
    }
  }

  @Test("no bias, no pedestal, no verdict")
  func testFilterSetScan_noBias() {
    var inventory = Self.inventory([Self.osc("dual.fits", .light, exposureMs: 120_000)])
    FilterSetClassifier.annotate(&inventory, overrides: [:], pixels: Self.dualAndBias)
    #expect(inventory.filterSets.isEmpty)
    #expect(inventory.sets.allSatisfy { $0.filterSet == .unknown })
  }

  @Test("a mono scan reads no pixel and gets no verdict")
  func testFilterSetScan_monoUntouched() {
    var light = CaptureFrame(path: "l.fits")
    light.type = .light
    light.filter = "L"
    light.exposureMs = 120_000
    var bias = CaptureFrame(path: "b.fits")
    bias.type = .bias
    var inventory = Self.inventory([light, bias])
    #expect(inventory.colorModel == .mono)
    FilterSetClassifier.annotate(&inventory, overrides: [:], pixels: Self.reader([:]))
    #expect(inventory.filterSets.isEmpty)
  }

  @Test(
    "an override beats a measured verdict, applies where nothing was measured, unknown is not one")
  func testBroadbandVsDualBand_overrideWins() {
    var inventory = Self.inventory([
      Self.osc("dual.fits", .light, exposureMs: 120_000),
      Self.osc("bias.fits", .bias, exposureMs: 0),
    ])
    let dual = Self.id(inventory, .light, 120_000)
    FilterSetClassifier.annotate(
      &inventory, overrides: [dual: .broadband], pixels: Self.dualAndBias)
    #expect(inventory.filterSets[dual] == .broadband)
    FilterSetClassifier.annotate(&inventory, overrides: [dual: .unknown], pixels: Self.dualAndBias)
    #expect(inventory.filterSets[dual] == .dualband)

    var blind = Self.inventory([Self.osc("dual.fits", .light, exposureMs: 120_000)])
    let id = Self.id(blind, .light, 120_000)
    FilterSetClassifier.annotate(&blind, overrides: [id: .dualband], pixels: Self.reader([:]))
    #expect(blind.filterSets[id] == .dualband)
  }

  @Test("Siril's [0,1] floats classify like the camera's 16-bit original")
  func testFilterSetScan_normalizedPixels() {
    var inventory = Self.inventory([
      Self.osc("dual.fits", .light, exposureMs: 120_000),
      Self.osc("bias.fits", .bias, exposureMs: 0),
    ])
    let scale = 65535.0
    let reader = Self.reader([
      "dual.fits": Self.mosaic(
        (Self.biasADU + 6) / scale, (Self.biasADU + 3) / scale, (Self.biasADU + 2) / scale),
      "bias.fits": Self.mosaic(Self.biasADU / scale, Self.biasADU / scale, Self.biasADU / scale),
    ])
    FilterSetClassifier.annotate(&inventory, overrides: [:], pixels: reader)
    #expect(inventory.filterSets[Self.id(inventory, .light, 120_000)] == .dualband)
  }

  @Test("the verdict map survives a regroup; the projection is re-applied")
  func testFilterSetScan_survivesRegroup() {
    var inventory = Self.inventory([
      Self.osc("dual.fits", .light, exposureMs: 120_000),
      Self.osc("bias.fits", .bias, exposureMs: 0),
    ])
    FilterSetClassifier.annotate(&inventory, overrides: [:], pixels: Self.dualAndBias)
    inventory.regroup()
    #expect(inventory.sets.first { $0.key.type == .light }?.filterSet == .dualband)
  }

  @Test("a dense star field must not push a dual-band night out of its band")
  func testFilterSetScan_denseStarField() {
    var inventory = Self.inventory([
      Self.osc("light.fits", .light, exposureMs: 120_000),
      Self.osc("bias.fits", .bias, exposureMs: 0),
    ])
    let reader = Self.reader([
      "light.fits": Self.starfield(
        sky: (Self.biasADU + 12, Self.biasADU + 9.6, Self.biasADU + 5.6), starFraction: 0.05,
        starADU: 40),
      "bias.fits": Self.mosaic(Self.biasADU, Self.biasADU, Self.biasADU),
    ])
    FilterSetClassifier.annotate(&inventory, overrides: [:], pixels: reader)
    #expect(inventory.filterSets[Self.id(inventory, .light, 120_000)] == .dualband)
  }

  static func lightSet(_ night: String, _ exposureMs: Int, _ verdict: FilterSet) -> (
    SetKey, FilterSet
  ) {
    (
      SetKey(
        type: .light, object: "NGC7000", filter: Filter.color, exposureMs: exposureMs, gain: 100,
        offset: 50, bin: 1, session: night, color: true), verdict
    )
  }

  static func nightInventory(_ sets: [(SetKey, FilterSet)]) -> Inventory {
    var inventory = Inventory(root: "", frames: [])
    inventory.sets = sets.map { FrameSet(key: $0.0, frames: [], indices: [], filterSet: $0.1) }
    inventory.filterSets = Dictionary(
      sets.filter { $0.1.isKnown }.map { ($0.0.id, $0.1) }, uniquingKeysWith: { $1 })
    return inventory
  }

  static let nightA = "2026-07-29"
  static let nightB = "2026-08-02"
  static let flatB = (
    SetKey(
      type: .flat, exposureMs: 2000, gain: 100, offset: 50, bin: 1, session: nightB, color: true),
    FilterSet.unknown
  )
  static let flatUndated = (
    SetKey(type: .flat, exposureMs: 2000, gain: 100, offset: 50, bin: 1, color: true),
    FilterSet.unknown
  )

  @Test(
    "a night's clip filter: one voice decides, a swap is unknown, only lights speak",
    arguments: [
      ([lightSet(nightA, 120_000, .dualband)], nightA, FilterSet.dualband),
      (
        [lightSet(nightA, 120_000, .dualband), lightSet(nightA, 300_000, .dualband)], nightA,
        .dualband
      ),
      (
        [lightSet(nightA, 120_000, .broadband), lightSet(nightA, 300_000, .unknown)], nightA,
        .broadband
      ),
      (
        [lightSet(nightA, 120_000, .dualband), lightSet(nightA, 300_000, .broadband)], nightA,
        .unknown
      ),
      (
        [lightSet(nightA, 120_000, .dualband), lightSet(nightB, 120_000, .broadband)], nightB,
        .broadband
      ),
      ([lightSet("", 120_000, .dualband), flatUndated], "", .dualband),
      ([lightSet(nightA, 120_000, .dualband), flatB], nightB, .unknown),
      ([lightSet(nightA, 120_000, .unknown)], nightA, .unknown),
    ])
  func testInventory_nightFilterSet(sets: [(SetKey, FilterSet)], night: String, expected: FilterSet)
  {
    #expect(Self.nightInventory(sets).nightFilterSet(night) == expected)
  }

  @Test("the night verdict reads the durable map, not the projection")
  func testInventory_nightFilterSetReadsMap() {
    var inventory = Self.nightInventory([Self.lightSet(Self.nightA, 120_000, .dualband)])
    for index in inventory.sets.indices { inventory.sets[index].filterSet = .unknown }
    #expect(inventory.nightFilterSet(Self.nightA) == .dualband)
  }
}

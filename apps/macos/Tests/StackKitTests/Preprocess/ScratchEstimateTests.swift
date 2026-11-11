import FilterKit
import Foundation
import StackKit
import TestSupport
import Testing

/// `ScratchEstimate` is the disk a run's Siril work folder peaks at, pinned against the two runs
/// card 0058 measured (`docs/design/validation-e14.md` § Disk).
@Suite("ScratchEstimate — the scratch a run needs, before Siril starts")
struct ScratchEstimateTests {
  /// The ASI2600MC frame of both 0058 targets.
  static let (width, height) = (6248, 4176)

  /// `count` lights of one set on `night`.
  static func set(
    _ night: String, count: Int, width: Int = width, height: Int = height, bayer: String = "RGGB",
    channels: Int = 1, filter: String = Filter.color, exposureMs: Int = 300_000
  ) -> FrameSet {
    let key = SetKey(
      type: .light, object: "M 31", filter: filter, exposureMs: exposureMs, gain: 100,
      offset: 50, tempBucketC: -10, bin: 1, session: night)
    let frames = (0..<count).map { index in
      var frame = CaptureFrame(path: "/cap/\(night)_\(filter)_\(exposureMs)_\(index).fits")
      frame.type = .light
      (frame.width, frame.height, frame.bayer, frame.channels) = (width, height, bayer, channels)
      frame.session = night
      return frame
    }
    return FrameSet(key: key, frames: frames, indices: Array(0..<count))
  }

  /// A scan of `sets`, `verdicts` index-aligned (a colour scan when the frames carry colour).
  static func scan(_ sets: [FrameSet], _ verdicts: [FilterSet] = []) -> Inventory {
    var inventory = Inventory(root: "/cap", frames: sets.flatMap(\.frames))
    inventory.colorModel = sets.first?.frames.first?.isColor == true ? .osc : .mono
    inventory.sets = sets
    for (set, verdict) in zip(sets, verdicts) where verdict.isKnown {
      inventory.filterSets[set.key.id] = verdict
    }
    return inventory
  }

  struct Measured: Sendable, CustomTestStringConvertible {
    let name: String
    let inventory: Inventory
    let peakGB: Double
    var testDescription: String { name }
  }

  /// 0058's runs as the scan saw them: M 31 = 84 broadband lights over three nights + the
  /// 2026-09-22 night (36) marked dual-band; IC 1848 = 111 lights over three nights.
  static let measured = [
    Measured(
      name: "M 31 BB+DB (80.6 GB)",
      inventory: scan(
        [
          set("2026-09-14", count: 19, exposureMs: 300_000),
          set("2026-09-21", count: 29, exposureMs: 300_000),
          set("2026-10-17", count: 36, exposureMs: 300_000),
          set("2026-09-22", count: 36, exposureMs: 300_001),
        ], [.broadband, .broadband, .broadband, .dualband]),
      peakGB: 80.6),
    Measured(
      name: "IC 1848 (106 GB)",
      inventory: scan([
        set("2026-09-21", count: 48), set("2026-09-22", count: 55), set("2026-10-17", count: 8),
      ]),
      peakGB: 106),
  ]

  @Test("pinned against the 0058 measurement within 10 %", arguments: measured)
  func testEstimateMatchesMeasurement(run: Measured) throws {
    let estimate = try ScratchEstimate(run.inventory, settings: .preset(.deepsky))
    let gigabytes = Double(estimate.bytes) / 1e9
    #expect(abs(gigabytes - run.peakGB) / run.peakGB <= 0.10, "\(gigabytes) GB")
  }

  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let sets: [FrameSet]
    let flatten: Bool
    /// Bytes of one written copy of one light.
    let frameBytes: Int64
    /// Copies per light of the lane that peaks (2: calibrated + registered; 3 with the flatten).
    let copies: Int64
    /// Lights in that lane.
    let lights: Int64
    var testDescription: String { name }
  }

  static let osc = Int64(width * height * 3 * 4)

  static let cases = [
    Case(
      name: "one night OSC: calibrated + registered, debayered",
      sets: [set("2026-09-22", count: 10)], flatten: true, frameBytes: osc, copies: 2, lights: 10),
    Case(
      name: "three nights OSC, flatten on: + the flattened copy",
      sets: [
        set("2026-09-21", count: 4), set("2026-09-22", count: 5), set("2026-10-17", count: 6),
      ],
      flatten: true, frameBytes: osc, copies: 3, lights: 15),
    Case(
      name: "three nights OSC, flatten off",
      sets: [
        set("2026-09-21", count: 4), set("2026-09-22", count: 5), set("2026-10-17", count: 6),
      ],
      flatten: false, frameBytes: osc, copies: 2, lights: 15),
    Case(
      name: "mono 4656×3520, the largest filter lane peaks (lanes run one after another)",
      sets: [
        set("2026-09-22", count: 20, width: 4656, height: 3520, bayer: "", filter: "L"),
        set("2026-09-22", count: 8, width: 4656, height: 3520, bayer: "", filter: "Ha"),
      ],
      flatten: true, frameBytes: Int64(4656 * 3520 * 4), copies: 2, lights: 20),
    Case(
      name: "already debayered three-plane frames",
      sets: [set("2026-09-22", count: 3, width: 3000, height: 2000, bayer: "", channels: 3)],
      flatten: true, frameBytes: Int64(3000 * 2000 * 3 * 4), copies: 2, lights: 3),
  ]

  @Test("frame size × lane shape", arguments: cases)
  func testEstimatePerFrame(example: Case) throws {
    var settings = PreprocessSettings.preset(.deepsky)
    settings.flattenBackground = example.flatten
    let estimate = try ScratchEstimate(Self.scan(example.sets), settings: settings)
    #expect(estimate.bytes == example.lights * example.copies * example.frameBytes)
  }

  @Test("a camera-raw night (NEF) adds the copy Siril's convert writes, one plane per mosaic")
  func testConvertedRawAddsIngestCopy() throws {
    var raw = Self.set("2026-09-22", count: 4, width: 6048, height: 4032)
    for index in raw.frames.indices {
      raw.frames[index].path = raw.frames[index].path.replacingOccurrences(
        of: ".fits", with: ".nef")
    }
    let estimate = try ScratchEstimate(Self.scan([raw]), settings: .preset(.deepsky))
    let pixels = Int64(6048 * 4032)
    #expect(estimate.bytes == 4 * (2 * pixels * 3 * 4 + pixels * 4))
  }

  @Test("a scan without lights estimates nothing: the run's own refusal names it")
  func testNoLights() {
    #expect(throws: PreprocessError.noLights) {
      try ScratchEstimate(Self.scan([]), settings: .preset(.deepsky))
    }
  }

  /// Ten one-night OSC lights peak at two copies each.
  static let tenLights = 2 * 10 * osc

  @Test(
    "refused only when the peak exceeds the room left; a volume that does not say refuses nothing",
    arguments: [
      (Int64?.some(tenLights - 1), true), (tenLights, false), (3 * tenLights, false), (nil, false),
    ])
  func testCheckRoom(room: Int64?, refused: Bool) throws {
    let estimate = try ScratchEstimate(
      Self.scan([Self.set("2026-09-22", count: 10)]), settings: .preset(.deepsky))
    let folder = URL(fileURLWithPath: "/Volumes/Scratch/Work")
    guard refused, let room else {
      try estimate.check(room: room, folder: folder)
      return
    }
    #expect(
      throws: PreprocessError.scratchFull(
        neededBytes: Self.tenLights, availableBytes: room, folder: "/Volumes/Scratch/Work")
    ) { try estimate.check(room: room, folder: folder) }
  }

  @Test("the refusal names the need, the room and the folder")
  func testScratchFullMessage() {
    let error = PreprocessError.scratchFull(
      neededBytes: 81_000_000_000, availableBytes: 40_000_000_000, folder: "/Volumes/Scratch")
    #expect(error.localizedDescription.contains("81 GB"))
    #expect(error.localizedDescription.contains("40 GB free"))
    #expect(error.localizedDescription.contains("/Volumes/Scratch"))
  }

  @Test(
    "testEstimate_CachedFramesNotCounted: kept frames cost nothing, the others stay for the run")
  func testEstimate_CachedFramesNotCounted() throws {
    var remote = Self.set("2026-09-22", count: 4, width: 4656, height: 3520, bayer: "", filter: "L")
    for index in remote.frames.indices {
      remote.frames[index].path = "s3://astro/M31/l_\(index).fits"
    }
    let inventory = Self.scan([remote])
    let copy = Int64(4656 * 3520 * 4)
    let raw = Int64(4656 * 3520 * 2)
    let settings = PreprocessSettings.preset(.deepsky)

    let inLane = try ScratchEstimate(inventory, settings: settings)
    #expect(inLane.bytes == 4 * (2 * copy + raw), "no cache: the downloads go with the lane")

    let none = try ScratchEstimate(inventory, settings: settings, kept: [])
    #expect(none.bytes == 4 * (2 * copy + raw), "nothing kept yet: every frame is downloaded")
    #expect(none.keptBytes == 4 * raw, "and stays after the run")

    let paths = Set(remote.frames.prefix(3).map(\.path))
    let kept = try ScratchEstimate(inventory, settings: settings, kept: paths)
    #expect(kept.bytes == 4 * 2 * copy + raw, "three kept: one download left")
    #expect(kept.lane == inLane.lane && kept.keptBytes == raw)

    #expect(ScratchEstimate.queued([]) == nil)
    #expect(ScratchEstimate.queued([inLane, inLane]) == inLane.bytes, "nothing kept: the peak")
    #expect(
      ScratchEstimate.queued([none, none]) == 4 * 2 * copy + 2 * 4 * raw,
      "a queue keeps each run's lights: the next run finds them on the disk")

    // The runs of a queue share the capture's calibration: it is downloaded, and counted, once.
    var darks = Self.set("", count: 2, width: 4656, height: 3520, bayer: "", filter: "")
    for index in darks.frames.indices {
      darks.frames[index].type = .dark
      darks.frames[index].path = "s3://astro/M31/d_\(index).fits"
    }
    darks.key.type = .dark
    let withDarks = try ScratchEstimate(Self.scan([remote, darks]), settings: settings, kept: [])
    #expect(withDarks.keptLightBytes == 4 * raw && withDarks.keptCalibrationBytes == 2 * raw)
    #expect(
      ScratchEstimate.queued([withDarks, withDarks]) == 4 * 2 * copy + 2 * 4 * raw + 2 * raw)
  }
}

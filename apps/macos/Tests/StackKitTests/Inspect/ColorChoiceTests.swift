import StackKit
import Testing

/// Translated from `internal/inspect/colorchoice_test.go` (the shared-pointer case does not apply:
/// frames are values here) and the unit half of `channel_test.go` (filter mapping).
@Suite("ColorChoice — the user's mono/colour assertion narrows the lights")
struct ColorChoiceTests {
  static func frame(_ type: FrameType, filter: String = "", channels: Int = 0) -> CaptureFrame {
    var frame = CaptureFrame(path: "")
    frame.type = type
    frame.filter = filter
    frame.channels = channels
    frame.exposureMs = 120_000
    frame.gain = 139
    frame.offset = 10
    frame.binX = 1
    frame.binY = 1
    return frame
  }

  static let mono = frame(.light, filter: "L")
  static let monoR = frame(.light, filter: "R")
  static let color = frame(.light, channels: 3)
  static let dark = frame(.dark)

  static func seed(_ frames: [CaptureFrame]) -> Inventory {
    var inventory = Inventory(root: "", frames: frames)
    inventory.colorModel = inventory.lightColorModel
    inventory.nameColorChannel()
    inventory.regroup()
    return inventory
  }

  struct Row: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let choice: ColorChoice
    let frames: [CaptureFrame]
    let model: ColorModel
    let lights: Int
    var darks = 0
    var warning = ""
  }

  static let rows: [Row] = [
    Row(
      testDescription: "auto leaves mono", choice: .auto, frames: [mono, monoR], model: .mono,
      lights: 2),
    Row(
      testDescription: "auto leaves colour", choice: .auto, frames: [color, color], model: .osc,
      lights: 2),
    Row(
      testDescription: "auto leaves mixed", choice: .auto, frames: [mono, color], model: .mixed,
      lights: 2),
    Row(
      testDescription: "mono on mono", choice: .mono, frames: [mono, monoR], model: .mono, lights: 2
    ),
    Row(
      testDescription: "mono on mixed drops colour", choice: .mono, frames: [mono, color],
      model: .mono,
      lights: 1, warning: "monochrome stack"),
    Row(
      testDescription: "osc on colour", choice: .osc, frames: [color, color], model: .osc, lights: 2
    ),
    Row(
      testDescription: "osc on mixed drops mono", choice: .osc, frames: [mono, color], model: .osc,
      lights: 1, warning: "colour stack"),
    Row(
      testDescription: "osc keeps a Bayer-less dark", choice: .osc, frames: [color, mono, dark],
      model: .osc, lights: 1, darks: 1, warning: "colour stack"),
    Row(
      testDescription: "a choice on a calibration-only scan is no error", choice: .mono,
      frames: [dark], model: .mono, lights: 0, darks: 1),
  ]

  @Test("an explicit choice drops contradicting lights only; auto changes nothing", arguments: rows)
  func testColorChoice_resolve(row: Row) throws {
    var inventory = Self.seed(row.frames)
    try inventory.resolve(row.choice)
    #expect(inventory.colorModel == row.model)
    #expect(inventory.frames.count { $0.type == .light } == row.lights)
    #expect(inventory.frames.count { $0.type == .dark } == row.darks)
    #expect(inventory.sets == FrameSet.group(inventory.frames))
    if row.warning.isEmpty {
      #expect(inventory.warnings.isEmpty)
    } else {
      #expect(inventory.warnings.joined(separator: "\n").contains(row.warning))
    }
  }

  @Test(
    "a choice no light matches is an honest error",
    arguments: [(ColorChoice.mono, [color, color]), (.osc, [mono, monoR])])
  func testColorChoice_noLights(choice: ColorChoice, frames: [CaptureFrame]) {
    var inventory = Self.seed(frames)
    #expect(throws: InspectError.noLightsForColorModel(choice: choice.rawValue, dropped: 2)) {
      try inventory.resolve(choice)
    }
  }

  @Test("a mixed scan names its colour lights RGB; mono lights keep their filter")
  func testNameColorChannel_mixed() {
    let inventory = Self.seed([Self.mono, Self.color, Self.monoR])
    #expect(inventory.colorModel == .mixed)
    #expect(inventory.frames.map(\.filter) == ["L", "RGB", "R"])
    #expect(Self.seed([Self.mono, Self.monoR]).frames.map(\.filter) == ["L", "R"])
  }

  @Test("promoting a mixed scan to colour names the surviving colour lights RGB")
  func testColorChoice_namesColourChannel() throws {
    var inventory = Self.seed([Self.mono, Self.color])
    #expect(inventory.colorModel == .mixed)
    try inventory.resolve(.osc)
    #expect(inventory.frames.map(\.filter) == ["RGB"])
  }

  @Test(
    "the wire value is a closed enum; empty is auto",
    arguments: [
      ("", ColorChoice.auto), ("auto", .auto), ("mono", .mono), ("osc", .osc), ("OSC", .osc),
    ])
  func testColorChoice_parse(raw: String, expected: ColorChoice) throws {
    #expect(try ColorChoice(parsing: raw) == expected)
  }

  @Test("colour, rgb and mixed are not choices", arguments: ["colour", "rgb", "mixed"])
  func testColorChoice_parseRejects(raw: String) {
    #expect(throws: InspectError.unknownColorChoice(raw)) { try ColorChoice(parsing: raw) }
  }

  @Test("a filter mapping relabels lights and `ignore` drops them from the sets")
  func testInventory_applyFilterMapping() {
    var inventory = Self.seed(["R", "G", "B"].map { Self.frame(.light, filter: $0) })
    inventory.applyFilterMapping(["G": "ignore", "B": "Ha"])
    let filters = Set(inventory.sets.filter { $0.key.type == .light }.map(\.key.filter))
    #expect(filters == ["R", "Ha"])
    #expect(inventory.frames.first { $0.filter == "Ha" }?.classSource == .manual)
  }
}

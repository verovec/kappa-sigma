import ProcessKit
import RenderKit
import Testing

/// The handles of card 0089 on the head's histogram (values on the axis, `.linear`): a drag
/// edits the one value it names, clamped c0 ≤ m ≤ c1; the stretch's handles edit its σ and
/// target the way the viewer's controls read them.
@Suite("Histogram handles → process values (levels, stretch)")
struct HistogramHandledTests {
  static func levels(_ values: [String: ParamValue]) throws -> ParamSet {
    var params = ParamSet(schema: LevelsProcess.schema)
    for (id, value) in values { try params.set(id, value) }
    return params
  }

  static let stats = LayerStats(
    channels: [
      ChannelStats(median: 0.1, madn: 0.01, minimum: 0, maximum: 1),
      ChannelStats(median: 0.12, madn: 0.012, minimum: 0, maximum: 1),
      ChannelStats(median: 0.08, madn: 0.008, minimum: 0, maximum: 1),
    ])

  @Test("dragging the mid handle edits the midtones only, clamped between the points")
  func testDragMapsToLevelsParams() throws {
    let params = try Self.levels([
      "rgbShadows": .number(0.1), "rgbMidtones": .number(0.5), "rgbHighlights": .number(0.9),
    ])
    let handles = LevelsProcess.handles(params, stats: Self.stats, channels: 3)
    #expect(handles == [STFHandlePositions(shadows: 0.1, midtone: 0.5, highlights: 0.9)])

    let moved = try LevelsProcess.dragging(
      .midtone, channel: 0, to: 0.3, params: params, stats: Self.stats)
    #expect(abs(moved.number("rgbMidtones") - 0.25) < 1e-12, "0.3 sits at a quarter of 0.1…0.9")
    for id in ["rgbShadows", "rgbHighlights", "rMidtones", "linked"] {
      #expect(moved[id] == params[id], "\(id) untouched")
    }
    let past = try LevelsProcess.dragging(
      .midtone, channel: 0, to: 0.95, params: params, stats: Self.stats)
    #expect(past.number("rgbMidtones") == 1, "the mid handle stops at the white point")
    let crossed = try LevelsProcess.dragging(
      .shadows, channel: 0, to: 0.95, params: params, stats: Self.stats)
    #expect(crossed.number("rgbShadows") == 0.9 - STFParameters.minimumRange)
  }

  @Test("unlinked, each channel's handles edit its own triple")
  func testUnlinkedChannels() throws {
    let params = try Self.levels(["linked": .flag(false)])
    #expect(LevelsProcess.handles(params, stats: Self.stats, channels: 3).count == 3)
    #expect(LevelsProcess.handles(params, stats: Self.stats, channels: 1).count == 1)
    let moved = try LevelsProcess.dragging(
      .shadows, channel: 1, to: 0.05, params: params, stats: Self.stats)
    #expect(moved.number("gShadows") == 0.05 && moved.number("rgbShadows") == 0)
  }

  @Test("the stretch's handles move its σ and target; the white point is not one of its values")
  func testStretchHandles() throws {
    let params = ParamSet(schema: StretchProcess.schema)
    let mapping = STFMapping.linked(
      Self.stats.channels.map { STFMapping(median: $0.median, madn: $0.madn) })[0]
    let stf = mapping.parameters(sigma: -2.8, targetBackground: 0.25)
    let handles = StretchProcess.handles(params, stats: Self.stats, channels: 3)
    #expect(handles == [stf.handlePositions(in: .linear)])

    let shadows = try StretchProcess.dragging(
      .shadows, channel: 0, to: 0.05, params: params, stats: Self.stats)
    #expect(abs(shadows.number("shadowsClip") - mapping.sigma(ofShadows: 0.05)) < 1e-12)
    #expect(shadows.number("targetBackground") == 0.25)
    let midtone = try StretchProcess.dragging(
      .midtone, channel: 0, to: 0.2, params: params, stats: Self.stats)
    let dragged = stf.dragging(.midtone, to: 0.2, in: .linear)
    #expect(
      abs(
        midtone.number("targetBackground")
          - mapping.targetBackground(ofMidtone: dragged.midtone, shadows: stf.shadows)) < 1e-12)
    #expect(
      try StretchProcess.dragging(
        .highlights, channel: 0, to: 0.5, params: params, stats: Self.stats) == params)
    var ghs = params
    try ghs.set("mode", .choice("ghs"))
    #expect(StretchProcess.handles(ghs, stats: Self.stats, channels: 3).isEmpty, "MTF only")
  }
}

extension HistogramHandledTests {
  @Test("the CPU transfer composes each channel's triple, then RGB/K, as the kernel does")
  func testTransfer() throws {
    let params = try Self.levels([
      "linked": .flag(false), "gShadows": .number(0.2), "rgbMidtones": .number(0.3),
    ])
    let green = STFParameters(shadows: 0.2, midtone: 0.5, highlights: 1)
    let rgb = STFParameters(shadows: 0, midtone: 0.3, highlights: 1)
    let x = 0.4
    #expect(
      LevelsProcess.transfer(x, channel: 1, channels: 3, params: params)
        == rgb.display(green.display(x)))
    #expect(LevelsProcess.transfer(x, channel: 0, channels: 3, params: params) == rgb.display(x))
    #expect(
      LevelsProcess.transfer(1.5, channel: 0, channels: 1, params: try Self.levels([:])) == 1.5)
    #expect(LevelsProcess.steps["rgbShadows"] == 0.001 && LevelsProcess.steps["bMidtones"] == 0.01)
  }
}

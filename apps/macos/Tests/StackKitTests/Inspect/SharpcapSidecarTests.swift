import Foundation
import StackKit
import TestSupport
import Testing

/// Translated from `internal/inspect/sidecar_test.go`.
@Suite("SharpcapSidecar — the per-frame capture-settings file")
struct SharpcapSidecarTests {
  @Test(
    "keys are read by full name; slot aliases count only when they name a filter",
    arguments: [
      (
        "[ZWO ASI1600MM Pro]\nEFW Slot = 1(Alias: 1)\nExposure = 30s\nGain = 300\n"
          + "Temperature = -15.0 C\n",
        SharpcapSidecar(
          slot: 1, gain: 300, hasGain: true, exposureMs: 30000, tempMilliC: -15000, hasTemp: true)
      ),
      (
        "EFW Slot = 5(Alias: Ha)\nExposure = 1500ms\n",
        SharpcapSidecar(slot: 5, slotAlias: "Ha", exposureMs: 1500)
      ),
      ("EFW Slot = 3(Alias: green)\n", SharpcapSidecar(slot: 3, slotAlias: "G")),
      ("EFW Slot = 2(Alias: Moon)\nGain = 0\n", SharpcapSidecar(slot: 2, hasGain: true)),
      (
        "Gain = 200\nExposure = 60s\n",
        SharpcapSidecar(gain: 200, hasGain: true, exposureMs: 60000)
      ),
      (
        "[ZWO ASI1600MM Pro]\nAuto Exp Target Brightness = 100\nBrightness = 10\n"
          + "EFW Slot = 4(Alias: B)\nExposure = 10ms\nGain = 0\nTemperature = -17.0 C\n",
        SharpcapSidecar(
          slot: 4, slotAlias: "B", hasGain: true, offset: 10, hasOffset: true, exposureMs: 10,
          tempMilliC: -17000, hasTemp: true)
      ),
      (
        "Gain = 100\nOffset = 21\n",
        SharpcapSidecar(gain: 100, hasGain: true, offset: 21, hasOffset: true)
      ),
      ("\n[header]\nrandom text\n", SharpcapSidecar()),
    ])
  func testSharpcapSidecar_parse(body: String, expected: SharpcapSidecar) {
    #expect(SharpcapSidecar(parsing: body) == expected)
  }

  @Test("the sidecar is <frame>.txt; an absent one reads as nil", .scratchDirectory)
  func testSharpcapSidecar_read() throws {
    let dir = try ScratchDirectory.url
    let frame = dir.appendingPathComponent("x.FIT").path
    try Data("placeholder".utf8).write(to: URL(fileURLWithPath: frame))
    try Data("EFW Slot = 2(Alias: 2)\nGain = 250\n".utf8)
      .write(to: URL(fileURLWithPath: frame + ".txt"))

    let sidecar = try #require(SharpcapSidecar.read(beside: frame))
    #expect(sidecar.slot == 2)
    #expect(sidecar.gain == 250)
    #expect(SharpcapSidecar.read(beside: dir.appendingPathComponent("missing.FIT").path) == nil)
  }
}

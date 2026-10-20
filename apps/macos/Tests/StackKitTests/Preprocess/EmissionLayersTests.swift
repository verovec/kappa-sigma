import Foundation
import StackKit
import TestSupport
import Testing

/// The assembly's emission step: a split capture's dual-band lane becomes `syn_Ha` + `syn_OIII`,
/// every line layer gets its continuum scale (or the reason it has none), the colour composite
/// is built from the broadband base alone, and the bundle records `continuum_k`.
@Suite("Emission layers — split, continuum scales, composite base, bundle")
struct EmissionLayersTests {
  static let (width, height) = (512, 256)

  static func ramp(_ scale: Float) -> [Float] {
    (0..<(width * height)).map { scale * (0.1 + 0.5 * Float($0 % width) / Float(width)) }
  }

  static func write(_ name: String, _ planes: [[Float]]) throws -> URL {
    try FloatFITS.write(
      try ScratchDirectory.url.appendingPathComponent(name + ".fits"), width: width,
      height: height, planes: planes)
  }

  @Test("broadband + dual-band: Hα and [OIII] split, scales fitted on the colour base", .scratchDirectory)
  func testSplitCapture() throws {
    let out = try ScratchDirectory.url
    _ = try Self.write("trim_RGB", [Self.ramp(1), Self.ramp(0.8), Self.ramp(0.6)])
    _ = try Self.write("trim_RGB-dualband", [Self.ramp(0.5), Self.ramp(0.2), Self.ramp(0.1)])
    var notes: [String] = []
    let (channels, continuum) = Preprocessor.emission(
      ["RGB": "trim_RGB", "RGB-dualband": "trim_RGB-dualband"], out: out, notes: &notes)
    #expect(channels == ["RGB": "trim_RGB", "Ha": "syn_Ha", "OIII": "syn_OIII"])
    #expect(abs((continuum["Ha"] ?? 0) - 0.5) <= 0.01)
    #expect(abs((continuum["OIII"] ?? 0) - 0.25) <= 0.01)
    #expect(notes.count == 3 && notes[0].hasPrefix("mixed filter sets"))
    #expect(notes[1].hasPrefix("Ha: continuum k = 0.5") && notes[1].hasSuffix("against RGB"))
  }

  @Test("a mono Hα is fitted against R; a lone Hα says why it has no scale", .scratchDirectory)
  func testMono() throws {
    let out = try ScratchDirectory.url
    _ = try Self.write("trim_R", [Self.ramp(1)])
    _ = try Self.write("trim_Ha", [Self.ramp(0.5)])
    var notes: [String] = []
    let (_, continuum) = Preprocessor.emission(
      ["R": "trim_R", "Ha": "trim_Ha"], out: out, notes: &notes)
    #expect(abs((continuum["Ha"] ?? 0) - 0.5) <= 0.01 && notes.count == 1)
    var lone: [String] = []
    let (_, none) = Preprocessor.emission(["Ha": "trim_Ha"], out: out, notes: &lone)
    #expect(none.isEmpty && lone == ["Ha: continuum scale not fitted — no broadband channel (R/L) to estimate the continuum from"])
  }

  @Test("the composite base: the one colour master, emission layers set aside")
  func testCombineInputs() {
    #expect(
      ChannelCombiner.inputs(["RGB": "trim_RGB", "Ha": "syn_Ha", "OIII": "syn_OIII"])
        == .colour("trim_RGB"))
    #expect(ChannelCombiner.inputs(["Ha": "trim_Ha", "OIII": "trim_OIII"]) == nil)
  }

  @Test("the bundle records each line layer's continuum_k", .scratchDirectory)
  func testBundle() throws {
    let out = try ScratchDirectory.url
    let base = try Self.write("trim_RGB", [Self.ramp(1), Self.ramp(1), Self.ramp(1)])
    let ha = try Self.write("syn_Ha", [Self.ramp(0.5)])
    let bundle = try BundleWriter().write(
      runID: "R", colorModel: .osc,
      layers: [
        .init(filter: "RGB", file: base, source: "trim"),
        .init(filter: "Ha", file: ha, source: "syn", continuumK: 0.5),
      ], to: out)
    #expect(bundle.layers.map(\.continuumK) == [nil, 0.5])
    #expect(try BundleWriter.read(from: out).layers[1].continuumK == 0.5)
  }
}

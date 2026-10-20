import Foundation
import StackKit
import TestSupport
import Testing

/// `ContinuumK` is the scale fit of `lineContinuumSubtract` (`hacontinuum.go`): cases of
/// `hacontinuum_test.go`, plus the one-shot-colour base the legacy reference list lacked.
@Suite("ContinuumK — the broadband scale of an emission layer's continuum")
struct ContinuumKTests {
  static let (width, height) = (512, 256)

  /// A smooth continuum ramp: the P85–P99.9 band is populated and blob-free.
  static func ramp(_ scale: Float = 1) -> [Float] {
    (0..<(width * height)).map { scale * (0.1 + 0.5 * Float($0 % width) / Float(width)) }
  }

  /// `k`·ramp, plus a 0.3 blob at low x (where the reference is dim).
  static func line(_ k: Float, of reference: [Float]) -> [Float] {
    reference.indices.map { index in
      let (x, y) = (index % width, index / width)
      return k * reference[index] + (x < 64 && y < 64 ? 0.3 : 0)
    }
  }

  static func write(_ name: String, _ planes: [[Float]]) throws -> URL {
    try FloatFITS.write(
      try ScratchDirectory.url.appendingPathComponent(name + ".fits"), width: width,
      height: height, planes: planes)
  }

  @Test("Hα = 0.5·R + emission: k = 0.5 (±0.01) against R", .scratchDirectory)
  func testHaAgainstR() throws {
    let red = Self.ramp()
    let layers = [
      "R": try Self.write("combine_R", [red]), "Ha": try Self.write("combine_Ha", [Self.line(0.5, of: red)]),
    ]
    let fit = try #require(try ContinuumK.measure(line: "Ha", layers: layers).fit)
    #expect(abs(fit.k - 0.5) <= 0.01 && fit.reference == "R")
  }

  @Test("a colour base: Hα against its red plane, [OIII] against its green", .scratchDirectory)
  func testColourBase() throws {
    let (red, green) = (Self.ramp(), Self.ramp(0.8))
    let layers = [
      "RGB": try Self.write("trim_RGB", [red, green, Self.ramp(0.6)]),
      "Ha": try Self.write("syn_Ha", [Self.line(0.5, of: red)]),
      "OIII": try Self.write("syn_OIII", [Self.line(0.25, of: green)]),
    ]
    let ha = try #require(try ContinuumK.measure(line: "Ha", layers: layers).fit)
    let oiii = try #require(try ContinuumK.measure(line: "OIII", layers: layers).fit)
    #expect(abs(ha.k - 0.5) <= 0.01 && ha.reference == "RGB")
    #expect(abs(oiii.k - 0.25) <= 0.01 && oiii.reference == "RGB")
  }

  @Test("a mono R wins over a colour base for Hα", .scratchDirectory)
  func testMonoFirst() throws {
    let red = Self.ramp()
    let layers = [
      "R": try Self.write("r", [red]), "RGB": try Self.write("rgb", [red, red, red]),
      "Ha": try Self.write("ha", [Self.line(0.5, of: red)]),
    ]
    #expect(try ContinuumK.measure(line: "Ha", layers: layers).fit?.reference == "R")
  }

  @Test("no broadband layer: no fit, and the reason", .scratchDirectory)
  func testNoReference() throws {
    let measured = try ContinuumK.measure(
      line: "Ha", layers: ["Ha": try Self.write("ha", [Self.ramp()])])
    #expect(measured.fit == nil && measured.reason?.contains("no broadband") == true)
  }

  @Test("a flat dark reference cannot calibrate the scale", .scratchDirectory)
  func testDarkReference() throws {
    let dark = [Float](repeating: 0, count: Self.width * Self.height)
    let measured = try ContinuumK.measure(
      line: "Ha", layers: ["R": try Self.write("r", [dark]), "Ha": try Self.write("ha", [dark])])
    #expect(measured.fit == nil && measured.reason?.contains("too dark") == true)
  }
}

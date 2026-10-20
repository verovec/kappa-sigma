import Foundation
import StackKit
import Testing

/// Translated from `internal/inspect/cfaprobe_test.go` and `dualband_test.go`: is a frame a real
/// colour mosaic, and the per-instrument spurious-BAYERPAT veto built on it.
@Suite("CFAProbe — a colour mosaic is told from a mono sensor by its pixels, not its FILTER")
struct CFAProbeTests {
  static func lattice(_ m00: Double, _ m10: Double, _ m01: Double, _ m11: Double) -> PixelPlanes {
    let size = 16
    var pixels = [Float](repeating: 0, count: size * size)
    for y in 0..<size {
      for x in 0..<size {
        let base = y % 2 == 0 ? (x % 2 == 0 ? m00 : m10) : (x % 2 == 0 ? m01 : m11)
        pixels[y * size + x] = Float(base + sin(Double(x * 7 + y * 13)) * 0.5)
      }
    }
    return PixelPlanes(width: size, height: size, planes: [pixels])
  }

  static let mosaic = lattice(520, 560, 560, 505)
  static let mono = lattice(500, 500, 500, 500)
  static let ambiguous = lattice(500, 510, 510, 500)

  @Test(
    "the four sub-lattices separate under dyes and stay together on one sensor",
    arguments: [
      (lattice(520, 560, 560, 505), CFAVerdict.cfa), (lattice(530, 504, 504, 502), .cfa),
      (lattice(500, 500, 500, 500), .mono), (lattice(500, 501, 500, 501), .mono),
      (lattice(500, 510, 510, 500), .unknown), (lattice(500, 502, 500, 502), .mono),
      (PixelPlanes(width: 0, height: 0, planes: [[]]), .unknown),
      (
        PixelPlanes(
          width: 4, height: 4,
          planes: Array(repeating: [Float](repeating: 0, count: 16), count: 3)),
        .unknown
      ),
    ])
  func testCFAProbe_structure(image: PixelPlanes, expected: CFAVerdict) {
    #expect(CFAProbe.verdict(image) == expected)
  }

  static func frames(_ count: Int) -> [CaptureFrame] {
    (0..<count).map { index in
      var frame = CaptureFrame(path: "\(index).fits")
      frame.type = .light
      frame.bayer = "RGGB"
      return frame
    }
  }

  static func reader(_ images: [PixelPlanes]) -> PixelReader {
    PixelReader(
      planes: { path in
        guard let index = Int(path.prefix { $0.isNumber }), images.indices.contains(index) else {
          throw FilterSetScanTests.Missing()
        }
        return images[index]
      },
      centerSample: { _, _ in [] })
  }

  @Test(
    "the sampled frames must agree; anything unreadable says nothing",
    arguments: [
      ([mosaic, mosaic, mosaic], 3, CFAVerdict.cfa), ([mono, mono, mono], 3, .mono),
      ([mosaic, mosaic, mono], 3, .unknown), ([mosaic, ambiguous, mosaic], 3, .unknown),
      ([], 2, .unknown), ([mosaic], 0, .unknown),
    ])
  func testCFAProbe_frames(images: [PixelPlanes], count: Int, expected: CFAVerdict) {
    #expect(CFAProbe.verdict(Self.frames(count), pixels: Self.reader(images)) == expected)
  }

  static func frame(
    _ path: String, _ type: FrameType, filter: String = "", instrument: String
  ) -> CaptureFrame {
    var frame = CaptureFrame(path: path)
    frame.type = type
    frame.bayer = "RGGB"
    frame.filter = filter
    frame.instrument = instrument
    return frame
  }

  static func pixels(_ byPath: @escaping @Sendable (String) -> PixelPlanes?) -> PixelReader {
    PixelReader(
      planes: { path in
        guard let image = byPath(path) else { throw FilterSetScanTests.Missing() }
        return image
      },
      centerSample: { _, _ in [] })
  }

  @Test("a dual-band clip on a colour camera keeps every Bayer card and stays OSC")
  func testCFAProbe_dualbandOSC() {
    var inventory = Inventory(
      root: "",
      frames: [
        Self.frame("bb.fits", .light, instrument: "ASI2600MC"),
        Self.frame("db.fits", .light, filter: "L-eXtreme", instrument: "ASI2600MC"),
        Self.frame("flat.fits", .flat, instrument: "ASI2600MC"),
        Self.frame("dark.fits", .dark, instrument: "ASI2600MC"),
      ])
    inventory.clearSpuriousBayer(pixels: Self.pixels { _ in Self.mosaic })
    #expect(inventory.frames.allSatisfy { $0.bayer == "RGGB" })
    #expect(inventory.warnings.isEmpty)
    #expect(inventory.lightColorModel == .osc)
  }

  @Test("a mono rig's spurious BAYERPAT is cleared on its lights and calibration, with a warning")
  func testCFAProbe_monoRig() {
    var inventory = Inventory(
      root: "",
      frames: [
        Self.frame("l.fits", .light, filter: "L", instrument: "ASI1600MM"),
        Self.frame("ha.fits", .light, filter: "Ha", instrument: "ASI1600MM"),
        Self.frame("bias.fits", .bias, instrument: "ASI1600MM"),
      ])
    inventory.clearSpuriousBayer(pixels: Self.pixels { _ in Self.mono })
    #expect(inventory.frames.allSatisfy { $0.bayer.isEmpty })
    #expect(inventory.warnings.count == 1)
    #expect(inventory.warnings.first?.contains("filter wheel (mono rig)") == true)
    #expect(inventory.warnings.first?.contains("3 frame(s)") == true)
    #expect(inventory.lightColorModel == .mono)
  }

  @Test("one rig's evidence never reaches another rig's frames")
  func testCFAProbe_perInstrument() {
    var inventory = Inventory(
      root: "",
      frames: [
        Self.frame("mono_l.fits", .light, filter: "L", instrument: "ASI1600MM"),
        Self.frame("mono_bias.fits", .bias, instrument: "ASI1600MM"),
        Self.frame("osc.fits", .light, instrument: "ASI2600MC"),
        Self.frame("osc_flat.fits", .flat, instrument: "ASI2600MC"),
      ])
    inventory.clearSpuriousBayer(
      pixels: Self.pixels { $0.hasPrefix("mono") ? Self.mono : Self.mosaic })
    #expect(inventory.frames.map(\.bayer) == ["", "", "RGGB", "RGGB"])
  }

  @Test("unreadable pixels keep the old clearing, and say so")
  func testCFAProbe_declined() {
    var inventory = Inventory(
      root: "", frames: [Self.frame("l.fits", .light, filter: "L", instrument: "ASI1600MM")])
    inventory.clearSpuriousBayer(pixels: Self.pixels { _ in nil })
    #expect(inventory.frames[0].bayer.isEmpty)
    #expect(inventory.warnings.count == 2)
    #expect(inventory.warnings.last?.contains("do not settle") == true)
  }
}

import Foundation
import StackKit
import TestSupport
import Testing

/// Translated from `internal/inspect/remote_test.go` (FrameFromHeader), `types_test.go` (FITS rows
/// of NeedsDebayer) and `inspect_test.go` (EXPOINUS, back-fill from a sidecar alias).
@Suite("CaptureFrame — a FITS header plus its path, as the legacy engine reads them")
struct CaptureFrameTests {
  static let paris = TimeZone(identifier: "Europe/Paris") ?? .gmt

  static func frame(_ url: URL) throws -> CaptureFrame {
    try CaptureFrame(reading: url, timeZone: paris)
  }

  @Test("the core cards fill type, filter, gain, offset, bin, exposure, size, object", .scratchDirectory)
  func testCaptureFrame_coreCards() throws {
    let url = try TestFITS.write(
      "x.fits", in: ScratchDirectory.url, width: 64, height: 48,
      cards: [
        "IMAGETYP": "LIGHT", "FILTER": "Ha", "GAIN": "180", "OFFSET": "30", "XBINNING": "2",
        "EXPTIME": "300.0", "OBJECT": "M42",
      ])
    let frame = try Self.frame(url)
    #expect(frame.type == .light)
    #expect(frame.classSource == .header)
    #expect(frame.filter == "Ha")
    #expect(frame.gain == 180)
    #expect(frame.hasGain)
    #expect(frame.offset == 30)
    #expect(frame.binX == 2)
    #expect(frame.exposureMs == 300_000)
    #expect(frame.width == 64)
    #expect(frame.height == 48)
    #expect(frame.object == "M42")
  }

  @Test("a real GAIN 0 is metadata; no GAIN card is not; SWCREATE is the creator", .scratchDirectory)
  func testCaptureFrame_gainZeroVsAbsent() throws {
    let dir = try ScratchDirectory.url
    let zero = try Self.frame(
      TestFITS.write(
        "g0.fits", in: dir, cards: ["IMAGETYP": "LIGHT", "GAIN": "0", "SWCREATE": "ASICAP"]))
    #expect(zero.hasGain)
    #expect(zero.gain == 0)
    #expect(zero.creator == "ASICAP")
    let absent = try Self.frame(TestFITS.write("plain.fits", in: dir, cards: ["IMAGETYP": "LIGHT"]))
    #expect(!absent.hasGain)
  }

  @Test("ASICAP's EXPOINUS (µs) is the exposure; a BAYERPAT makes the frame colour", .scratchDirectory)
  func testCaptureFrame_expoinusAndBayer() throws {
    let frame = try Self.frame(
      TestFITS.write(
        "lights/a.fit", in: ScratchDirectory.url,
        cards: ["IMAGETYP": "'Light'", "EXPOINUS": "30000000", "BAYERPAT": "'rggb'"]))
    #expect(frame.exposureMs == 30000)
    #expect(frame.bayer == "RGGB")
    #expect(frame.isColor)
    #expect(frame.needsDebayer)
  }

  @Test("BAYERPAT NONE is mono; NAXIS3 = 3 is colour already debayered", .scratchDirectory)
  func testCaptureFrame_bayerNoneAndRGB() throws {
    let dir = try ScratchDirectory.url
    let none = try Self.frame(TestFITS.write("a.fit", in: dir, cards: ["BAYERPAT": "'NONE'"]))
    #expect(none.bayer.isEmpty)
    let rgb = try Self.frame(
      TestFITS.write(
        "rgb.fit", in: dir, width: 4, height: 4, planes: Array(repeating: [UInt16](repeating: 1, count: 16), count: 3),
        cards: ["BAYERPAT": "'RGGB'"]))
    #expect(rgb.channels == 3)
    #expect(rgb.isColor)
    #expect(!rgb.needsDebayer)
  }

  @Test("DATE-OBS gives epoch ms and the observing night, bucketed at local noon", .scratchDirectory)
  func testCaptureFrame_dateObsAndNight() throws {
    let frame = try Self.frame(
      TestFITS.write(
        "a.fit", in: ScratchDirectory.url, cards: ["DATE-OBS": "'2023-02-28T03:40:12.874142'"]))
    #expect(frame.dateObs == "2023-02-28T03:40:12.874142")
    #expect(frame.dateObsMs == 1_677_555_612_874)
    #expect(frame.session == "2023-02-27")
  }

  @Test(
    "DATE-OBS layouts the capture programs write; anything else is 0",
    arguments: [
      ("2024-03-01T22:10:00", 1_709_331_000_000), ("2024-03-01 22:10:00.5", 1_709_331_000_500),
      ("2024-03-01", 1_709_251_200_000), (" 2024-03-01T22:10:00 ", 1_709_331_000_000),
      ("2024-13-01", 0), ("yesterday", 0), ("", 0),
    ])
  func testCaptureFrame_parseDateObs(value: String, expected: Int) {
    #expect(CaptureFrame.parseDateObs(value) == expected)
  }

  @Test(
    "the night key is the evening's date in the given zone; no date is no night",
    arguments: [
      ("2023-02-28T03:40:00", "2023-02-27"), ("2023-02-27T20:00:00", "2023-02-27"),
      ("2023-02-28T11:30:00", "2023-02-28"), ("", ""),
    ])
  func testCaptureFrame_nightKey(utc: String, expected: String) {
    // 03:40 UTC is 04:40 in Paris: still the night of the 27th.
    #expect(Night.key(ms: CaptureFrame.parseDateObs(utc), in: Self.paris) == expected)
  }

  @Test("a flat's filter comes from the sidecar's slot alias once its folder typed it", .scratchDirectory)
  func testCaptureFrame_flatFilterFromSlotAlias() throws {
    let url = try TestFITS.write("flats/2023-02-28-0601_0-3-CapObj_0000.FIT", in: ScratchDirectory.url, cards: [:])
    try Data("EFW Slot = 3(Alias: Red)\nExposure = 1.5s\n".utf8)
      .write(to: URL(fileURLWithPath: url.path + ".txt"))
    let frame = try Self.frame(url)
    #expect(frame.type == .flat)
    #expect(frame.classSource == .filename)
    #expect(frame.filter == "R")
    #expect(frame.wheelSlot == 3)
    #expect(frame.exposureMs == 1500)
  }

  @Test(
    "FITS frames need debayering only while they are a one-plane mosaic",
    arguments: [("RGGB", 1, true), ("RGGB", 3, false), ("", 1, false), ("", 3, false)])
  func testCaptureFrame_needsDebayer(bayer: String, channels: Int, expected: Bool) {
    var frame = CaptureFrame(path: "/x/a.fits")
    frame.bayer = bayer
    frame.channels = channels
    #expect(frame.needsDebayer == expected)
  }
}

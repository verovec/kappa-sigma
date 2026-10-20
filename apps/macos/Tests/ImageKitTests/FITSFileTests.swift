import Foundation
import ImageKit
import TestSupport
import Testing

@Suite("FITSFile reads and writes the primary HDU the way Siril and the legacy reader do")
struct FITSFileTests {
  struct Planes: Sendable, CustomTestStringConvertible {
    let name: String
    let width: Int
    let height: Int
    let planes: [[Float]]
    let rowOrderCard: String?
    let rowOrder: RowOrder
    var testDescription: String { name }
  }

  static let ramp: [Float] = (0..<12).map { Float($0) / 11 }
  static let float32Cases: [Planes] = [
    Planes(
      name: "mono, TOP-DOWN", width: 4, height: 3, planes: [ramp],
      rowOrderCard: "'TOP-DOWN'", rowOrder: .topDown),
    Planes(
      name: "RGB, TOP-DOWN", width: 4, height: 3,
      planes: [ramp, ramp.map { 1 - $0 }, ramp.map { $0 * $0 }], rowOrderCard: "'TOP-DOWN'",
      rowOrder: .topDown),
    Planes(
      name: "mono, BOTTOM-UP", width: 3, height: 4, planes: [ramp],
      rowOrderCard: "'BOTTOM-UP'", rowOrder: .bottomUp),
    Planes(
      name: "RGB, no ROWORDER card (FITS default: bottom-up)", width: 2, height: 6,
      planes: [ramp, ramp, [Float](repeating: -0.25, count: 12)], rowOrderCard: nil,
      rowOrder: .bottomUp),
  ]

  static func write(_ data: Data, named name: String) throws -> URL {
    let url = try ScratchDirectory.url.appendingPathComponent(name)
    try data.write(to: url)
    return url
  }

  @Test(
    "float32 planes: dims, plane count, every pixel, row order kept as stored",
    .scratchDirectory, arguments: float32Cases)
  func testReadFloat32Planes(_ expected: Planes) throws {
    let extra = expected.rowOrderCard.map { [FITSBytes.card("ROWORDER", $0)] } ?? []
    let url = try Self.write(
      FITSBytes.float32(
        width: expected.width, height: expected.height, planes: expected.planes, extra: extra),
      named: "f.fits")

    let image = try FITSFile.read(at: url).image()
    #expect(image.width == expected.width)
    #expect(image.height == expected.height)
    #expect(image.planes.count == expected.planes.count)
    #expect(image.planes == expected.planes, "no flip: rows stay in file order")
    #expect(image.metadata.rowOrder == expected.rowOrder)
  }

  @Test("float32: read then write gives the same bytes, extra cards included", .scratchDirectory)
  func testWriteRoundTripBytes() throws {
    let original = FITSBytes.float32(
      width: 4, height: 3, planes: [Self.ramp, Self.ramp, Self.ramp],
      extra: [
        FITSBytes.card("ROWORDER", "'TOP-DOWN'"), FITSBytes.card("FILTER", "'RGB'"),
        FITSBytes.card("CTYPE1", "'RA---TAN'"), FITSBytes.card("HISTORY", "stacked by Siril"),
      ])
    let file = try FITSFile.read(at: Self.write(original, named: "in.fits"))
    let out = try ScratchDirectory.url.appendingPathComponent("out.fits")

    try file.write(file.image(), to: out)
    #expect(try Data(contentsOf: out) == original)
  }

  @Test(
    "BITPIX 16 with BZERO/BSCALE and BITPIX 8 decode to physical values", .scratchDirectory,
    arguments: [
      (FITSBytes.int16(width: 3, height: 1, raw: [-32768, 0, 32767]), [Float(0), 32768, 65535]),
      (
        FITSBytes.int16(width: 2, height: 1, raw: [100, -100], bzero: "0", bscale: "0.5"),
        [50, -50]
      ),
      (FITSBytes.uint8(width: 3, height: 1, raw: [0, 128, 255]), [0, 128, 255]),
    ])
  func testInt16WithBZero(bytes: Data, expected: [Float]) throws {
    let image = try FITSFile.read(at: Self.write(bytes, named: "i.fits")).image()
    #expect(image.planes == [expected])
  }

  @Test("header cards keep values, strings and order; metadata comes from them", .scratchDirectory)
  func testFITSFile_header_metadata() throws {
    let url = try Self.write(
      FITSBytes.float32(
        width: 1, height: 1, planes: [[0.5]],
        extra: [
          FITSBytes.card("FILTER", "'Ha      '"), FITSBytes.card("INSTRUME", "'ZWO ASI2600MC Air'"),
          FITSBytes.card("GAIN", "100"), FITSBytes.card("EXPTIME", "300.0"),
          FITSBytes.card("BAYERPAT", "'RGGB'"),
        ]),
      named: "h.fits")
    let file = try FITSFile.read(at: url)
    #expect(file.header.string("FILTER") == "Ha")
    #expect(file.header.double("EXPTIME") == 300)
    #expect(file.header.cards.first?.keyword == "SIMPLE")
    let metadata = try file.image().metadata
    #expect(metadata.filter == "Ha")
    #expect(metadata.camera == "ZWO ASI2600MC Air")
    #expect(metadata.gain == 100)
    #expect(metadata.exposureSeconds == 300)
    #expect(metadata.bayerPattern == "RGGB")
  }

  @Test(
    "malformed files are refused with the reason", .scratchDirectory,
    arguments: [
      ("empty", Data(), FITSError.noHeaderEnd),
      ("no END", FITSBytes.padded(Data(FITSBytes.card("SIMPLE", "T").utf8)), .noHeaderEnd),
      (
        "a PNG", FITSBytes.padded(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        .nonASCIIHeader
      ),
      (
        "truncated data",
        FITSBytes.header([
          FITSBytes.card("SIMPLE", "T"), FITSBytes.card("BITPIX", "-32"),
          FITSBytes.card("NAXIS", "2"),
          FITSBytes.card("NAXIS1", "10"), FITSBytes.card("NAXIS2", "10"),
        ]), .truncatedData
      ),
      (
        "BITPIX 12",
        FITSBytes.header([
          FITSBytes.card("SIMPLE", "T"), FITSBytes.card("BITPIX", "12"),
          FITSBytes.card("NAXIS", "2"),
          FITSBytes.card("NAXIS1", "1"), FITSBytes.card("NAXIS2", "1"),
        ]), .unsupportedBitpix(12)
      ),
      (
        "four planes",
        FITSBytes.header([
          FITSBytes.card("SIMPLE", "T"), FITSBytes.card("BITPIX", "8"),
          FITSBytes.card("NAXIS", "3"),
          FITSBytes.card("NAXIS1", "1"), FITSBytes.card("NAXIS2", "1"),
          FITSBytes.card("NAXIS3", "4"),
        ]) + FITSBytes.padded(Data([1, 2, 3, 4])), .unsupportedPlaneCount(4)
      ),
      (
        "dimensions that overflow",
        FITSBytes.header([
          FITSBytes.card("SIMPLE", "T"), FITSBytes.card("BITPIX", "-32"),
          FITSBytes.card("NAXIS", "2"), FITSBytes.card("NAXIS1", "4294967296"),
          FITSBytes.card("NAXIS2", "4294967296"),
        ]), .dimensionsTooLarge
      ),
    ])
  func testFITSFile_read_rejects(name: String, bytes: Data, expected: FITSError) throws {
    let url = try Self.write(bytes, named: "bad.fits")
    #expect(throws: FITSFileError(path: url.path, reason: expected), "\(name)") {
      try FITSFile.read(at: url).image()
    }
  }

  @Test(
    "float32 with BZERO/BSCALE survives a rewrite: stored = (value − BZERO) / BSCALE",
    .scratchDirectory)
  func testFITSFile_write_scaledFloat32() throws {
    let original = FITSBytes.header([
      FITSBytes.card("SIMPLE", "T"), FITSBytes.card("BITPIX", "-32"), FITSBytes.card("NAXIS", "2"),
      FITSBytes.card("NAXIS1", "2"), FITSBytes.card("NAXIS2", "1"), FITSBytes.card("BZERO", "0.5"),
      FITSBytes.card("BSCALE", "2"),
    ])
    var data = Data()
    for value: Float in [1, -0.25] {
      withUnsafeBytes(of: value.bitPattern.bigEndian) { data.append(contentsOf: $0) }
    }
    let file = try FITSFile.read(at: Self.write(original + FITSBytes.padded(data), named: "s.fits"))
    let image = try file.image()
    #expect(image.planes == [[2.5, 0]])

    let out = try ScratchDirectory.url.appendingPathComponent("out.fits")
    try file.write(image, to: out)
    #expect(try FITSFile.read(at: out).image().planes == [[2.5, 0]])
  }

  @Test("rewriting a file in place keeps the open FITSFile readable", .scratchDirectory)
  func testFITSFile_write_inPlace() throws {
    let url = try Self.write(
      FITSBytes.float32(width: 4, height: 3, planes: [Self.ramp]), named: "same.fits")
    let file = try FITSFile.read(at: url)
    let image = try file.image()
    image.planes = [image.planes[0].map { $0 * 2 }]

    try file.write(image, to: url)
    #expect(try file.image().planes == [Self.ramp], "the open file still reads its own bytes")
    #expect(try FITSFile.read(at: url).image().planes == image.planes)
  }

  @Test("a plane of the wrong length is refused, never written", .scratchDirectory)
  func testFITSFile_write_rejectsShortPlane() throws {
    let file = try FITSFile.read(
      at: Self.write(FITSBytes.float32(width: 4, height: 3, planes: [Self.ramp]), named: "p.fits"))
    let image = try file.image()
    image.planes = [Array(image.planes[0].dropLast())]
    let out = try ScratchDirectory.url.appendingPathComponent("out.fits")
    #expect(throws: FITSFileError(path: out.path, reason: .dimensionMismatch)) {
      try file.write(image, to: out)
    }
    #expect(!FileManager.default.fileExists(atPath: out.path))
  }

  @Test("parse accepts a Data slice that does not start at index 0")
  func testFITSFile_parse_slice() throws {
    let bytes =
      Data(repeating: 0, count: 7) + FITSBytes.float32(width: 2, height: 1, planes: [[1, 2]])
    let file = try FITSFile.parse(bytes[7...])
    #expect(try file.image().planes == [[1, 2]])
  }
}

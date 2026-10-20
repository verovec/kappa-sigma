/// An image's geometry and encoding, read from its header and checked against overflow.
struct FITSLayout {
  let width: Int
  let height: Int
  let planes: Int
  let bitpix: Int
  let bzero: Double
  let bscale: Double
  /// Bytes of the data unit (without padding).
  let dataBytes: Int

  var bytesPerValue: Int { abs(bitpix) / 8 }

  init(header: FITSHeader) throws {
    guard let bitpix = header.int("BITPIX") else { throw FITSError.missingCard("BITPIX") }
    guard [8, 16, 32, -32, -64].contains(bitpix) else { throw FITSError.unsupportedBitpix(bitpix) }
    guard let width = header.int("NAXIS1"), width > 0 else { throw FITSError.missingCard("NAXIS1") }
    guard let height = header.int("NAXIS2"), height > 0 else {
      throw FITSError.missingCard("NAXIS2")
    }
    let planes = (header.int("NAXIS") ?? 2) >= 3 ? (header.int("NAXIS3") ?? 1) : 1
    guard planes == 1 || planes == 3 else { throw FITSError.unsupportedPlaneCount(planes) }
    // A corrupt header must give an error, never an arithmetic trap.
    let (pixels, overflowA) = width.multipliedReportingOverflow(by: height)
    let (values, overflowB) = pixels.multipliedReportingOverflow(by: planes)
    let (bytes, overflowC) = values.multipliedReportingOverflow(by: abs(bitpix) / 8)
    guard !overflowA, !overflowB, !overflowC else { throw FITSError.dimensionsTooLarge }
    self.width = width
    self.height = height
    self.planes = planes
    self.bitpix = bitpix
    self.bzero = header.double("BZERO") ?? 0
    self.bscale = header.double("BSCALE") ?? 1
    self.dataBytes = bytes
  }
}

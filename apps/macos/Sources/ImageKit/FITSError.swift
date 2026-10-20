/// Why a FITS file cannot be read or written.
package enum FITSError: Error, Equatable, Sendable {
  /// No `END` card before the end of the file.
  case noHeaderEnd
  /// A header card holds non-ASCII bytes: not a FITS file.
  case nonASCIIHeader
  /// A required card is absent or not a number (`BITPIX`, `NAXIS1`, …).
  case missingCard(String)
  /// The data unit is shorter than NAXIS1 × NAXIS2 × NAXIS3 × |BITPIX|/8.
  case truncatedData
  /// BITPIX other than 8, 16, 32, −32, −64.
  case unsupportedBitpix(Int)
  /// NAXIS3 other than 1 or 3.
  case unsupportedPlaneCount(Int)
  /// The image written does not have the dimensions of the header it is written with.
  case dimensionMismatch
  /// NAXIS1 × NAXIS2 × NAXIS3 × bytes does not fit in memory sizes: a corrupt header.
  case dimensionsTooLarge
}

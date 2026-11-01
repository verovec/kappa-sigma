/// What a scan warning or an error sheet prints: a sentence, never the Swift dump
/// `FITSFileError(path: …, reason: ImageKit.FITSError.nonASCIIHeader)`.
extension FITSError: CustomStringConvertible {
  package var description: String {
    switch self {
    case .noHeaderEnd: "not a FITS file (its header never ends)"
    case .nonASCIIHeader: "not a FITS file (its header is not text)"
    case .missingCard(let keyword): "the header has no valid \(keyword) card"
    case .truncatedData: "the image data is shorter than its header says"
    case .unsupportedBitpix(let bitpix): "BITPIX \(bitpix) is not supported"
    case .unsupportedPlaneCount(let planes): "\(planes) image planes are not supported (1 or 3)"
    case .dimensionMismatch: "the image does not have the dimensions of its header"
    case .dimensionsTooLarge: "the header's dimensions are too large (a corrupt header)"
    }
  }
}

extension FITSFileError: CustomStringConvertible {
  package var description: String { "\(path): \(reason)" }
}

/// What the header says about an image, for display and for choosing processes.
package struct ImageMetadata: Equatable, Sendable {
  /// `FILTER`, trimmed.
  package var filter: String?
  /// `INSTRUME`, trimmed.
  package var camera: String?
  /// `GAIN`.
  package var gain: Double?
  /// `EXPTIME` (or `EXPOSURE`), in seconds.
  package var exposureSeconds: Double?
  /// `BAYERPAT` for a raw colour frame (`RGGB`…).
  package var bayerPattern: String?
  /// `OBJECT`, trimmed.
  package var object: String?
  /// The order rows are stored in; pixels are kept in that order.
  package var rowOrder: RowOrder
  /// The TAN plate solution, when the header has one.
  package var wcs: WCS?

  /// The metadata of an image without a FITS header (a PNG or TIFF): rows in `rowOrder`, nothing
  /// else known.
  package init(rowOrder: RowOrder) {
    self.rowOrder = rowOrder
  }

  /// Metadata read from `header`.
  package init(header: FITSHeader) {
    filter = header.string("FILTER")
    camera = header.string("INSTRUME")
    gain = header.double("GAIN")
    exposureSeconds = header.double("EXPTIME") ?? header.double("EXPOSURE")
    bayerPattern = header.string("BAYERPAT")
    object = header.string("OBJECT")
    rowOrder = header.string("ROWORDER")?.uppercased() == "TOP-DOWN" ? .topDown : .bottomUp
    wcs = WCS(header: header)
  }
}

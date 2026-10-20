/// The order of rows in a FITS data unit (`ROWORDER` card).
package enum RowOrder: Equatable, Sendable {
  /// Row 0 is the top of the frame (`ROWORDER = 'TOP-DOWN'`, what Siril writes).
  case topDown
  /// Row 0 is the bottom of the frame: the FITS default when the card is absent.
  case bottomUp
}

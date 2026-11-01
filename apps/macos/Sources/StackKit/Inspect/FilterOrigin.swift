/// Where a light filter came from (card 0163), and the text it was read from: the import row
/// shows it next to the picker (R2: the verdict and its reason are visible, the picker wins).
package struct FilterOrigin: Equatable, Sendable {
  /// The fallback that named the filter, in the scan's order.
  package enum Source: Sendable, CaseIterable {
    /// The FITS `FILTER` card.
    case header
    /// The file name (`…_filter-OIII_…`).
    case fileName
    /// A parent folder's name.
    case folder
    /// An `info.txt` legend.
    case manifest
    /// The physical filter-wheel slot (SharpCap sidecar or name).
    case wheelSlot
    /// Wheel-order detection on the signal.
    case signal
    /// The user's filter mapping.
    case manual
  }

  package var source: Source
  /// What named it: the card or file-name token as written (`H-alpha 7nm`), the folder
  /// (`SII_300s`), the legend token (`info.txt` legends are split from glued words, so the token is
  /// already a filter), the slot number (or a sidecar's alias), the mapped-from filter; `""` for
  /// the signal.
  package var raw: String

  package init(source: Source, raw: String) {
    self.source = source
    self.raw = raw
  }
}

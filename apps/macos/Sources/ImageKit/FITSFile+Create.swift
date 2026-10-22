package import Foundation

extension FITSFile {
  /// Cards describing the data unit (its layout, or values computed from its pixels): never
  /// copied, since the new file's data differs — a stale CHECKSUM makes readers call it corrupt.
  private static let structural: Set<String> = [
    "SIMPLE", "BITPIX", "NAXIS", "NAXIS1", "NAXIS2", "NAXIS3", "EXTEND", "BZERO", "BSCALE",
    "BLANK", "PCOUNT", "GCOUNT", "END", "CHECKSUM", "DATASUM", "DATAMIN", "DATAMAX",
  ]

  /// Writes `image` as a new float32 FITS at `url`, atomically.
  ///
  /// Fresh structural cards, then every descriptive card of `header` (object, exposure, WCS, ROWORDER… — a history step keeps
  /// what its source said). Without a `ROWORDER` card, the image's row order is written.
  package static func create(_ image: AstroImage, keeping header: FITSHeader?, at url: URL) throws {
    var cards = [
      card("SIMPLE", "T"), card("BITPIX", "-32"), card("NAXIS", image.planes.count > 1 ? "3" : "2"),
      card("NAXIS1", "\(image.width)"), card("NAXIS2", "\(image.height)"),
    ]
    if image.planes.count > 1 { cards.append(card("NAXIS3", "\(image.planes.count)")) }
    let kept = header?.cards.filter { !structural.contains($0.keyword) } ?? []
    cards += kept
    if !kept.contains(where: { $0.keyword == "ROWORDER" }) {
      cards.append(
        card("ROWORDER", image.metadata.rowOrder == .topDown ? "'TOP-DOWN'" : "'BOTTOM-UP'"))
    }
    try Self(header: FITSHeader(cards: cards), body: Data(), path: nil).write(image, to: url)
  }

  private static func card(_ keyword: String, _ value: String) -> FITSHeader.Card {
    FITSHeader.Card(keyword: keyword, value: value)
  }
}

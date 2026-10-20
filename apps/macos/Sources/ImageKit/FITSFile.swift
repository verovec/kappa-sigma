package import Foundation

/// A FITS file's primary HDU: its header and data unit, as the legacy reader handles them
/// (`../stacking-astro/internal/fits/data.go`): BITPIX −32/−64/32/16/8, NAXIS3 of 1 or 3, value =
/// BZERO + BSCALE · stored computed in double then rounded to float32, rows kept in file order.
package struct FITSFile: Sendable {
  /// FITS blocks are 2880 bytes; cards are 80.
  static let block = 2880
  static let cardLength = 80

  /// The primary header.
  package let header: FITSHeader
  /// Everything after the header: the data unit, its padding and any extension, kept so a
  /// rewrite of an unchanged image is byte-identical.
  let body: Data
  /// The file read, when there is one: every error names it.
  let path: String?

  /// Reads the file at `url` (memory-mapped; `write` replaces files atomically, so a mapping
  /// is never truncated under a reader).
  package static func read(at url: URL) throws -> Self {
    try withPath(url.path) {
      let file = try parse(Data(contentsOf: url, options: .mappedIfSafe))
      return Self(header: file.header, body: file.body, path: url.path)
    }
  }

  /// Splits `data` (any slice) into header cards and body.
  package static func parse(_ data: Data) throws -> Self {
    var cards: [FITSHeader.Card] = []
    var offset = data.startIndex
    while offset + cardLength <= data.endIndex {
      // FITS headers are ASCII (FITS 4.0 §4.1.1): anything else is not a FITS file.
      guard let raw = String(bytes: data[offset..<offset + cardLength], encoding: .ascii) else {
        throw FITSError.nonASCIIHeader
      }
      offset += cardLength
      if raw.hasPrefix("END") && raw.dropFirst(3).allSatisfy({ $0 == " " }) {
        let consumed = offset - data.startIndex
        let start = min(data.startIndex + consumed + padding(consumed), data.endIndex)
        return Self(header: FITSHeader(cards: cards), body: data[start...], path: nil)
      }
      cards.append(FITSHeader.Card(raw: raw))
    }
    throw FITSError.noHeaderEnd
  }

  /// Decodes the data unit into planes of physical values.
  package func image() throws -> AstroImage {
    try Self.withPath(path) {
      let layout = try FITSLayout(header: header)
      guard body.count >= layout.dataBytes else { throw FITSError.truncatedData }
      return AstroImage(
        width: layout.width, height: layout.height,
        planes: FITSDecoder.decode(body, layout: layout),
        metadata: ImageMetadata(header: header))
    }
  }

  /// Writes `image` as float32 with this file's header cards, unchanged.
  ///
  /// Stores (value − BZERO) / BSCALE so a re-read gives the values back: an unchanged image from
  /// a float32 file gives the same bytes (extensions kept). Replaces `url` atomically.
  package func write(_ image: AstroImage, to url: URL) throws {
    try Self.withPath(url.path) {
      let layout = try FITSLayout(header: header)
      guard layout.bitpix == -32 else { throw FITSError.unsupportedBitpix(layout.bitpix) }
      let plane = layout.width * layout.height
      guard image.width == layout.width, image.height == layout.height,
        image.planes.count == layout.planes, image.planes.allSatisfy({ $0.count == plane })
      else { throw FITSError.dimensionMismatch }
      var out = Data(capacity: Self.block + layout.dataBytes + body.count)
      var text = header.cards.map(\.raw).joined() + "END" + String(repeating: " ", count: 77)
      text += String(repeating: " ", count: Self.padding(text.utf8.count))
      out.append(contentsOf: Array(text.utf8))
      out.append(
        FITSDecoder.encodeFloat32(image.planes, bzero: layout.bzero, bscale: layout.bscale))
      out.append(Data(count: Self.padding(layout.dataBytes)))
      let unitEnd = layout.dataBytes + Self.padding(layout.dataBytes)
      if body.count > unitEnd { out.append(body[(body.startIndex + unitEnd)...]) }
      try out.write(to: url, options: .atomic)
    }
  }

  /// Bytes needed to reach the next block boundary.
  static func padding(_ count: Int) -> Int { (block - count % block) % block }

  /// Runs `body`, naming `path` in any `FITSError` it throws.
  static func withPath<T>(_ path: String?, _ body: () throws -> T) throws -> T {
    do {
      return try body()
    } catch let error as FITSError {
      guard let path else { throw error }
      throw FITSFileError(path: path, reason: error)
    }
  }
}

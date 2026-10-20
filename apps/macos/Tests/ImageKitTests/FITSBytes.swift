import Foundation

/// Builds FITS files byte by byte from the standard (2880-byte blocks, 80-char cards, big-endian
/// data), independently of ImageKit's writer, so reader tests do not test the code against itself.
enum FITSBytes {
  static func card(_ key: String, _ value: String) -> String {
    let text = key.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + value
    return text.padding(toLength: 80, withPad: " ", startingAt: 0)
  }

  static func header(_ cards: [String]) -> Data {
    var text = cards.joined() + "END".padding(toLength: 80, withPad: " ", startingAt: 0)
    while text.utf8.count % 2880 != 0 { text += " " }
    return Data(text.utf8)
  }

  /// A float32 image: `planes[c][y * width + x]`, rows in file order.
  static func float32(
    width: Int, height: Int, planes: [[Float]], extra: [String] = []
  ) -> Data {
    var cards = [
      card("SIMPLE", "T"), card("BITPIX", "-32"), card("NAXIS", planes.count == 1 ? "2" : "3"),
      card("NAXIS1", "\(width)"), card("NAXIS2", "\(height)"),
    ]
    if planes.count > 1 { cards.append(card("NAXIS3", "\(planes.count)")) }
    cards += [card("BZERO", "0"), card("BSCALE", "1")] + extra
    var data = Data()
    for value in planes.joined() {
      withUnsafeBytes(of: value.bitPattern.bigEndian) { data.append(contentsOf: $0) }
    }
    return header(cards) + padded(data)
  }

  /// A 16-bit image with BZERO/BSCALE; raw values are the stored signed integers.
  static func int16(
    width: Int, height: Int, raw: [Int16], bzero: String = "32768", bscale: String = "1"
  ) -> Data {
    let cards = [
      card("SIMPLE", "T"), card("BITPIX", "16"), card("NAXIS", "2"), card("NAXIS1", "\(width)"),
      card("NAXIS2", "\(height)"), card("BZERO", bzero), card("BSCALE", bscale),
    ]
    var data = Data()
    for value in raw {
      withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }
    return header(cards) + padded(data)
  }

  /// An 8-bit image (unsigned bytes).
  static func uint8(width: Int, height: Int, raw: [UInt8]) -> Data {
    let cards = [
      card("SIMPLE", "T"), card("BITPIX", "8"), card("NAXIS", "2"), card("NAXIS1", "\(width)"),
      card("NAXIS2", "\(height)"),
    ]
    return header(cards) + padded(Data(raw))
  }

  static func padded(_ data: Data) -> Data {
    var out = data
    while out.count % 2880 != 0 { out.append(0) }
    return out
  }
}

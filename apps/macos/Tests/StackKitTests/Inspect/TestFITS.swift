import Foundation

/// 16-bit FITS frames for inspect tests, the shape the legacy `fitstest` helper writes: BZERO 32768,
/// physical values 0…65535, card values already FITS-formatted (`'Ha'` quoted, numbers bare).
/// Built from the standard, never with ImageKit's writer.
enum TestFITS {
  /// Writes `dir/relative` (folders created) with every pixel `pixel`; returns its URL.
  @discardableResult
  static func write(
    _ relative: String, in dir: URL, width: Int = 8, height: Int = 8, pixel: UInt16 = 500,
    cards: [String: String]
  ) throws -> URL {
    try write(
      relative, in: dir, width: width, height: height,
      planes: [[UInt16](repeating: pixel, count: width * height)], cards: cards)
  }

  /// Writes a 1- or 3-plane frame from physical values, `planes[c][y * width + x]`.
  @discardableResult
  static func write(
    _ relative: String, in dir: URL, width: Int, height: Int, planes: [[UInt16]],
    cards: [String: String]
  ) throws -> URL {
    let url = dir.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var data = header(width: width, height: height, planes: planes.count, cards: cards)
    var body = Data(capacity: width * height * planes.count * 2)
    for value in planes.joined() {
      let stored = UInt16(bitPattern: Int16(Int32(value) - 32768))
      withUnsafeBytes(of: stored.bigEndian) { body.append(contentsOf: $0) }
    }
    while body.count % 2880 != 0 { body.append(0) }
    data.append(body)
    try data.write(to: url)
    return url
  }

  /// A padded primary header; extra cards sorted by keyword so files are reproducible.
  static func header(width: Int, height: Int, planes: Int, cards: [String: String]) -> Data {
    var base = [("SIMPLE", "T"), ("BITPIX", "16"), ("NAXIS", planes > 1 ? "3" : "2")]
    base += [("NAXIS1", "\(width)"), ("NAXIS2", "\(height)")]
    if planes > 1 { base.append(("NAXIS3", "\(planes)")) }
    base += [("BZERO", "32768"), ("BSCALE", "1")]
    base += cards.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    var text = base.map { card($0.0, $0.1) }.joined()
    text += "END".padding(toLength: 80, withPad: " ", startingAt: 0)
    while text.utf8.count % 2880 != 0 { text += " " }
    return Data(text.utf8)
  }

  static func card(_ key: String, _ value: String) -> String {
    let text = key.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + value
    return String(text.prefix(80)).padding(toLength: 80, withPad: " ", startingAt: 0)
  }
}

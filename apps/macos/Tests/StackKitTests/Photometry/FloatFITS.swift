import Foundation

/// Float32 FITS frames for photometry tests, written from the standard (BITPIX −32, BZERO 0,
/// BSCALE 1: what Siril's calibrated frames are and what the normaliser may rewrite).
enum FloatFITS {
  @discardableResult
  static func write(_ url: URL, width: Int, height: Int, planes: [[Float]]) throws -> URL {
    var cards = [
      TestFITS.card("SIMPLE", "T"), TestFITS.card("BITPIX", "-32"),
      TestFITS.card("NAXIS", planes.count > 1 ? "3" : "2"), TestFITS.card("NAXIS1", "\(width)"),
      TestFITS.card("NAXIS2", "\(height)"),
    ]
    if planes.count > 1 { cards.append(TestFITS.card("NAXIS3", "\(planes.count)")) }
    cards += [TestFITS.card("BZERO", "0"), TestFITS.card("BSCALE", "1")]
    var text = cards.joined() + "END".padding(toLength: 80, withPad: " ", startingAt: 0)
    while text.utf8.count % 2880 != 0 { text += " " }
    var data = Data(text.utf8)
    for value in planes.joined() {
      withUnsafeBytes(of: value.bitPattern.bigEndian) { data.append(contentsOf: $0) }
    }
    while data.count % 2880 != 0 { data.append(0) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    return url
  }
}

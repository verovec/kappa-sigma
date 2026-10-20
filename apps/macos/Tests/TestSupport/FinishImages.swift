package import Foundation
internal import Accelerate
internal import ImageIO
internal import UniformTypeIdentifiers

/// Reading the finishing oracle's images: sizes, and how far a render is from a deliverable.
package enum FinishImages {
  /// FITS extensions, compared case-insensitively.
  static let fitsExtensions: Set<String> = ["fit", "fits", "fts"]

  /// Width and height: NAXIS1/NAXIS2 of a FITS header, or the image's size.
  package static func dimensions(of url: URL) throws -> (width: Int, height: Int) {
    if fitsExtensions.contains(url.pathExtension.lowercased()) {
      let bytes = try FileHandle(forReadingFrom: url).read(upToCount: 2880) ?? Data()
      let header = String(bytes: bytes, encoding: .ascii) ?? ""
      func value(_ key: String) -> Int {
        let cards = stride(from: 0, to: header.count, by: 80).map {
          header.dropFirst($0).prefix(80)
        }
        let card = cards.first {
          $0.hasPrefix(key.padding(toLength: 8, withPad: " ", startingAt: 0))
        }
        return Int(
          card?.dropFirst(10).split(separator: "/").first?.trimmingCharacters(in: .whitespaces)
            ?? "") ?? 0
      }
      return (value("NAXIS1"), value("NAXIS2"))
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { throw FinishOracleError.unreadable(url.path) }
    return (
      properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
      properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    )
  }

  /// Mean and largest |Δ| of the RGB samples of two images of the same size, as fractions of full
  /// scale (16-bit reads: 1/255 is 257 levels).
  package static func difference(_ first: URL, _ second: URL) throws -> (
    meanAbs: Double, maxAbs: Double
  ) {
    let (one, two) = (try samples(first), try samples(second))
    guard one.width == two.width, one.height == two.height else {
      throw FinishOracleError.unreadable(
        "\(first.lastPathComponent) ≠ \(second.lastPathComponent) in size")
    }
    // vDSP over RGBA: alpha is opaque in both, so it adds nothing to the sum or the maximum.
    let deltas = vDSP.absolute(
      vDSP.subtract(
        vDSP.integerToFloatingPoint(one.values, floatingPointType: Float.self),
        vDSP.integerToFloatingPoint(two.values, floatingPointType: Float.self)))
    let count = Double(one.width * one.height * 3)
    return (Double(vDSP.sum(deltas)) / count / 65535, Double(vDSP.maximum(deltas)) / 65535)
  }

  /// RGBA, 16 bits per channel, in sRGB.
  private static func samples(_ url: URL) throws -> (width: Int, height: Int, values: [UInt16]) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw FinishOracleError.unreadable(url.path) }
    let (width, height) = (image.width, image.height)
    var values = [UInt16](repeating: 0, count: width * height * 4)
    let info =
      CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
    guard
      let context = CGContext(
        data: &values, width: width, height: height, bitsPerComponent: 16,
        bytesPerRow: width * 8, space: space, bitmapInfo: info)
    else { throw FinishOracleError.unreadable(url.path) }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, values)
  }

  /// Writes a grey 8-bit PNG (tests of `verify`).
  package static func writeTestPNG(width: Int, height: Int, value: UInt8 = 128, to url: URL) throws
  {
    var pixels = [UInt8](repeating: value, count: width * height)
    guard
      let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
      let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw FinishOracleError.unreadable(url.path) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw FinishOracleError.unreadable(url.path)
    }
  }
}

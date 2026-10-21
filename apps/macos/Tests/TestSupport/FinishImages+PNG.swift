package import Foundation
internal import ImageIO
internal import UniformTypeIdentifiers

extension FinishImages {
  /// Writes three planes in [0, 1] as a 16-bit sRGB PNG, quantised like astrocomp's `rgba16`
  /// (v · 65535 + 0.5, clamped); `bottomUp` planes (FITS file order) are flipped to the top-down
  /// rows a PNG stores, as astrocomp does.
  package static func writePNG16(
    planes: [[Float]], width: Int, height: Int, bottomUp: Bool, to url: URL
  ) throws {
    guard planes.count == 3, planes.allSatisfy({ $0.count == width * height }) else {
      throw FinishOracleError.unreadable(
        "\(url.lastPathComponent): needs 3 planes of \(width)×\(height)")
    }
    var samples = [UInt16](repeating: 0, count: width * height * 3)
    for y in 0..<height {
      let source = bottomUp ? height - 1 - y : y
      for x in 0..<width {
        for channel in 0..<3 {
          let value = planes[channel][source * width + x]
          samples[(y * width + x) * 3 + channel] =
            value <= 0 ? 0 : value >= 1 ? 65535 : UInt16(value * 65535 + 0.5)
        }
      }
    }
    let data = samples.withUnsafeBytes { Data($0) } as CFData
    guard let provider = CGDataProvider(data: data),
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48,
        bytesPerRow: width * 6, space: space,
        bitmapInfo: CGBitmapInfo(
          rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw FinishOracleError.unreadable(url.path) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw FinishOracleError.unreadable(url.path)
    }
  }
}

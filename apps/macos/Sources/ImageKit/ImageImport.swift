internal import Accelerate
internal import CoreGraphics
package import Foundation
internal import ImageIO

/// Reading a display-referred PNG or TIFF (a StarNet starless, a deliverable) into float planes.
///
/// The inverse of `ImageExport`: samples are read at 16 bits in sRGB (gray for a one-channel
/// file) and divided by 65535; rows are top-down, as the file stores them.
package enum ImageImport {
  /// Why a file could not be read.
  package enum ImportError: Error, Equatable, Sendable {
    /// ImageIO could not decode it.
    case unreadable(path: String)
  }

  /// The image at `url`: one plane for a gray file, three otherwise (alpha dropped).
  package static func read(at url: URL) throws -> AstroImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw ImportError.unreadable(path: url.path) }
    let gray = image.colorSpace?.model == .monochrome
    let (width, height) = (image.width, image.height)
    // Gray reads one 16-bit sample per pixel; colour reads RGBX (CoreGraphics has no 48-bit RGB
    // context), the fourth sample ignored.
    let stride = gray ? 1 : 4
    var samples = [UInt16](repeating: 0, count: width * height * stride)
    let space = CGColorSpace(name: gray ? CGColorSpace.genericGrayGamma2_2 : CGColorSpace.sRGB)
    let alpha = gray ? CGImageAlphaInfo.none : CGImageAlphaInfo.noneSkipLast
    let info = alpha.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
    let drawn = samples.withUnsafeMutableBytes { bytes -> Bool in
      guard let space,
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 16,
          bytesPerRow: width * stride * 2, space: space, bitmapInfo: info)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw ImportError.unreadable(path: url.path) }
    let count = width * height
    let planes = (0..<(gray ? 1 : 3)).map { channel in
      [Float](unsafeUninitializedCapacity: count) { plane, initialized in
        guard let target = plane.baseAddress else { return }
        samples.withUnsafeBufferPointer { source in
          guard let base = source.baseAddress else { return }
          // The strided channel to float, then to [0, 1]: ImageExport's vDSP_vfixru16 reversed.
          vDSP_vfltu16(base + channel, vDSP_Stride(stride), target, 1, vDSP_Length(count))
        }
        var scale: Float = 65535
        vDSP_vsdiv(target, 1, &scale, target, 1, vDSP_Length(count))
        initialized = count
      }
    }
    return AstroImage(
      width: width, height: height, planes: planes,
      metadata: ImageMetadata(rowOrder: .topDown))
  }
}

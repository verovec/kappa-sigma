internal import Accelerate
internal import CoreGraphics
package import Foundation
internal import ImageIO
internal import UniformTypeIdentifiers

/// 16-bit TIFF / PNG export of an image, for deliverables (display-referred values in [0, 1]).
///
/// Export only: pixels for processing stay float32 FITS. Rows are written top first, so a
/// bottom-up FITS is flipped here, at the boundary, never in the planes.
package enum ImageExport {
  /// A 16-bit output format.
  package enum Format: Sendable {
    /// 16-bit TIFF.
    case tiff16
    /// 16-bit PNG.
    case png16

    /// The file name extension.
    package var fileExtension: String { self == .tiff16 ? "tif" : "png" }
    var type: UTType { self == .tiff16 ? .tiff : .png }
  }

  /// Why an export failed.
  package enum ExportError: Error, Equatable, Sendable {
    /// Only 1 (gray) and 3 (RGB) planes export.
    case unsupportedPlaneCount(Int)
    /// ImageIO refused to build or write the image.
    case imageIOFailed(path: String)
    /// A plane does not hold width × height values.
    case planeSizeMismatch
  }

  /// Writes `image` to `url`; values outside [0, 1] clamp, NaN exports as 0.
  ///
  /// Display-referred: RGB is tagged sRGB, mono a gamma-2.2 gray (never linear gray, which
  /// viewers would brighten).
  package static func write(_ image: AstroImage, to url: URL, format: Format) throws {
    let channels = image.planes.count
    guard channels == 1 || channels == 3 else {
      throw ExportError.unsupportedPlaneCount(channels)
    }
    guard image.planes.allSatisfy({ $0.count == image.width * image.height }) else {
      throw ExportError.planeSizeMismatch
    }
    let space =
      channels == 3
      ? CGColorSpace(name: CGColorSpace.sRGB) : CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
    let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
      .union(.byteOrder16Little)
    let data = interleave(image) as CFData
    guard let space, let provider = CGDataProvider(data: data),
      let cgImage = CGImage(
        width: image.width, height: image.height, bitsPerComponent: 16,
        bitsPerPixel: 16 * channels, bytesPerRow: 2 * channels * image.width, space: space,
        bitmapInfo: bitmap, provider: provider, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, format.type.identifier as CFString, 1, nil)
    else { throw ExportError.imageIOFailed(path: url.path) }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw ExportError.imageIOFailed(path: url.path)
    }
  }

  /// Planes → interleaved native (little-endian) UInt16 samples, top row first, written straight
  /// into the buffer ImageIO reads: per row and channel, clip and scale with vDSP, then
  /// round-convert into the interleaved slot (stride = channel count).
  private static func interleave(_ image: AstroImage) -> Data {
    let width = image.width
    let channels = image.planes.count
    var data = Data(count: width * image.height * channels * 2)
    var row = [Float](repeating: 0, count: width)
    data.withUnsafeMutableBytes { raw in
      guard let samples = raw.bindMemory(to: UInt16.self).baseAddress else { return }
      for (channel, plane) in image.planes.enumerated() {
        plane.withUnsafeBufferPointer { source in
          guard let base = source.baseAddress else { return }
          for y in 0..<image.height {
            let from = image.metadata.rowOrder == .topDown ? y : image.height - 1 - y
            convert(base + from * width, into: &row, width: width)
            vDSP_vfixru16(
              row, 1, samples + y * width * channels + channel, channels, vDSP_Length(width))
          }
        }
      }
    }
    return data
  }

  /// One row: NaN → 0, clip to [0, 1], scale to 65535.
  private static func convert(_ source: UnsafePointer<Float>, into row: inout [Float], width: Int) {
    var low: Float = 0
    var high: Float = 1
    var scale: Float = 65535
    row.withUnsafeMutableBufferPointer { out in
      guard let target = out.baseAddress else { return }
      vDSP_vclip(source, 1, &low, &high, target, 1, vDSP_Length(width))
      // vDSP_vclip passes NaN through; the export defines it as 0 rather than relying on how the
      // integer conversion treats NaN on this CPU.
      for index in 0..<width where target[index].isNaN {
        target[index] = 0
      }
      vDSP_vsmul(target, 1, &scale, target, 1, vDSP_Length(width))
    }
  }
}

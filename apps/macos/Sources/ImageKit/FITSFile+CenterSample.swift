internal import Foundation

extension FITSFile {
  /// Up to `maxCount` contiguous physical values from the middle of the data unit (all planes in
  /// file order), computed as BZERO + BSCALE · stored in double: the legacy `fits.File.Stats` read,
  /// which classifies frames without decoding the whole image. `maxCount` ≤ 0 or larger than the
  /// image reads every value.
  package func centerSample(maxCount: Int) throws -> [Double] {
    try Self.withPath(path) {
      let layout = try FITSLayout(header: header)
      let total = layout.width * layout.height * layout.planes
      let count = maxCount <= 0 || maxCount > total ? total : maxCount
      let start = (total - count) / 2
      let size = layout.bytesPerValue
      guard body.count >= (start + count) * size else { throw FITSError.truncatedData }
      return body.withUnsafeBytes { raw -> [Double] in
        guard let base = raw.baseAddress else { return [] }
        let first = base + start * size
        return (0..<count).map { index in
          layout.bzero + layout.bscale * Self.stored(first + index * size, bitpix: layout.bitpix)
        }
      }
    }
  }

  /// One big-endian stored value as a double.
  static func stored(_ bytes: UnsafeRawPointer, bitpix: Int) -> Double {
    switch bitpix {
    case 16: Double(Int16(bigEndian: bytes.loadUnaligned(as: Int16.self)))
    case 32: Double(Int32(bigEndian: bytes.loadUnaligned(as: Int32.self)))
    case -32: Double(Float(bitPattern: UInt32(bigEndian: bytes.loadUnaligned(as: UInt32.self))))
    case -64: Double(bitPattern: UInt64(bigEndian: bytes.loadUnaligned(as: UInt64.self)))
    default: Double(bytes.load(as: UInt8.self))
    }
  }
}

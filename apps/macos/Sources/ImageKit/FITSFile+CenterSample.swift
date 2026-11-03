internal import Foundation

extension FITSFile {
  /// Up to `maxCount` contiguous physical values from the middle of the data unit (all planes in
  /// file order), computed as BZERO + BSCALE · stored in double: the legacy `fits.File.Stats` read,
  /// which classifies frames without decoding the whole image. `maxCount` ≤ 0 or larger than the
  /// image reads every value.
  package func centerSample(maxCount: Int) throws -> [Double] {
    try Self.withPath(path) {
      let run = try Self.centerRun(of: header, maxCount: maxCount)
      let start = body.startIndex + run.first * run.bytesPerValue
      let end = start + run.count * run.bytesPerValue
      guard body.endIndex >= end else { throw FITSError.truncatedData }
      return try Self.physicalValues(body[start..<end], header: header)
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

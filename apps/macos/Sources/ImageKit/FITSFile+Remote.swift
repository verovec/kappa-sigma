package import Foundation

// MARK: - Reading a FITS file in pieces (card 0167: a frame on S3, read by ranges)

extension FITSFile {
  /// The bytes the primary header of `header` occupies on disk, padded to a 2880-byte block: the
  /// data unit starts there (`header` as `parse` returns it, its `END` card not counted).
  package static func headerBytes(of header: FITSHeader) -> Int {
    let consumed = (header.cards.count + 1) * cardLength
    return consumed + padding(consumed)
  }

  /// Where the centred run of up to `maxCount` values lies in the data unit of `header`: its
  /// first value, its count, the image's total value count and the bytes of one value — the run
  /// `centerSample(maxCount:)` reads. `maxCount` ≤ 0 or larger than the image is every value.
  package static func centerRun(of header: FITSHeader, maxCount: Int) throws -> FITSCenterRun {
    let layout = try FITSLayout(header: header)
    let total = layout.width * layout.height * layout.planes
    let count = maxCount <= 0 || maxCount > total ? total : maxCount
    return FITSCenterRun(
      first: (total - count) / 2, count: count, total: total, bytesPerValue: layout.bytesPerValue)
  }

  /// The physical values of the stored bytes `bytes`, in the data unit of `header`.
  ///
  /// BZERO + BSCALE · stored, as `centerSample` computes them.
  package static func physicalValues(_ bytes: Data, header: FITSHeader) throws -> [Double] {
    let layout = try FITSLayout(header: header)
    let size = layout.bytesPerValue
    return bytes.withUnsafeBytes { raw -> [Double] in
      guard let base = raw.baseAddress else { return [] }
      return (0..<(raw.count / size)).map { index in
        layout.bzero + layout.bscale * stored(base + index * size, bitpix: layout.bitpix)
      }
    }
  }
}

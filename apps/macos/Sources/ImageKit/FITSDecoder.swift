internal import Foundation

/// Big-endian FITS values ↔ native floats.
enum FITSDecoder {
  /// The data unit as planes of physical floats.
  ///
  /// Decoded straight into each plane (no concatenated copy); the BITPIX choice is made once
  /// per plane, not per pixel.
  static func decode(_ body: Data, layout: FITSLayout) -> [[Float]] {
    let count = layout.width * layout.height
    let bytesPerPlane = count * layout.bytesPerValue
    return body.withUnsafeBytes { raw -> [[Float]] in
      guard let base = raw.baseAddress else { return [] }
      return (0..<layout.planes).map { plane in
        let bytes = base + plane * bytesPerPlane
        return [Float](unsafeUninitializedCapacity: count) { out, initialized in
          fill(out, from: bytes, count: count, layout: layout)
          initialized = count
        }
      }
    }
  }

  private static func fill(
    _ out: UnsafeMutableBufferPointer<Float>, from bytes: UnsafeRawPointer, count: Int,
    layout: FITSLayout
  ) {
    // Double first, then float32: the legacy reader's arithmetic, bit for bit.
    let zero = layout.bzero
    let scale = layout.bscale
    switch layout.bitpix {
    case -32 where zero == 0 && scale == 1:
      for index in 0..<count {
        out[index] = Float(
          bitPattern: UInt32(
            bigEndian: bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
      }
    case -32:
      for index in 0..<count {
        let stored = Float(
          bitPattern: UInt32(
            bigEndian: bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
        out[index] = Float(zero + scale * Double(stored))
      }
    case -64:
      for index in 0..<count {
        let stored = Double(
          bitPattern: UInt64(
            bigEndian: bytes.loadUnaligned(fromByteOffset: index * 8, as: UInt64.self)))
        out[index] = Float(zero + scale * stored)
      }
    case 32:
      for index in 0..<count {
        let stored = Int32(
          bigEndian: bytes.loadUnaligned(fromByteOffset: index * 4, as: Int32.self))
        out[index] = Float(zero + scale * Double(stored))
      }
    case 16:
      for index in 0..<count {
        let stored = Int16(
          bigEndian: bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
        out[index] = Float(zero + scale * Double(stored))
      }
    default:
      for index in 0..<count {
        out[index] = Float(zero + scale * Double(bytes.load(fromByteOffset: index, as: UInt8.self)))
      }
    }
  }

  /// Planes as big-endian float32 bytes of (value − BZERO) / BSCALE.
  static func encodeFloat32(_ planes: [[Float]], bzero: Double, bscale: Double) -> Data {
    let count = planes.reduce(0) { $0 + $1.count }
    let identity = bzero == 0 && bscale == 1
    var data = Data(count: count * 4)
    data.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      for plane in planes {
        for value in plane {
          let stored = identity ? value : Float((Double(value) - bzero) / bscale)
          base.storeBytes(of: stored.bitPattern.bigEndian, toByteOffset: offset, as: UInt32.self)
          offset += 4
        }
      }
    }
    return data
  }
}

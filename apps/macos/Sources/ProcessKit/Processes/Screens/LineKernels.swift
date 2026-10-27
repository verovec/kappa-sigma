package import Metal

/// Swift mirror of `Shaders/Lines.h` — the header is the definition; `LinesHeaderTests` pins the
/// slot count and the layouts.
///
/// The injection and screen kernels loop over the lines bound, in canonical order; a line that
/// would change no pixel is not bound (card 0136).
package enum LineKernels {
  /// `MAX_LINES`: the line slots of each kernel.
  package static let maxLines = 8

  /// `InjectLine`: what one line adds per unit of excess to each base plane, its continuum scale
  /// and black point.
  package struct InjectLine: BitwiseCopyable {
    package var weight: (Float, Float, Float)
    package var k: Float
    package var black: Float

    package init(weight: (Float, Float, Float), k: Float, black: Float) {
      (self.weight, self.k, self.black) = (weight, k, black)
    }
  }

  /// `ScreenLine`: one line's opacity · blend and tint.
  package struct ScreenLine: BitwiseCopyable {
    package var alpha: Float
    package var tint: (Float, Float, Float)

    package init(alpha: Float, tint: (Float, Float, Float)) {
      (self.alpha, self.tint) = (alpha, tint)
    }
  }

  /// Refuses more bound lines than the kernels have slots, before any layer is read.
  package static func checkSlots(_ count: Int) throws {
    guard count <= maxLines else {
      throw ProcessError.invalidParameter("more than \(maxLines) lines")
    }
  }

  /// Binds `textures` from texture index `first` on, padding the `slots` left with `padding`, the
  /// per-line `values` at buffer 0 and their count at buffer 1.
  package static func bind<Value: BitwiseCopyable>(
    _ textures: [MTLTexture], slots: Int, from first: Int, padding: MTLTexture,
    values: [Value], encoder: MTLComputeCommandEncoder
  ) {
    for slot in 0..<slots {
      encoder.setTexture(slot < textures.count ? textures[slot] : padding, index: first + slot)
    }
    // setBytes needs bytes even with no line bound (count 0: the kernel copies the base).
    if values.isEmpty {
      var zero = [UInt8](repeating: 0, count: MemoryLayout<Value>.stride)
      unsafe encoder.setBytes(&zero, length: zero.count, index: 0)
    } else {
      var values = values
      unsafe encoder.setBytes(
        &values, length: values.count * MemoryLayout<Value>.stride, index: 0)
    }
    var count = UInt32(values.count)
    unsafe encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 1)
  }
}

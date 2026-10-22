package import ImageKit

/// A strided sample of the head's planes (card 0089): the panel's input histogram and its
/// clipping readouts, measured for display only (R2: no process reads them).
package struct HeadSample: Equatable, Sendable {
  /// What a transfer sends to black and to white, as fractions of a channel's sample.
  package struct Clipping: Equatable, Sendable {
    /// At or below 0.
    package let low: Double
    /// At or above 1.
    package let high: Double
  }

  /// Bins per channel, over [0, 1].
  package static let binCount = 256
  /// Samples per channel at most (a stride above that).
  package static let limit = 1 << 20

  /// Each channel's finite sampled values.
  package let planes: [[Float]]
  /// Each channel's counts over [0, 1] (values outside fall in the end bins).
  package let bins: [[Int]]

  /// The sample of `image`.
  package init(_ image: AstroImage) {
    let count = image.planes.first?.count ?? 0
    let stride = max(1, count / Self.limit)
    planes = image.planes.map { plane in
      Swift.stride(from: 0, to: plane.count, by: stride).map { plane[$0] }.filter(\.isFinite)
    }
    bins = planes.map { plane in
      var counts = [Int](repeating: 0, count: Self.binCount)
      for value in plane {
        let bin = Int((min(max(value, 0), 1) * Float(Self.binCount)).rounded(.down))
        counts[min(bin, Self.binCount - 1)] += 1
      }
      return counts
    }
  }

  /// The share of each channel `transfer(value, channel)` sends to 0 or below and 1 or above.
  package func clipping(_ transfer: (Double, Int) -> Double) -> [Clipping] {
    planes.enumerated().map { channel, plane in
      guard !plane.isEmpty else { return Clipping(low: 0, high: 0) }
      var (low, high) = (0, 0)
      for value in plane {
        let mapped = transfer(Double(value), channel)
        if mapped <= 0 { low += 1 } else if mapped >= 1 { high += 1 }
      }
      let total = Double(plane.count)
      return Clipping(low: Double(low) / total, high: Double(high) / total)
    }
  }
}

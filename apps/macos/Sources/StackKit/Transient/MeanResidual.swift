/// The coverage-aware mean residual (`meanAccum`).
///
/// A frame counts at a pixel only where it has data, so rotated zero-fill borders do not drag the
/// mean negative. Float sums, as the legacy.
struct MeanResidual {
  var sum: [Float]
  var count: [UInt16]

  init(pixels: Int) {
    sum = [Float](repeating: 0, count: pixels)
    count = [UInt16](repeating: 0, count: pixels)
  }

  mutating func add(_ residual: [Float], frame: TrailMaskPlanes.Frame) {
    for index in residual.indices where !TrailMaskPlanes.isZero(frame, index) {
      sum[index] += residual[index]
      count[index] += 1
    }
  }

  /// The mean, 0 where no frame had data.
  var plane: [Float] {
    zip(sum, count).map { $1 > 0 ? $0 / Float($1) : 0 }
  }
}

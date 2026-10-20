package import Foundation
internal import ImageKit

/// Quick-look PNGs of a run's stages: the image decimated to at most `maxDimension`, then an
/// asinh display stretch from median − 2.8 MADN to the 99.9th percentile, linked across planes.
///
/// Display only: nothing it computes feeds a process or a file the run keeps as data.
package enum PreviewRenderer {
  /// Renders `fits` to `png`.
  package static func render(_ fits: URL, to png: URL, maxDimension: Int = 1024) throws {
    let image = try FITSFile.read(at: fits).image()
    let step = max(1, (max(image.width, image.height) + maxDimension - 1) / maxDimension)
    let (width, height) = ((image.width + step - 1) / step, (image.height + step - 1) / step)
    var planes = image.planes.map { plane in
      (0..<height).flatMap { row in
        stride(from: 0, to: image.width, by: step).map { plane[row * step * image.width + $0] }
      }
    }
    let sample = planes.joined().filter(\.isFinite).sorted()
    guard !sample.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    let median = sample[sample.count / 2]
    let deviations = sample.map { abs($0 - median) }.sorted()
    let black = median - 2.8 * 1.4826 * deviations[deviations.count / 2]
    let white = max(sample[Int(0.999 * Double(sample.count - 1))], black + 1e-6)
    let scale = asinh(1000 * (white - black))
    planes = planes.map { plane in
      plane.map { value in value.isFinite ? asinh(1000 * max(0, value - black)) / scale : 0 }
    }
    let shown = AstroImage(width: width, height: height, planes: planes, metadata: image.metadata)
    try ImageExport.write(shown, to: png, format: .png16)
  }
}

internal import Foundation
internal import ImageKit

/// A frame's pixels as planes of physical values in file row order (`planes[c][y * width + x]`).
package struct PixelPlanes: Equatable, Sendable {
  package var width: Int
  package var height: Int
  package var planes: [[Float]]

  /// The given planes.
  package init(width: Int, height: Int, planes: [[Float]]) {
    self.width = width
    self.height = height
    self.planes = planes
  }
}

/// How inspect reads pixels, injected so every verdict is testable without files. `.files`
/// reads FITS through ImageKit — never a second FITS reader.
package struct PixelReader: Sendable {
  /// The whole image at a path.
  package var planes: @Sendable (String) throws -> PixelPlanes
  /// Up to `count` contiguous physical values from the middle of the data unit (`fits.Stats`).
  package var centerSample: @Sendable (String, Int) throws -> [Double]

  /// A reader from the two closures.
  package init(
    planes: @escaping @Sendable (String) throws -> PixelPlanes,
    centerSample: @escaping @Sendable (String, Int) throws -> [Double]
  ) {
    self.planes = planes
    self.centerSample = centerSample
  }

  /// FITS files on disk.
  package static let files = Self(
    planes: { path in
      let image = try FITSFile.read(at: URL(fileURLWithPath: path)).image()
      return PixelPlanes(width: image.width, height: image.height, planes: image.planes)
    },
    centerSample: { path, count in
      try FITSFile.read(at: URL(fileURLWithPath: path)).centerSample(maxCount: count)
    })

  /// The robust statistics of a frame's centre run, `nil` when unreadable.
  func stats(_ path: String, sample: Int) -> SampleStats? {
    (try? centerSample(path, sample)).flatMap(SampleStats.init)
  }
}

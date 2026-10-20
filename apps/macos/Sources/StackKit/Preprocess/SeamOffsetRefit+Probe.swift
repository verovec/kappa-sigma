internal import Foundation
internal import ImageKit

extension SeamOffsetRefit {
  /// Measures nights over one overlap region and applies a refit.
  struct Probe {
    let review: RegistrationReview
    let overlap: [Bool]
    let width: Int
    let height: Int
    let frame: (Int) -> URL

    var gridWidth: Int { (width + CoverageGrid.cellSize - 1) / CoverageGrid.cellSize }
    var gridHeight: Int { (height + CoverageGrid.cellSize - 1) / CoverageGrid.cellSize }

    /// Both nights' overlap curves, the guarded Δ, and the frames rewritten (`refitOneGroup`).
    func measure(_ span: Range<Int>, against anchor: Range<Int>, into record: Record) throws -> Record {
      var record = record
      guard let group = try curve(span) else {
        record.reason = "overlap region too thin to measure on the group's frames"
        return record
      }
      guard let reference = try curve(anchor) else {
        record.reason = "overlap region too thin to measure on the anchor's frames"
        return record
      }
      let (delta, reason) = SeamOffsetRefit.delta(group: group, anchor: reference)
      guard reason.isEmpty else {
        record.reason = reason
        return record
      }
      do {
        try add(Float(delta), to: kept(span))
        (record.delta, record.applied) = (delta, true)
      } catch {
        record.reason = "apply failed: \(ChannelStacker.describe(error))"
      }
      return record
    }

    /// The span's frames kept by the review.
    func kept(_ span: Range<Int>) -> [Int] { span.filter { review.frameHomographies[$0] != nil } }

    /// The component-median masked curve of up to seven evenly spaced kept frames (`overlapCurve`).
    func curve(_ span: Range<Int>) throws -> FrameCurve? {
      var curves: [FrameCurve] = []
      let indices = kept(span)
      let step = indices.count > SeamOffsetRefit.maxProbeFrames ? indices.count / SeamOffsetRefit.maxProbeFrames : 1
      for index in stride(from: 0, to: indices.count, by: step).map({ indices[$0] }).prefix(SeamOffsetRefit.maxProbeFrames) {
        try Task.checkCancellation()
        guard let image = try? FITSFile.read(at: frame(index)).image(),
          let homography = review.frameHomographies[index],
          let curve = FrameCurve.masked(
            planes: image.planes, width: image.width, height: image.height,
            keep: { keep(homography, x: $0, y: $1) })
        else { continue }
        curves.append(curve)
      }
      return curves.isEmpty ? nil : FrameCurve.median(curves)
    }

    /// The pixel's centre, through its frame's homography, lands in the overlap (`overlapKeepFn`).
    func keep(_ homography: [Double], x: Int, y: Int) -> Bool {
      guard let point = Homography.apply(homography, x: Double(x) + 0.5, y: Double(y) + 0.5) else { return false }
      let (column, row) = (Int(point.x) / CoverageGrid.cellSize, Int(point.y) / CoverageGrid.cellSize)
      guard column >= 0, row >= 0, column < gridWidth, row < gridHeight else { return false }
      return overlap[row * gridWidth + column]
    }

    /// p += Δ on each frame, in float32 (`addOffsetToFrames`).
    func add(_ delta: Float, to indices: [Int]) throws {
      for index in indices {
        try Task.checkCancellation()
        let url = frame(index).resolvingSymlinksInPath()
        let file = try FITSFile.read(at: url)
        let image = try file.image()
        image.planes = image.planes.map { $0.map { $0 + delta } }
        try file.write(image, to: url)
      }
    }
  }
}

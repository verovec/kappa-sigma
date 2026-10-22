internal import Foundation
internal import ImageKit

/// What the geometry values make of one input (card 0090), in stored coordinates.
///
/// The panel's values read as the image is shown (top row first): the crop, then the clockwise
/// quarter turns, then the flips of the turned image, then the fine angle. Rows stored bottom-up
/// are shown flipped, so the display moves are conjugated by that flip — the recorded values
/// mean what the panel showed (R2).
struct GeometryPlan {
  /// The exact part: crop, turns and flips as one whole-pixel map.
  let map: GridMap
  /// The fine angle in stored coordinates (clockwise when the row index grows downwards); 0
  /// leaves the exact part alone.
  let degrees: Double
  /// 0 bilinear, 1 bicubic, 2 Lanczos-3.
  let kernel: Int
  /// The output's columns.
  let width: Int
  /// The output's rows.
  let height: Int

  /// The plan of `params` for a `width` × `height` input at `scale` (crop values in
  /// full-resolution pixels, rounded to whole working pixels).
  init(params: ParamSet, width: Int, height: Int, scale: Double, bottomUp: Bool) throws {
    let crops = ["cropLeft", "cropTop", "cropRight", "cropBottom"]
    // Values applied = values shown (R2): a fraction of a pixel is refused, never rounded.
    if let fraction = crops.first(where: { params.number($0).rounded() != params.number($0) }) {
      throw ProcessError.invalidParameter("\(fraction) must be whole pixels")
    }
    func pixels(_ id: String) -> Int { Int((params.number(id) / scale).rounded()) }
    var map = GridMap.identity(width: width, height: height)
    if bottomUp { map = map.flippedY() }
    map = map.cropped(
      left: pixels("cropLeft"), first: pixels("cropTop"), right: pixels("cropRight"),
      last: pixels("cropBottom"))
    guard map.width > 0, map.height > 0 else {
      throw ProcessError.invalidParameter(
        "the crop leaves no pixel of the \(width) × \(height) image")
    }
    let turns = (Int(params.choice("rotation")) ?? 0) / 90
    for _ in 0..<turns { map = map.quarterTurned() }
    if params.flag("flipH") { map = map.flippedX() }
    if params.flag("flipV") { map = map.flippedY() }
    if bottomUp { map = map.flippedY() }
    self.map = map
    let angle = params.number("angle")
    degrees = bottomUp ? -angle : angle
    // The schema refuses any other option: a missing one is a broken invariant, never bilinear.
    guard let kernel = GeometryProcess.interpolations.firstIndex(of: params.choice("interpolation"))
    else {
      throw ProcessError.invalidParameter("interpolation \(params.choice("interpolation"))")
    }
    self.kernel = kernel
    guard angle != 0, params.choice("canvas") == "expand" else {
      (self.width, self.height) = (map.width, map.height)
      return
    }
    let radians = angle * .pi / 180
    let (w, h) = (Double(map.width), Double(map.height))
    // The bounding box of the turned frame; the epsilon keeps an exact fit from adding a column.
    self.width = Int((abs(w * cos(radians)) + abs(h * sin(radians)) - 1e-6).rounded(.up))
    self.height = Int((abs(w * sin(radians)) + abs(h * cos(radians)) - 1e-6).rounded(.up))
  }

  /// The resampling kernel's `p[]` (see Geometry.metal): cos, sin, the output and input
  /// centres, the kernel.
  var resampleUniforms: [Float] {
    let radians = degrees * .pi / 180
    return [
      Float(cos(radians)), Float(sin(radians)), Float(width - 1) / 2, Float(height - 1) / 2,
      Float(map.width - 1) / 2, Float(map.height - 1) / 2, Float(kernel),
    ]
  }

  /// The index kernel's `m[]`: the inverse matrix and the offset (1-based, see `GridMap`).
  var exactUniforms: [Int32] {
    let inverse = map.inverse
    return [inverse[0], inverse[1], inverse[2], inverse[3], map.offset.x, map.offset.y].map {
      Int32($0)
    }
  }
}

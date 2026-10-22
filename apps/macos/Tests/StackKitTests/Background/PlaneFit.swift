import Foundation
import ImageKit
import StackKit

/// A GraXpert stand-in for the flat-sky test: the background model of each plane is its
/// least-squares plane `a·x + b·y + c`, corrected as GraXpert corrects (the model's mean is put
/// back for a subtraction, kept as the scale for a division).
enum PlaneFit {
  /// The plane coefficients `(a, b, c)` of `values` over `width` × `height`.
  static func fit(_ values: [Float], width: Int, height: Int)
    -> (slopeX: Double, slopeY: Double, offset: Double)
  {
    let n = Double(width * height)
    var sx = 0.0
    var sy = 0.0
    var sxx = 0.0
    var syy = 0.0
    var sxy = 0.0
    var sv = 0.0
    var sxv = 0.0
    var syv = 0.0
    for y in 0..<height {
      for x in 0..<width {
        let (px, py, value) = (Double(x), Double(y), Double(values[y * width + x]))
        sx += px
        sy += py
        sxx += px * px
        syy += py * py
        sxy += px * py
        sv += value
        sxv += px * value
        syv += py * value
      }
    }
    // Centred normal equations: the x and y sums decouple from the constant.
    let (mx, my, mv) = (sx / n, sy / n, sv / n)
    let (cxx, cyy, cxy) = (sxx - n * mx * mx, syy - n * my * my, sxy - n * mx * my)
    let (cxv, cyv) = (sxv - n * mx * mv, syv - n * my * mv)
    let det = cxx * cyy - cxy * cxy
    let slopeX = (cxv * cyy - cyv * cxy) / det
    let slopeY = (cyv * cxx - cxv * cxy) / det
    return (slopeX, slopeY, mv - slopeX * mx - slopeY * my)
  }

  /// The model plane of `values`.
  static func model(of values: [Float], width: Int, height: Int) -> [Float] {
    let plane = fit(values, width: width, height: height)
    return (0..<height).flatMap { y in
      (0..<width).map { x in
        Float(plane.slopeX * Double(x) + plane.slopeY * Double(y) + plane.offset)
      }
    }
  }

  /// A runner reading the input FITS, correcting each plane by its fitted plane, writing the output.
  static var graxpert: GraXpertRunner {
    GraXpertRunner { input, output, options, onProgress in
      let image = try FITSFile.read(at: input).image()
      let planes = image.planes.map { plane -> [Float] in
        let model = model(of: plane, width: image.width, height: image.height)
        let mean = model.reduce(0, +) / Float(model.count)
        return zip(plane, model).map { value, background in
          options.correction == .subtract ? value - background + mean : value / background * mean
        }
      }
      let corrected = AstroImage(
        width: image.width, height: image.height, planes: planes, metadata: image.metadata)
      try FITSFile.create(corrected, keeping: nil, at: output)
      onProgress(ToolProgress(line: "plane fit 100%", percent: 100))
      return "plane fit\n"
    }
  }
}

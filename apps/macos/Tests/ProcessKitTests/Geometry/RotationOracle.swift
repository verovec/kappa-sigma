import Foundation

/// A CPU rotation of one plane about its centre, scalar and written apart from the kernel (card
/// 0090): the reference the GPU resampling is held to.
///
/// Rows as stored, y growing with the row index; `degrees` turns clockwise when y points down. A
/// pixel whose source falls outside the input is 0; inside, the kernel taps clamp to the edge.
/// Bilinear, Keys bicubic (a = −0.5), Lanczos-3 with its weights normalised.
struct RotationOracle {
  let width: Int
  let height: Int
  let plane: [Float]

  init(plane input: [Float], width: Int, height: Int, degrees: Double, kernel: String, expand: Bool)
  {
    let radians = degrees * .pi / 180
    let (cosine, sine) = (Float(cos(radians)), Float(sin(radians)))
    if expand {
      let w = abs(Double(width) * cos(radians)) + abs(Double(height) * sin(radians))
      let h = abs(Double(width) * sin(radians)) + abs(Double(height) * cos(radians))
      self.width = Int((w - 1e-6).rounded(.up))
      self.height = Int((h - 1e-6).rounded(.up))
    } else {
      self.width = width
      self.height = height
    }
    let centreIn = (Float(width - 1) / 2, Float(height - 1) / 2)
    let centreOut = (Float(self.width - 1) / 2, Float(self.height - 1) / 2)
    var plane = [Float](repeating: 0, count: self.width * self.height)
    for y in 0..<self.height {
      for x in 0..<self.width {
        let (dx, dy) = (Float(x) - centreOut.0, Float(y) - centreOut.1)
        let sx = cosine * dx + sine * dy + centreIn.0
        let sy = -sine * dx + cosine * dy + centreIn.1
        guard sx >= -0.5, sx <= Float(width) - 0.5, sy >= -0.5, sy <= Float(height) - 0.5 else {
          continue
        }
        plane[y * self.width + x] = Self.sample(
          input, width: width, height: height, x: sx, y: sy, kernel: kernel)
      }
    }
    self.plane = plane
  }

  static func sample(
    _ input: [Float], width: Int, height: Int, x: Float, y: Float, kernel: String
  ) -> Float {
    let radius = kernel == "bilinear" ? 1 : kernel == "bicubic" ? 2 : 3
    let (x0, y0) = (Int(x.rounded(.down)), Int(y.rounded(.down)))
    var (sum, weights): (Float, Float) = (0, 0)
    for j in (y0 - radius + 1)...(y0 + radius) {
      let wy = weight(y - Float(j), kernel)
      for i in (x0 - radius + 1)...(x0 + radius) {
        let w = weight(x - Float(i), kernel) * wy
        let value = input[min(max(j, 0), height - 1) * width + min(max(i, 0), width - 1)]
        sum += w * value
        weights += w
      }
    }
    return kernel == "lanczos3" ? sum / weights : sum
  }

  static func weight(_ distance: Float, _ kernel: String) -> Float {
    let gap = abs(distance)
    switch kernel {
    case "bilinear":
      return max(0, 1 - gap)
    case "bicubic":
      let keys: Float = -0.5
      if gap <= 1 { return ((keys + 2) * gap - (keys + 3)) * gap * gap + 1 }
      if gap < 2 { return ((keys * gap - 5 * keys) * gap + 8 * keys) * gap - 4 * keys }
      return 0
    default:
      if gap == 0 { return 1 }
      if gap >= 3 { return 0 }
      let pd = Float.pi * gap
      return 3 * sin(pd) * sin(pd / 3) / (pd * pd)
    }
  }
}

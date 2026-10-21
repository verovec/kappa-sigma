import Metal
import ProcessKit
import Testing

/// Shared inputs and a runner for the colour-process tests.
enum ColourFixtures {
  static let width = 64
  static let height = 16

  /// A deterministic colour field over [0, 1]: every lightness, hue and saturation, plus a grey
  /// row (mx == mn) and a row of pure primaries.
  static func field() -> [[Float]] {
    var seed: UInt32 = 4_242
    var planes = [[Float]](repeating: [], count: 3)
    for index in 0..<width * height {
      let row = index / width
      for plane in 0..<3 {
        let value: Float
        switch row {
        case 0: value = Float(index % width) / Float(width - 1)
        case 1: value = (index % 3 == plane) ? 1 : 0
        default:
          seed = seed &* 1_664_525 &+ 1_013_904_223
          value = Float(seed >> 8) / Float(1 << 24)
        }
        planes[plane].append(value)
      }
    }
    return planes
  }

  /// `type` with `values` over `planes`, through `ProcessRunner`.
  static func run<P: ImageProcess>(
    _ type: P.Type, _ values: [String: ParamValue], planes: [[Float]],
    width: Int = width, stats: LayerStats = LayerStats(channels: [])
  ) throws -> [[Float]] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var params = ParamSet(schema: P.schema)
    for (id, value) in values { try params.set(id, value) }
    let input = try GPUImage(
      device: device, width: width, height: planes[0].count / width, planes: planes)
    let process = try P(params: params, device: device)
    return try ProcessRunner(device: device).run(process, input: input, stats: stats).read()
  }

  /// The pixel at `index` of `planes`.
  static func pixel(_ planes: [[Float]], _ index: Int) -> [Float] {
    planes.map { $0[index] }
  }

  /// The largest absolute difference between two images.
  static func maxDifference(_ lhs: [[Float]], _ rhs: [[Float]]) -> Float {
    zip(lhs.joined(), rhs.joined()).map { abs($0 - $1) }.max() ?? .infinity
  }

  /// `planes` mapped pixel by pixel through `transform`.
  static func map(_ planes: [[Float]], _ transform: ([Float]) -> [Float]) -> [[Float]] {
    var out = planes.map { [Float](repeating: 0, count: $0.count) }
    for index in planes[0].indices {
      for (plane, value) in transform(pixel(planes, index)).enumerated() {
        out[plane][index] = value
      }
    }
    return out
  }
}

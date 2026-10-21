import Metal
import ProcessKit
import Testing

@Suite(
  "BoxBlur: successive edge-clamped box passes, one radius per pass",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct BoxBlurTests {
  static let (width, height) = (29, 17)

  static func field() -> [Float] {
    (0..<(width * height)).map { index in
      Float((index * 7_919) % 1_013) / 1_013 + (index % width == 9 ? 1 : 0)
    }
  }

  /// astrocomp's `boxPass` read as a window mean (the window clamped to the edge pixels), rows
  /// then columns, once per radius.
  static func oracle(_ plane: [Float], radii: [Int]) -> [Float] {
    var out = plane
    for radius in radii {
      let rows = (0..<out.count).map { index -> Float in
        let (x, y) = (index % width, index / width)
        let sum = (-radius...radius).reduce(Float(0)) { sum, offset in
          sum + out[y * width + min(max(x + offset, 0), width - 1)]
        }
        return sum / Float(2 * radius + 1)
      }
      out = (0..<rows.count).map { index -> Float in
        let (x, y) = (index % width, index / width)
        let sum = (-radius...radius).reduce(Float(0)) { sum, offset in
          sum + rows[min(max(y + offset, 0), height - 1) * width + x]
        }
        return sum / Float(2 * radius + 1)
      }
    }
    return out
  }

  @Test(
    "the GPU passes equal the window-mean oracle within 1e-6",
    arguments: [[0], [2], [1, 1, 3], [4, 4, 4]])
  func testMatchesOracle(radii: [Int]) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let plane = Self.field()
    let input = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: [plane])
    let output = try input.sameSize(device: device)
    let commands = try #require(device.makeCommandQueue()?.makeCommandBuffer())
    try BoxBlur(device: device).encode(
      input.planes[0], into: output.planes[0], radii: radii, commands: commands)
    commands.commit()
    commands.waitUntilCompleted()
    let expected = Self.oracle(plane, radii: radii)
    let worst = zip(output.read()[0], expected).map { abs($0 - $1) }.max() ?? 0
    #expect(worst <= 1e-6)
  }

  @Test("a negative radius is refused")
  func testNegativeRadius() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let image = try GPUImage(device: device, width: 4, height: 4, channels: 1)
    let commands = try #require(device.makeCommandQueue()?.makeCommandBuffer())
    #expect(throws: ProcessError.self) {
      try BoxBlur(device: device).encode(
        image.planes[0], into: image.planes[0], radii: [2, -1], commands: commands)
    }
  }
}

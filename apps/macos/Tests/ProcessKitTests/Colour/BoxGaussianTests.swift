import Metal
import ProcessKit
import Testing

/// `BoxGaussian`: the running-sum passes against `imgops.GaussianBlur`'s CPU port, including radii
/// wider than the image (every sample edge-clamped).
@Suite(
  "Box Gaussian: running sums equal the direct blur",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct BoxGaussianTests {
  @Test(
    "radii match boxesForGauss",
    arguments: zip([0.0, 0.5, 2, 6.93, 27.7], [[], [], [1, 1, 2], [6, 6, 7], [27, 27, 28]]))
  func testRadii(sigma: Double, radii: [Int]) {
    #expect(BoxGaussian.radii(sigma: sigma) == radii)
  }

  @Test("the GPU blur equals the CPU port within 1e-6", arguments: [2.0, 6.93, 40, 120])
  func testMatchesOracle(sigma: Double) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (width, height) = (97, 41)
    var seed: UInt32 = 9
    let plane: [Float] = (0..<width * height).map { _ in
      seed = seed &* 1_664_525 &+ 1_013_904_223
      return 0.05 + Float(seed >> 8) / Float(1 << 24) * 0.9
    }
    let source = try GPUImage(device: device, width: width, height: height, planes: [plane])
    let target = try GPUImage(device: device, width: width, height: height, channels: 1)
    let scratch = try GPUImage(device: device, width: width, height: height, channels: 1)
    let queue = try #require(device.makeCommandQueue())
    let commands = try #require(queue.makeCommandBuffer())
    try BoxGaussian(device: device).encode(
      source.planes[0], into: target.planes[0], scratch: scratch.planes[0], sigma: sigma,
      commands: commands)
    commands.commit()
    commands.waitUntilCompleted()
    let expected = SkyDesatOracle.gaussian(
      plane.map(Double.init), width: width, height: height, sigma: sigma)
    let out = target.read()[0]
    let worst = zip(out, expected).map { abs(Double($0) - $1) }.max() ?? .infinity
    #expect(worst <= 1e-6, "σ \(sigma): \(worst)")
  }
}

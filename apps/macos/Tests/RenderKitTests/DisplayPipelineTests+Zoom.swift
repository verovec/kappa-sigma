import Metal
import RenderKit
import Testing

extension DisplayPipelineTests {
  /// A `width`×`height` checkerboard of `cell`-pixel squares of `low` and `high`.
  static func checkerboard(width: Int, height: Int, cell: Int, low: Float, high: Float)
    -> [Float]
  {
    (0..<width * height).map { ($0 % width / cell + $0 / width / cell) % 2 == 0 ? low : high }
  }

  /// `image` drawn at `scale` image pixels per view pixel into a view of `width`×`height`.
  static func render(_ image: ImageTexture, scale: Float, width: Int, height: Int) throws
    -> [SIMD4<Float>]
  {
    let device = try GPU.requireDevice()
    var uniforms = DisplayUniforms(image: image, stf: nil)
    uniforms.scale = scale
    let pipeline = try DisplayPipeline(device: device, library: ShaderLibrary.load(device: device))
    let output = try GPU.output(width: width, height: height)
    try pipeline.render(current: image, reference: nil, into: output, uniforms: uniforms)
    return GPU.read(output)
  }

  /// Card 0110: at a zoom-out that is not a power of two (Fit), a pattern finer than a view
  /// pixel shows as its average, never as alternating samples (aliasing read as grain). At ×3
  /// the squares are 2 px, finer than a view pixel but not averaged away by the ×2 level.
  @Test(
    "testDisplay_zoomOutNonPowerOfTwo_IsFiltered",
    arguments: zip([Float(1.5), 3], [1, 2]))
  func testDisplay_zoomOutNonPowerOfTwo_IsFiltered(scale: Float, cell: Int) throws {
    let (width, height) = (12, 12)
    let image = try GPU.texture(
      Self.checkerboard(width: width, height: height, cell: cell, low: 0.2, high: 0.8),
      width: width, height: height)
    let side = Int(Float(width) / scale)
    let pixels = try Self.render(image, scale: scale, width: side, height: side)
    let worst = pixels.map { abs($0.x - 0.5) }.max() ?? .infinity
    #expect(worst <= 1.0 / 255, "max |shown − mean| = \(worst) at ×\(scale)")
  }

  /// Card 0110: zoomed in, every image pixel is a hard block of its own value (the readout and
  /// the clipping overlay judge real pixels).
  @Test("testDisplay_zoomIn_StaysNearest")
  func testDisplay_zoomIn_StaysNearest() throws {
    let values: [Float] = [0.1, 0.2, 0.3, 0.4]
    let image = try GPU.texture(values, width: 2, height: 2)
    let pixels = try Self.render(image, scale: 0.5, width: 4, height: 4)
    let want: [Float] = (0..<16).map { values[($0 / 4 / 2) * 2 + ($0 % 4) / 2] }
    #expect(pixels.map(\.x) == want)
  }

  /// Card 0110: zoomed out, the clipping overlay judges the filtered value — a lone clipped
  /// pixel averaged with its neighbours below 1 is not tinted; at 1:1 it is.
  @Test("zoomed out, the clipping overlay is decided on the average; 1:1 on each pixel")
  func testDisplay_zoomOut_ClipsOnTheAverage() throws {
    var values = [Float](repeating: 0.5, count: 16)
    values[0] = 1.2
    let image = try GPU.texture(values, width: 4, height: 4)
    let device = try GPU.requireDevice()
    let pipeline = try DisplayPipeline(device: device, library: ShaderLibrary.load(device: device))
    var uniforms = DisplayUniforms(image: image, stf: nil)
    uniforms.clippingOverlay = 1
    uniforms.scale = 1.5
    let zoomedOut = try GPU.output(width: 2, height: 2)
    try pipeline.render(current: image, reference: nil, into: zoomedOut, uniforms: uniforms)
    // Level 1 is [0.675, 0.5, 0.5, 0.5]; the views sit at image pixels 0.75 and 2.25.
    let want: [Float] = [0.675, 0.565625, 0.565625, 0.524609375]
    for (pixel, value) in zip(GPU.read(zoomedOut), want) {
      #expect(abs(pixel.x - value) < 1e-6 && pixel.y == pixel.x && pixel.z == pixel.x)
    }
    uniforms.scale = 1
    let actual = try GPU.output(width: 4, height: 4)
    try pipeline.render(current: image, reference: nil, into: actual, uniforms: uniforms)
    #expect(GPU.read(actual)[0] == SIMD4(1, 0, 0, 1), "1:1: the clipped pixel is red")
  }
}

extension DisplayPipelineTests {
  /// The CPU oracle of a zoomed-out view pixel: level `lod` built by 2×2 block means (an odd last
  /// row or column dropped, as the pyramid does), then bilinear at image pixel `(x, y)` with
  /// texel i covering [i·2^lod, (i+1)·2^lod), edges clamped.
  static func filtered(
    _ values: [Float], width: Int, height: Int, lod: Int, x: Double, y: Double
  ) -> Double {
    var (level, levelWidth, levelHeight) = (values.map(Double.init), width, height)
    for _ in 0..<lod {
      let (half, halfHeight) = (levelWidth / 2, levelHeight / 2)
      level = (0..<half * halfHeight).map { index in
        let (column, row) = (index % half * 2, index / half * 2)
        let (upper, lower) = (row * levelWidth + column, (row + 1) * levelWidth + column)
        let top = level[upper] + level[upper + 1]
        let bottom = level[lower] + level[lower + 1]
        return (top + bottom) / 4
      }
      (levelWidth, levelHeight) = (half, halfHeight)
    }
    let (px, py) = (x / Double(1 << lod) - 0.5, y / Double(1 << lod) - 0.5)
    let (fx, fy) = (px - px.rounded(.down), py - py.rounded(.down))
    func at(_ column: Int, _ row: Int) -> Double {
      level[min(max(row, 0), levelHeight - 1) * levelWidth + min(max(column, 0), levelWidth - 1)]
    }
    let (column, row) = (Int(px.rounded(.down)), Int(py.rounded(.down)))
    let top = at(column, row) * (1 - fx) + at(column + 1, row) * fx
    let bottom = at(column, row + 1) * (1 - fx) + at(column + 1, row + 1) * fx
    return top * (1 - fy) + bottom * fy
  }

  /// Card 0110 review: on an odd-sized image of varying values, every zoomed-out view pixel is
  /// the bilinear of level `ceil(log2 scale)` at its own image position — the weights, the edge
  /// clamp and the dropped odd column all pinned against the CPU oracle.
  /// One oracle case: the zoom, its level, bottom-up rows, and the image as compare reference.
  struct OracleCase: Sendable, CustomTestStringConvertible {
    let scale: Float
    let lod: Int
    var flipRows = false
    var asReference = false
    var testDescription: String {
      "×\(scale) lod \(lod)\(flipRows ? " bottom-up" : "")\(asReference ? " reference" : "")"
    }
  }

  @Test(
    "zoomed out, each view pixel is the bilinear of the ceil level at its image position",
    arguments: [
      OracleCase(scale: 1.5, lod: 1), OracleCase(scale: 3, lod: 2),
      OracleCase(scale: 1.5, lod: 1, flipRows: true),
      OracleCase(scale: 3, lod: 2, asReference: true),
    ])
  func testDisplay_zoomOut_MatchesTheCPUOracle(_ oracle: OracleCase) throws {
    let (scale, lod) = (oracle.scale, oracle.lod)
    let (width, height) = (13, 9)
    let values: [Float] = (0..<width * height).map { index in
      let (x, y) = (Float(index % width), Float(index / width))
      return 0.5 + 0.3 * sin(x * 1.3) + 0.15 * cos(y * 0.7)
    }
    let image = try GPU.texture(values, width: width, height: height)
    let (viewWidth, viewHeight) = (Int(Float(width) / scale), Int(Float(height) / scale))
    var uniforms = DisplayUniforms(image: image, stf: nil)
    uniforms.scale = scale
    uniforms.flipRows = oracle.flipRows ? 1 : 0
    uniforms.compareMode = oracle.asReference ? 1 : 0
    let device = try GPU.requireDevice()
    let pipeline = try DisplayPipeline(device: device, library: ShaderLibrary.load(device: device))
    let output = try GPU.output(width: viewWidth, height: viewHeight)
    // As the reference, the image is drawn in place of a blank current image.
    let blank = try GPU.texture(
      .init(repeating: 0, count: width * height), width: width, height: height)
    try pipeline.render(
      current: oracle.asReference ? blank : image, reference: oracle.asReference ? image : nil,
      into: output, uniforms: uniforms)
    var worst = 0.0
    for (index, pixel) in GPU.read(output).enumerated() {
      let x = (Double(index % viewWidth) + 0.5) * Double(scale)
      let shownY = (Double(index / viewWidth) + 0.5) * Double(scale)
      let y = oracle.flipRows ? Double(height) - shownY : shownY
      let want = Self.filtered(values, width: width, height: height, lod: lod, x: x, y: y)
      worst = max(worst, abs(Double(pixel.x) - want))
    }
    #expect(worst <= 1e-5, "max |GPU − CPU| = \(worst), \(oracle.testDescription)")
  }
}

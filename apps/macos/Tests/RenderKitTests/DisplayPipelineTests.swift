import Metal
import RenderKit
import Testing

@Suite("DisplayPipeline: the display kernel against the CPU oracle", .enabled(if: GPU.available))
struct DisplayPipelineTests {
  static func render(
    _ current: ImageTexture, reference: ImageTexture? = nil, uniforms: DisplayUniforms
  ) throws -> [SIMD4<Float>] {
    let device = try GPU.requireDevice()
    let pipeline = try DisplayPipeline(device: device, library: ShaderLibrary.load(device: device))
    let output = try GPU.output(width: current.width, height: current.height)
    try pipeline.render(current: current, reference: reference, into: output, uniforms: uniforms)
    return GPU.read(output)
  }

  static let ramp: [Float] = (0..<1024).map { -0.2 + 1.4 * Float($0) / 1023 }

  @Test("the STF shader equals the CPU MTF oracle within 1/65535 on a ramp")
  func testSTFMatchesReference() throws {
    let image = try GPU.texture(Self.ramp, width: 1024, height: 1)
    let stf = STFParameters(shadows: 0.031, midtone: 0.07, highlights: 1)
    let pixels = try Self.render(image, uniforms: DisplayUniforms(image: image, stf: [stf]))
    var worst = 0.0
    for (value, pixel) in zip(Self.ramp, pixels) {
      worst = max(worst, abs(Double(pixel.x) - stf.display(Double(value))))
      #expect(pixel.x == pixel.y && pixel.y == pixel.z, "mono shows grey")
    }
    #expect(worst <= 1.0 / 65535, "max |GPU − CPU| = \(worst)")
  }

  @Test("STF off renders clamp(x) only")
  func testOffIsIdentity() throws {
    let image = try GPU.texture(Self.ramp, width: 1024, height: 1)
    let pixels = try Self.render(image, uniforms: DisplayUniforms(image: image, stf: nil))
    for (value, pixel) in zip(Self.ramp, pixels) {
      #expect(pixel.x == min(max(value, 0), 1))
    }
  }

  @Test("clipped pixels are tinted exactly; compare and split pick the reference per pixel")
  func testClippingOverlayAndCompare() throws {
    let current = try GPU.texture([-0.1, 0.5, 1.2, 0.5], width: 4, height: 1)
    let reference = try GPU.texture([0.25, 0.25, 0.25, 0.25], width: 4, height: 1)

    var clipping = DisplayUniforms(image: current, stf: nil)
    clipping.clippingOverlay = 1
    let tinted = try Self.render(current, uniforms: clipping)
    #expect(tinted[0] == SIMD4(0, 0, 1, 1), "≤ 0 is blue")
    #expect(tinted[1] == SIMD4(0.5, 0.5, 0.5, 1))
    #expect(tinted[2] == SIMD4(1, 0, 0, 1), "≥ 1 is red")

    var whole = DisplayUniforms(image: current, stf: nil)
    whole.compareMode = 1
    #expect(
      try Self.render(current, reference: reference, uniforms: whole).allSatisfy { $0.x == 0.25 })

    var split = DisplayUniforms(image: current, stf: nil)
    split.compareMode = 2
    split.splitX = 2
    let halves = try Self.render(current, reference: reference, uniforms: split)
    #expect(halves.map(\.x) == [0.25, 0.25, 1, 0.5], "left of the split: reference")
  }

  @Test("the mask overlay tints by half the mask, in red; without it the mask is not shown")
  func testMaskOverlay() throws {
    let device = try GPU.requireDevice()
    let image = try GPU.texture([0.2, 0.2, 0.2], width: 3, height: 1)
    let mask = try GPU.texture([1, 0.5, 0], width: 3, height: 1)
    var uniforms = DisplayUniforms(image: image, stf: nil)
    let pipeline = try DisplayPipeline(device: device, library: ShaderLibrary.load(device: device))
    let output = try GPU.output(width: 3, height: 1)
    try pipeline.render(
      current: image, reference: nil, mask: mask.planes[0], into: output, uniforms: uniforms)
    #expect(GPU.read(output).map(\.x) == [0.2, 0.2, 0.2], "overlay off")
    uniforms.maskOverlay = 1
    try pipeline.render(
      current: image, reference: nil, mask: mask.planes[0], into: output, uniforms: uniforms)
    let shown = GPU.read(output)
    #expect(abs(shown[0].x - 0.6) < 1e-6 && abs(shown[0].y - 0.1) < 1e-6 && shown[0].w == 1)
    #expect(abs(shown[1].x - 0.4) < 1e-6 && abs(shown[1].y - 0.15) < 1e-6)
    #expect(shown[2] == SIMD4(0.2, 0.2, 0.2, 1))
  }

  @Test("a bottom-up image shows its last stored row at the top, as Siril does")
  func testBottomUpRowsFlipped() throws {
    let image = try GPU.texture([0.1, 0.2, 0.3, 0.4, 0.5, 0.6], width: 2, height: 3)
    var uniforms = DisplayUniforms(image: image, stf: nil)
    uniforms.flipRows = 1
    let pixels = try Self.render(image, uniforms: uniforms)
    #expect(pixels.map(\.x) == [0.5, 0.6, 0.3, 0.4, 0.1, 0.2])
  }

  @Test("zoomed out ×2, a 2×2 block mean comes from the mip level, not one sample")
  func testDisplay_zoomedOutUsesMip() throws {
    let device = try GPU.requireDevice()
    let image = try ImageTexture(
      device: device, width: 4, height: 2, planes: [[0, 1, 0, 1, 1, 0, 1, 0]])
    var uniforms = DisplayUniforms(image: image, stf: nil)
    uniforms.scale = 2
    let pipeline = try DisplayPipeline(device: device, library: ShaderLibrary.load(device: device))
    let output = try GPU.output(width: 2, height: 1)
    try pipeline.render(current: image, reference: nil, into: output, uniforms: uniforms)
    #expect(GPU.read(output).map(\.x) == [0.5, 0.5])
  }
}

@Suite("Histogram: GPU bins at quarter resolution", .enabled(if: GPU.available))
struct HistogramTests {
  @Test(
    "bins of each channel sum to the sampled pixel count and equal a CPU count",
    arguments: [(1, 7, 5), (3, 8, 6), (3, 1, 1)])
  func testBinsSumToPixelCount(channels: Int, width: Int, height: Int) throws {
    let device = try GPU.requireDevice()
    let planes: [[Float]] = (0..<channels).map { channel in
      (0..<width * height).map { index -> Float in
        let step = (index * 37 + channel * 11) % 300
        return Float(step) / 255 - 0.05
      }
    }
    let image = try ImageTexture(device: device, width: width, height: height, planes: planes)
    let histogram = try Histogram(device: device, library: ShaderLibrary.load(device: device))
    let bins = try histogram.compute(image, stride: 2)

    let sampled = ((width + 1) / 2) * ((height + 1) / 2)
    #expect(bins.count == channels)
    for (channel, counts) in bins.enumerated() {
      #expect(counts.count == 256)
      #expect(counts.reduce(0, +) == sampled)
      var expected = [Int](repeating: 0, count: 256)
      for y in Swift.stride(from: 0, to: height, by: 2) {
        for x in Swift.stride(from: 0, to: width, by: 2) {
          let value = min(max(planes[channel][y * width + x], 0), 1)
          expected[min(Int(value * 255 + 0.5), 255)] += 1
        }
      }
      #expect(counts == expected)
    }
  }

  @Test("NaN and ±Inf pixels are not counted")
  func testBinsSkipNonFinite() throws {
    let device = try GPU.requireDevice()
    let image = try ImageTexture(
      device: device, width: 4, height: 1, planes: [[0.5, .nan, .infinity, -.infinity]])
    let histogram = try Histogram(device: device, library: ShaderLibrary.load(device: device))
    let bins = try histogram.compute(image, stride: 1)
    #expect(bins[0].reduce(0, +) == 1)
    #expect(bins[0][128] == 1)
  }

  @Test("with a region, only its pixels are counted, sampled from its top-left corner")
  func testBinsFollowRegion() throws {
    let device = try GPU.requireDevice()
    let (width, height) = (9, 7)
    let plane = (0..<width * height).map { Float($0 % 17) / 16 }
    let image = try ImageTexture(device: device, width: width, height: height, planes: [plane])
    let histogram = try Histogram(device: device, library: ShaderLibrary.load(device: device))
    let region = PixelRegion(x: 3, y: 2, width: 5, height: 4)
    let bins = try histogram.compute(image, stride: 2, region: region)

    var expected = [Int](repeating: 0, count: 256)
    for y in Swift.stride(from: 2, to: 6, by: 2) {
      for x in Swift.stride(from: 3, to: 8, by: 2) {
        expected[min(Int(plane[y * width + x] * 255 + 0.5), 255)] += 1
      }
    }
    #expect(bins == [expected])
  }
}

@Suite(
  "Shader library: one definition of the parameter structs, two load paths",
  .enabled(if: GPU.available))
struct ShaderLibraryTests {
  @Test("the Swift mirrors have the layout the GPU compiles from ShaderTypes.h")
  func testShaderLayout_matchesSwift() throws {
    let device = try GPU.requireDevice()
    let probe = try ShaderLayoutProbe.run(device: device)
    #expect(probe.gpu == probe.swift)
  }

  @Test("the runtime library exposes every kernel")
  func testRuntimeLibrary_functions() throws {
    let library = try ShaderLibrary.compileSources(device: try GPU.requireDevice())
    #expect(Set(library.functionNames) == ShaderLibrary.kernelNames)
  }

  @Test(
    "runtime and precompiled libraries expose the same functions",
    .enabled(if: MetalToolchain.available, "Metal Toolchain absent (xcrun metal): Xcode only"))
  func testRuntimeAndPrecompiledAgree() throws {
    let device = try GPU.requireDevice()
    let runtime = try ShaderLibrary.compileSources(device: device)
    let precompiled = try MetalToolchain.compileLibrary(device: device)
    #expect(Set(runtime.functionNames) == Set(precompiled.functionNames))
  }
}

/// The area around the image is the canvas token's grey, never black nor tinted.
@Suite("DisplayPipeline: the canvas around the image", .enabled(if: GPU.available))
struct DisplayCanvasTests {
  @Test(
    "view pixels outside the image show the canvas grey of each appearance, R = G = B",
    arguments: DesignAppearance.allCases)
  func testCanvasOutsideImage(_ appearance: DesignAppearance) throws {
    let image = try GPU.texture([0.5, 0.5], width: 2, height: 1)
    var frame = ViewerFrame(transform: ViewTransform(scale: 1, origin: SIMD2(-2, 0)), stf: nil)
    frame.canvasGrey = DesignColor.canvasGrey(in: appearance)
    let device = try GPU.requireDevice()
    let pipeline = try DisplayPipeline(device: device, library: ShaderLibrary.load(device: device))
    let output = try GPU.output(width: 4, height: 1)
    try pipeline.render(
      current: image, reference: nil, into: output, uniforms: frame.uniforms(for: image))
    let pixels = GPU.read(output)
    let grey = DesignColor.canvasGrey(in: appearance)
    #expect(pixels[0] == SIMD4(grey, grey, grey, 1) && pixels[1] == pixels[0])
    #expect(pixels[2] == SIMD4(0.5, 0.5, 0.5, 1), "the image itself is untouched")
  }
}

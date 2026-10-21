import AppKit
import Metal
import RenderKit
import SwiftUI
import Testing

/// The display-domain histogram (the kernel bins the displayed values after the STF) and the
/// three handles: their positions in each domain and what a drag does to the stretch (card 0085).
@Suite("HistogramHandles — display-domain bins, handle positions, drags")
struct HistogramHandlesTests {
  static let stf = STFParameters(shadows: 0.031, midtone: 0.07, highlights: 1)
  static let ramp: [Float] = (0..<1024).map { Float($0) / 1023 }

  /// The kernel's bin of a displayed value (`Histogram.metal`).
  static func bin(_ displayed: Double) -> Int {
    min(Int((min(max(displayed, 0), 1) * 255 + 0.5).rounded(.down)), 255)
  }

  @Test(
    "a linear ramp under an STF yields bins spread over the range, matching the CPU oracle",
    .enabled(if: GPU.available))
  func testDisplayDomainBins() throws {
    let device = try GPU.requireDevice()
    let image = try GPU.texture(Self.ramp, width: 1024, height: 1)
    let histogram = try Histogram(device: device, library: ShaderLibrary.load(device: device))

    let linear = try histogram.compute(image, stride: 1)[0]
    let display = try histogram.compute(image, stride: 1, stf: [Self.stf])[0]
    #expect(linear.reduce(0, +) == 1024 && display.reduce(0, +) == 1024)
    #expect(abs(linear[0..<16].reduce(0, +) - 64) <= 1, "the linear ramp fills the bins evenly")
    // Under the stretch, the ramp displays bright: most of it above ½, spread over the bins.
    #expect(display[128...].reduce(0, +) > 700, "a stretched ramp lifts the values")
    #expect(display.filter { $0 > 0 }.count > 100, "and spreads them over the range")
    #expect(display[0..<16].reduce(0, +) < linear[0..<16].reduce(0, +))

    // The GPU float math may land a value one bin away from the double oracle: compare the
    // cumulative counts within one sample per bin.
    var oracle = [Int](repeating: 0, count: 256)
    for value in Self.ramp { oracle[Self.bin(Self.stf.display(Double(value)))] += 1 }
    var (gpu, cpu, worst) = (0, 0, 0)
    for index in 0..<256 {
      gpu += display[index]
      cpu += oracle[index]
      worst = max(worst, abs(gpu - cpu))
    }
    #expect(worst <= 1, "cumulative counts differ by \(worst)")
  }

  @Test(
    "the renderer counts the display domain when the frame asks for it", .enabled(if: GPU.available)
  )
  func testRendererFollowsTheFrameDomain() throws {
    let device = try GPU.requireDevice()
    let image = try GPU.texture(Self.ramp, width: 1024, height: 1)
    let renderer = try ViewerRenderer(device: device)
    let output = try GPU.output(width: 4, height: 1)
    var frame = ViewerFrame(transform: ViewTransform(scale: 1, origin: .zero), stf: [Self.stf])
    frame.histogramStride = 1
    let linear = try renderer.render(image: image, reference: nil, frame: frame, into: output)
    frame.histogramDomain = .display
    let display = try renderer.render(image: image, reference: nil, frame: frame, into: output)
    #expect(abs(linear[0][0..<16].reduce(0, +) - 64) <= 1)
    #expect(display[0][128...].reduce(0, +) > 700)
    #expect(
      frame.histogramInput
        != ViewerFrame(transform: frame.transform, stf: [Self.stf]).histogramInput)
    frame.stf = nil
    #expect(frame.histogramSTF == nil, "off: the display domain is the linear one")
    // An empty stretch list is off too, for both kernels.
    #expect(
      DisplayUniforms(width: 1, height: 1, mipLevels: 1, channels: 1, stf: []).stfEnabled == 0)
    let off = try Self.histogramIsOff(device: device, image: image)
    #expect(off)
  }

  /// The histogram of `image` through an empty stretch list equals its linear one.
  static func histogramIsOff(device: MTLDevice, image: ImageTexture) throws -> Bool {
    let histogram = try Histogram(device: device, library: ShaderLibrary.load(device: device))
    return try histogram.compute(image, stride: 1, stf: []) == histogram.compute(image, stride: 1)
  }

  struct Positions: Sendable, CustomTestStringConvertible {
    let stf: STFParameters
    let linear: [Double]
    var testDescription: String { "c0 \(stf.shadows) m \(stf.midtone) c1 \(stf.highlights)" }
  }

  @Test(
    "handle positions: c0 / c0 + m·(c1 − c0) / c1 in the linear domain, 0 / ½ / 1 displayed",
    arguments: [
      Positions(stf: stf, linear: [0.031, 0.031 + 0.07 * 0.969, 1]),
      Positions(
        stf: STFParameters(shadows: 0.2, midtone: 0.5, highlights: 0.8), linear: [0.2, 0.5, 0.8]),
      Positions(stf: .identity, linear: [0, 0.5, 1]),
    ])
  func testHandlePositions(_ row: Positions) {
    let linear = row.stf.handlePositions(in: .linear)
    #expect(abs(linear.shadows - row.linear[0]) < 1e-12)
    #expect(abs(linear.midtone - row.linear[1]) < 1e-12)
    #expect(abs(linear.highlights - row.linear[2]) < 1e-12)
    #expect(abs(row.stf.midtoneValue - row.linear[1]) < 1e-12)
    let display = row.stf.handlePositions(in: .display)
    #expect(display.shadows == 0 && abs(display.midtone - 0.5) < 1e-12 && display.highlights == 1)
    for handle in STFHandle.allCases {
      #expect(linear[handle] == [linear.shadows, linear.midtone, linear.highlights][handle.index])
    }
  }

  @Test("a position in the display domain maps back to the linear value shown there")
  func testLinearValueAtPosition() {
    for position in stride(from: 0.0, through: 1.0, by: 0.05) {
      let value = Self.stf.linearValue(atPosition: position, in: .display)
      #expect(abs(Self.stf.display(value) - position) < 1e-9)
      #expect(Self.stf.linearValue(atPosition: position, in: .linear) == position)
    }
  }

  @Test("a drag moves only its handle, in either domain, and keeps c0 < c1")
  func testDragMovesOneHandle() {
    let stf = Self.stf
    let shadows = stf.dragging(.shadows, to: 0.1, in: .linear)
    #expect(shadows.shadows == 0.1 && shadows.midtone == stf.midtone && shadows.highlights == 1)

    let midtone = stf.dragging(.midtone, to: 0.5, in: .linear)
    #expect(abs(midtone.midtoneValue - 0.5) < 1e-12)
    #expect(midtone.shadows == stf.shadows && midtone.highlights == stf.highlights)

    let highlights = stf.dragging(.highlights, to: 0.6, in: .linear)
    #expect(highlights.highlights == 0.6 && highlights.shadows == stf.shadows)
    #expect(highlights.midtone == stf.midtone)

    // Display domain: the value shown at 0.25 becomes the black point; the midtone handle
    // dropped at 0.75 makes that value the new midtone.
    let shown = stf.dragging(.shadows, to: 0.25, in: .display)
    #expect(abs(shown.shadows - stf.linearValue(atPosition: 0.25, in: .display)) < 1e-12)
    let mid = stf.dragging(.midtone, to: 0.75, in: .display)
    #expect(abs(mid.midtoneValue - stf.linearValue(atPosition: 0.75, in: .display)) < 1e-12)

    // Never crossed: the black point stops below the white point and the reverse.
    let crossed = stf.dragging(.shadows, to: 1.2, in: .linear)
    #expect(crossed.shadows < crossed.highlights)
    let under = STFParameters(shadows: 0.5, midtone: 0.5, highlights: 0.9)
      .dragging(.highlights, to: 0.1, in: .linear)
    #expect(under.highlights > under.shadows)
    #expect((0...1).contains(stf.dragging(.midtone, to: -3, in: .linear).midtone))
    // And inside [0, 1] even from a degenerate stretch (raw c1 = 0, raw c0 = 1).
    let dark = STFParameters(shadows: 0, midtone: 0.5, highlights: 0)
      .dragging(.shadows, to: 0.5, in: .linear)
    #expect(dark.shadows >= 0 && dark.shadows < dark.highlights + 1e-9)
    let bright = STFParameters(shadows: 1, midtone: 0.5, highlights: 1)
      .dragging(.highlights, to: 0.5, in: .linear)
    #expect(bright.highlights <= 1)
  }

  /// The plot rendered to pixels (sRGB bytes), and how many differ from the first pixel.
  @MainActor
  static func pixels(_ handles: [STFHandlePositions]?, bins: [[Int]]) throws -> (
    bytes: [UInt8], inked: Int
  ) {
    let view = HistogramHandles(
      bins: bins, handles: handles, key: "test", label: "Histogram",
      hint: "Drag a handle"
    ) { _, _, _ in }
    let renderer = ImageRenderer(content: view.frame(width: 128, height: 48))
    let image = try #require(
      renderer.nsImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let bitmap = NSBitmapImageRep(cgImage: image)
    var bytes: [UInt8] = []
    var inked = 0
    let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB)
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        bytes += [colour.redComponent, colour.greenComponent, colour.blueComponent].map {
          UInt8(min(max($0, 0), 1) * 255)
        }
        inked += colour == background ? 0 : 1
      }
    }
    return (bytes, inked)
  }

  @Test("the handles draw over an empty plot and over counts; none without a stretch")
  @MainActor
  func testHandlesDraw() throws {
    let empty = [[Int]](repeating: [Int](repeating: 0, count: 256), count: 3)
    let none = try Self.pixels(nil, bins: empty)
    let drawn = try Self.pixels([Self.stf.handlePositions(in: .linear)], bins: empty)
    #expect(none.inked == 0 && drawn.inked > 0)
    let full = [[Int]](repeating: [Int](repeating: 100, count: 256), count: 3)
    let three = try Self.pixels(
      [Self.stf, .identity, STFParameters(shadows: 0.2, midtone: 0.5, highlights: 0.8)].map {
        $0.handlePositions(in: .linear)
      }, bins: full)
    let plain = try Self.pixels(nil, bins: full)
    #expect(three.bytes != plain.bytes)
    // A mono plot draws its handles in the luminance colour: still something over the plot.
    let mono = try Self.pixels([Self.stf.handlePositions(in: .display)], bins: [empty[0]])
    #expect(mono.inked > 0)
  }

  @Test("the nearest handle within reach takes the press; none when all are far")
  func testNearestHandle() {
    let sets = [
      STFHandlePositions(shadows: 0.1, midtone: 0.3, highlights: 0.9),
      STFHandlePositions(shadows: 0.5, midtone: 0.6, highlights: 1),
    ]
    let hit = HistogramHandles.nearest(to: 0.31, in: sets, within: 0.03)
    #expect(hit?.channel == 0 && hit?.handle == .midtone)
    let other = HistogramHandles.nearest(to: 0.52, in: sets, within: 0.03)
    #expect(other?.channel == 1 && other?.handle == .shadows)
    #expect(HistogramHandles.nearest(to: 0.75, in: sets, within: 0.03) == nil)
  }
}

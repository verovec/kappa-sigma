import AppKit
import ImageKit
import Metal
import RenderKit
import SwiftUI
import TestSupport
import Testing

/// The card's manual acceptance, recorded: run #78 `rgb_base` (the 0067 finishing crop,
/// hash-checked) with Shadows moved by 0.1 σ steps — the sky darkens a little at each step, never
/// jumps — and the panel with its numbers, as PNG attachments.
@MainActor
@Suite(
  "Live stretch controls — run #78 rgb_base, Shadows by 0.1 σ steps", .finishOracle,
  .tags(.live), .enabled(if: GPU.available), .serialized, .timeLimit(.minutes(2)))
struct LiveStretchControlsTests {
  /// The display output as a PNG.
  static func png(_ output: MTLTexture) throws -> Data {
    let pixels = GPU.read(output)
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: output.width, pixelsHigh: output.height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: output.width * 4, bitsPerPixel: 32))
    let bytes = try #require(bitmap.bitmapData)
    for (index, pixel) in pixels.enumerated() {
      for lane in 0..<3 {
        bytes[index * 4 + lane] = UInt8(min(max(pixel[lane], 0), 1) * 255)
      }
      bytes[index * 4 + 3] = 255
    }
    return try #require(bitmap.representation(using: .png, properties: [:]))
  }

  @Test("each 0.1 σ step darkens the sky gently; the panel shows the numbers (PNGs attached)")
  func testShadowsStepsMoveTheSkyGently() throws {
    let root = try #require(FinishOracle.root)
    let layer = try #require(
      FinishOracle.manifest().layers.first { $0.path == "crop/rgb_base.fits" })
    try #require(FinishOracle.verify([layer], root: root) == [])
    let image = try FITSFile.read(at: root.appendingPathComponent(layer.path)).image()
    let device = try GPU.requireDevice()
    let texture = try ImageTexture(
      device: device, width: image.width, height: image.height, planes: image.planes)
    let renderer = try ViewerRenderer(device: device)
    let model = ViewerModel(image: image)
    let (width, height) = (image.width / 2, image.height / 2)
    model.viewSize = SIMD2(Double(width), Double(height))
    model.zoomToFit()
    let output = try GPU.output(width: width, height: height)

    func shown(_ name: String) throws -> Double {
      _ = try renderer.render(image: texture, reference: nil, frame: model.frame, into: output)
      Attachment.record(try Self.png(output), named: name)
      let pixels = GPU.read(output)
      return pixels.map { Double($0.x + $0.y + $0.z) / 3 }.reduce(0, +) / Double(pixels.count)
    }

    var means = [try shown("stretch-auto.png")]
    model.stretch = .manual
    let step = STFChannelControls.step(of: .shadowsSigma).coarse
    for index in 1...3 {
      for channel in model.manualSTF.indices {
        var controls = STFChannelControls(
          parameters: model.manualSTF[channel], auto: model.autoParameters[channel],
          mapping: model.mapping(for: channel))
        var sigma = controls[.shadowsSigma]
        sigma.set(sigma.value + step)
        controls[.shadowsSigma] = sigma
        model.manualSTF[channel] = controls.parameters
      }
      means.append(try shown("stretch-shadows-plus-\(index)-tenth-sigma.png"))
    }
    print("LiveStretchControls: mean shown per 0.1 σ step \(means)")
    for (before, after) in zip(means, means.dropFirst()) {
      #expect(after < before, "the sky darkens")
      #expect(before - after < 0.05, "and gently: \(before) → \(after)")
    }

    // The panel in manual mode: the σ, target and highlights rows with their numbers.
    let host = try ViewerViewTests.hosted(model)
    host.appearance = NSAppearance(named: .darkAqua)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    Attachment.record(
      try #require(bitmap.representation(using: .png, properties: [:])), named: "stretch-panel.png")
  }
}

import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// `testSubtractRestoresFlatSky` of card 0072: a flat field under a plane gradient comes back flat
/// (within 1 %) and the model is what was taken out — a zero-mean plane for a subtraction, a
/// unit-mean plane for a division. GraXpert is played by a plane fit; the Siril engines are
/// checked on a real Siril in `LiveBackgroundExtractionTests`.
@Suite("BackgroundExtraction restores a flat sky from a plane gradient")
struct BackgroundFlatSkyTests {
  static let flat: Float = 0.2
  static let (width, height) = (64, 48)

  /// `flat + 0.001·x′ − 0.0005·y′` per plane (x′, y′ centred, so the gradient has a zero mean and a
  /// subtraction — which puts the model's mean back — leaves exactly `flat`), scaled per channel.
  static func gradient() -> AstroImage { gradient(width: width, height: height) }

  /// The same gradient (same edge-to-edge amplitude) over another size.
  static func gradient(width: Int, height: Int) -> AstroImage {
    let (stepX, stepY) = (63 / Float(width - 1), 47 / Float(height - 1))
    let planes: [[Float]] = (0..<3).map { channel in
      let scale = Float(1 + channel)
      var plane: [Float] = []
      plane.reserveCapacity(width * height)
      for y in 0..<height {
        for x in 0..<width {
          let (dx, dy) = (Float(x) - Float(width - 1) / 2, Float(y) - Float(height - 1) / 2)
          plane.append(flat + scale * (0.001 * dx * stepX - 0.0005 * dy * stepY))
        }
      }
      return plane
    }
    return AstroImage(
      width: width, height: height, planes: planes, metadata: ImageMetadata(rowOrder: .bottomUp))
  }

  static func extraction() -> BackgroundExtraction {
    BackgroundExtraction(
      graxpert: { PlaneFit.graxpert }, siril: SirilRunner { _, _, _ in "" })
  }

  @Test("testSubtractRestoresFlatSky", .scratchDirectory)
  func testSubtractRestoresFlatSky() async throws {
    let result = try await Self.extraction().run(
      image: Self.gradient(), engine: .graxpert(smoothing: 0.5), correction: .subtract,
      scratch: try ScratchDirectory.url
    ) { _ in }
    let worst = result.corrected.planes.joined().map { abs($0 - Self.flat) }.max() ?? 1
    #expect(worst <= Self.flat * 0.01, "corrected sky off by \(worst) (1 % = \(Self.flat * 0.01))")
    for (channel, plane) in result.model.planes.enumerated() {
      let mean = plane.reduce(0, +) / Float(plane.count)
      #expect(abs(mean) <= 1e-5, "channel \(channel): subtraction model mean \(mean)")
      // The model's slopes are the gradient's.
      let dx = plane[1] - plane[0]
      let dy = plane[Self.width] - plane[0]
      let scale = Float(1 + channel)
      #expect(abs(dx - 0.001 * scale) <= 1e-5 && abs(dy + 0.0005 * scale) <= 1e-5)
    }
    #expect(result.corrected.metadata.rowOrder == .bottomUp)
  }

  @Test("divide leaves a unit-mean model and a flat sky", .scratchDirectory)
  func testDivideLeavesUnitMeanModel() async throws {
    let result = try await Self.extraction().run(
      image: Self.gradient(), engine: .graxpert(smoothing: 0.5), correction: .divide,
      scratch: try ScratchDirectory.url
    ) { _ in }
    for plane in result.model.planes {
      let mean = plane.reduce(0, +) / Float(plane.count)
      #expect(abs(mean - 1) <= 1e-4, "division model mean \(mean)")
    }
    // The division of a plane gradient by its model leaves one value: the model's mean per plane.
    for (channel, plane) in result.corrected.planes.enumerated() {
      let spread = (plane.max() ?? 0) - (plane.min() ?? 0)
      #expect(spread <= Self.flat * 0.01, "channel \(channel): spread \(spread)")
    }
  }
}

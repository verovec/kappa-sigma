import Metal
import ProcessKit
import Testing

/// Card 0189: the proxy a drag renders on is the input reduced by an integer factor — a box
/// average of the finite values of each cell (`FITSFile.downsampled(pooling: .mean)`'s rule), ragged
/// last cells averaged over what they hold — and the result goes back to the full size
/// bilinearly. Both kernels against their CPU oracle.
@Suite(
  "Resample — box downsample and bilinear upsample against the CPU",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ResampleTests {
  struct Case: CustomTestStringConvertible {
    let name: String
    let width: Int
    let height: Int
    let factor: Int
    let plane: [Float]
    var testDescription: String { name }
  }

  static func ramp(_ width: Int, _ height: Int) -> [Float] {
    (0..<(width * height)).map { Float($0 % width) / Float(width) + Float($0 / width) / 100 }
  }

  static let cases: [Case] = {
    var nanCell = ramp(8, 4)
    nanCell[9] = .nan  // one NaN inside the cell (0, 0) at factor 4
    var deadCell = ramp(8, 4)
    for y in 0..<2 { for x in 0..<2 { deadCell[y * 8 + x] = .nan } }  // the whole cell (0,0) at 2
    return [
      Case(name: "even sizes, factor 2", width: 8, height: 4, factor: 2, plane: ramp(8, 4)),
      Case(name: "even sizes, factor 4", width: 8, height: 4, factor: 4, plane: ramp(8, 4)),
      Case(name: "ragged edges, factor 3", width: 7, height: 5, factor: 3, plane: ramp(7, 5)),
      Case(name: "a NaN inside a cell is left out", width: 8, height: 4, factor: 4, plane: nanCell),
      Case(name: "a cell of NaNs is NaN", width: 8, height: 4, factor: 2, plane: deadCell),
      Case(name: "factor 1 is the identity", width: 5, height: 3, factor: 1, plane: ramp(5, 3)),
    ]
  }()

  /// The CPU oracle: cells pooled in double, finite values only, NaN for an empty cell.
  static func boxAverage(_ plane: [Float], width: Int, height: Int, factor: Int) -> [Float] {
    let outWidth = (width + factor - 1) / factor
    let outHeight = (height + factor - 1) / factor
    var out = [Float](repeating: .nan, count: outWidth * outHeight)
    for cy in 0..<outHeight {
      for cx in 0..<outWidth {
        var sum = 0.0
        var count = 0
        for y in (cy * factor)..<min((cy + 1) * factor, height) {
          for x in (cx * factor)..<min((cx + 1) * factor, width) {
            let value = plane[y * width + x]
            guard value.isFinite else { continue }
            sum += Double(value)
            count += 1
          }
        }
        if count > 0 { out[cy * outWidth + cx] = Float(sum / Double(count)) }
      }
    }
    return out
  }

  @Test("testDownsample_MatchesCPUBoxAverage", arguments: cases)
  func testDownsample_MatchesCPUBoxAverage(_ testCase: Case) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let resample = try Resample(device: device)
    let image = try GPUImage(
      device: device, width: testCase.width, height: testCase.height,
      planes: [testCase.plane, testCase.plane.reversed()])

    let reduced = try resample.downsample(image, by: testCase.factor)

    let expected = [
      Self.boxAverage(
        testCase.plane, width: testCase.width, height: testCase.height, factor: testCase.factor),
      Self.boxAverage(
        testCase.plane.reversed(), width: testCase.width, height: testCase.height,
        factor: testCase.factor),
    ]
    #expect(reduced.width == (testCase.width + testCase.factor - 1) / testCase.factor)
    #expect(reduced.height == (testCase.height + testCase.factor - 1) / testCase.factor)
    for (plane, oracle) in zip(reduced.read(), expected) {
      #expect(plane.count == oracle.count)
      for (value, want) in zip(plane, oracle) {
        if want.isNaN {
          #expect(value.isNaN)
        } else {
          // A float sum of at most factor² values against a double one.
          #expect(abs(value - want) <= 1e-6, "\(value) vs \(want)")
        }
      }
    }
  }

  /// Bilinear, pixel centres aligned (`(i + 0.5) · src / dst − 0.5`, edges clamped): the CPU
  /// formula within float rounding.
  static func bilinear(_ plane: [Float], width: Int, height: Int, toWidth: Int, toHeight: Int)
    -> [Float]
  {
    func sample(_ x: Int, _ y: Int) -> Double {
      Double(plane[min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)])
    }
    var out = [Float](repeating: 0, count: toWidth * toHeight)
    for y in 0..<toHeight {
      for x in 0..<toWidth {
        let sx = (Double(x) + 0.5) * Double(width) / Double(toWidth) - 0.5
        let sy = (Double(y) + 0.5) * Double(height) / Double(toHeight) - 0.5
        let x0 = Int(sx.rounded(.down))
        let y0 = Int(sy.rounded(.down))
        let fx = sx - Double(x0)
        let fy = sy - Double(y0)
        let top = sample(x0, y0) * (1 - fx) + sample(x0 + 1, y0) * fx
        let bottom = sample(x0, y0 + 1) * (1 - fx) + sample(x0 + 1, y0 + 1) * fx
        out[y * toWidth + x] = Float(top * (1 - fy) + bottom * fy)
      }
    }
    return out
  }

  @Test("testUpsample_BilinearMatchesCPU")
  func testUpsample_BilinearMatchesCPU() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let resample = try Resample(device: device)
    let plane = Self.ramp(4, 3)
    let image = try GPUImage(device: device, width: 4, height: 3, planes: [plane])

    let enlarged = try resample.upsample(image, toWidth: 9, toHeight: 7)

    let expected = Self.bilinear(plane, width: 4, height: 3, toWidth: 9, toHeight: 7)
    #expect(enlarged.width == 9 && enlarged.height == 7)
    for (value, want) in zip(enlarged.read()[0], expected) {
      #expect(abs(value - want) <= 1e-6, "\(value) vs \(want)")
    }
    let same = try resample.upsample(image, toWidth: 4, toHeight: 3)
    #expect(same === image, "the size it has: nothing to do")
  }
}

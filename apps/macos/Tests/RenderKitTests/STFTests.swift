import RenderKit
import Testing

@Suite("STF: the midtones transfer function and Siril's autostretch, on the CPU (the oracle)")
struct STFTests {
  @Test(
    "MTF fixed points and the identity at m = 0.5",
    arguments: [
      (0.25, 0.0, 0.0), (0.25, 1.0, 1.0), (0.25, 0.25, 0.5), (0.5, 0.3, 0.3), (0.5, 0.8, 0.8),
      (0.1, 0.1, 0.5), (0.9, 0.9, 0.5),
    ])
  func testMTF_fixedPoints(midtone: Double, x: Double, expected: Double) {
    #expect(abs(MTF.apply(midtone, x) - expected) < 1e-12)
  }

  @Test("MTF is the closed form ((m − 1)x) / ((2m − 1)x − m) and is monotonic")
  func testMTF_closedFormAndMonotonic() {
    let midtone = 0.07
    var previous = -1.0
    for step in 0...100 {
      let x = Double(step) / 100
      let value = MTF.apply(midtone, x)
      let closed = x == 0 ? 0 : ((midtone - 1) * x) / ((2 * midtone - 1) * x - midtone)
      #expect(abs(value - closed) < 1e-12)
      #expect(value >= previous)
      previous = value
    }
  }

  @Test("STF display of a value: clip below c0, rescale, MTF; off is clamp(x)")
  func testSTFParameters_display() {
    let stf = STFParameters(shadows: 0.1, midtone: 0.25, highlights: 1)
    #expect(stf.display(0.05) == 0)
    #expect(abs(stf.display(0.1 + 0.25 * 0.9) - 0.5) < 1e-12)
    #expect(stf.display(1.5) == 1)
    #expect(STFParameters.identity.display(0.3) == 0.3)
    #expect(STFParameters.identity.display(-0.2) == 0)
    #expect(STFParameters.identity.display(1.2) == 1)
  }

  @Test("autostretch: c0 = median − 2.8·MADN, midtone maps median − c0 to the 0.25 target")
  func testAutoSTF_unlinked() {
    // 26 × 0.09, 49 × 0.1, 26 × 0.11: upper median 0.1, upper-median MAD 0.01 → MADN 0.014826
    var plane = [Float](repeating: 0.1, count: 101)
    for index in 0..<26 {
      plane[index] = 0.09
      plane[100 - index] = 0.11
    }
    let stf = AutoSTF.compute(planes: [plane], linked: false)[0]
    let madn = 0.01 * 1.4826
    let c0 = 0.1 - 2.8 * madn
    #expect(abs(stf.shadows - c0) < 1e-6)
    // Siril computes m from median − c0 (not rescaled by 1 − c0): that value lands on 0.25.
    #expect(abs(MTF.apply(stf.midtone, Double(Float(0.1)) - stf.shadows) - 0.25) < 1e-6)
    #expect(stf.highlights == 1)
  }

  @Test("linked autostretch gives every channel the same parameters")
  func testAutoSTF_linked() {
    let red = [Float](repeating: 0.2, count: 9)
    let blue = [Float](repeating: 0.05, count: 9)
    let stf = AutoSTF.compute(planes: [red, blue, blue], linked: true)
    #expect(stf[0] == stf[1] && stf[1] == stf[2])
    let unlinked = AutoSTF.compute(planes: [red, blue, blue], linked: false)
    #expect(unlinked[0] != unlinked[1])
  }

  @Test("a flat or empty plane gets a safe, finite stretch")
  func testAutoSTF_degenerate() {
    for plane in [[Float](repeating: 0.3, count: 4), [Float]()] {
      let stf = AutoSTF.compute(planes: [plane], linked: false)[0]
      #expect(stf.shadows.isFinite && stf.midtone.isFinite)
      #expect((0...1).contains(stf.shadows) && (0...1).contains(stf.midtone))
    }
  }

  @Test("NaN and ±Inf pixels (blank borders) are left out of the statistics")
  func testAutoSTF_ignoresNonFinite() {
    let finite: [Float] = (0..<101).map { 0.05 + Float($0 % 13) / 1000 }
    let dirty = finite + [.nan, .infinity, -.infinity, .nan]
    #expect(
      AutoSTF.compute(planes: [dirty], linked: false)
        == AutoSTF.compute(planes: [finite], linked: false))
  }
}

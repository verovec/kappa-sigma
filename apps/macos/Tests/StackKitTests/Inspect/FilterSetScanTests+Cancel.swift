import StackKit
import Synchronization
import Testing

extension FilterSetScanTests {
  @Test("a cancelled scan stops reading frames for the colour verdicts")
  func testAnnotateStopsWhenCancelled() async {
    let reads = Mutex(0)
    let images = [
      "bias.fits": Self.mosaic(Self.biasADU, Self.biasADU, Self.biasADU),
      "a.fits": Self.mosaic(Self.biasADU + 6, Self.biasADU + 3, Self.biasADU + 2),
    ]
    // Every read after the bias's cancels the scan: the first light read is the last read.
    let reader = PixelReader(
      planes: { path in
        let count = reads.withLock { value in
          value += 1
          return value
        }
        if count > 1 { withUnsafeCurrentTask { $0?.cancel() } }
        return images[path] ?? images["a.fits"] ?? Self.mosaic(0, 0, 0)
      },
      centerSample: { _, _ in [] })
    let frames =
      [Self.osc("bias.fits", .bias, exposureMs: 0)]
      + (0..<6).map { Self.osc("light_\($0).fits", .light, exposureMs: 60_000 * ($0 + 1)) }
    let task = Task {
      var inventory = Self.inventory(frames)
      FilterSetClassifier.annotate(&inventory, overrides: [:], pixels: reader)
    }
    await task.value
    #expect(reads.withLock { $0 } == 2, "one light read, then nothing")
  }
}

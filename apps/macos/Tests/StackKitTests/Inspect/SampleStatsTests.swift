import StackKit
import Testing

/// `SampleStats` is the legacy `fits.summarize`: order statistics by index (`sorted[n/2]`), MAD
/// about that median, the bright fraction above median + 3·MAD, peaks above median + 6·MAD.
@Suite("SampleStats — the robust summary the classifier and channel detection read")
struct SampleStatsTests {
  @Test("one hot pixel on a flat run: zero MAD, one bright pixel, one peak")
  func testSampleStats_hotPixel() throws {
    let stats = try #require(SampleStats([1, 1, 1, 1, 10, 1, 1, 1, 1, 1]))
    #expect(stats.count == 10)
    #expect(stats.median == 1)
    #expect(stats.mad == 0)
    #expect(stats.p90 == 10)
    #expect(stats.brightFraction == 0.1)
    #expect(stats.peaks == 1)
    #expect(stats.mean == 1.9)
    #expect(stats.min == 1)
    #expect(stats.max == 10)
  }

  @Test("median and MAD are the upper middle of an odd or even sample")
  func testSampleStats_orderStatistics() throws {
    let stats = try #require(SampleStats([5, 3, 8, 8, 2]))
    #expect(stats.median == 5)
    #expect(stats.mad == 3)
    #expect(stats.p90 == 8)
    #expect(stats.brightFraction == 0)
    #expect(stats.peaks == 0)
  }

  @Test("a peak is a strict rise then a non-strict fall, never at either end")
  func testSampleStats_peaks() throws {
    let stats = try #require(SampleStats([9, 0, 0, 0, 7, 7, 0, 0, 0, 0, 0, 9]))
    #expect(stats.peaks == 1)
  }

  @Test("an empty sample has no statistics")
  func testSampleStats_empty() {
    #expect(SampleStats([]) == nil)
  }
}

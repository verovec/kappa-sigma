import StackKit
import Testing

@Suite("GoFormat: numbers written exactly as the legacy Go engine wrote them")
struct GoFormatTests {
  @Test(
    "strconv.FormatFloat(v, 'g', -1, 64)",
    arguments: [
      (3.0, "3"), (0.2, "0.2"), (0.05, "0.05"), (1.8, "1.8"), (10.0, "10"), (0.0001, "0.0001"),
      (0.00001, "1e-05"), (1.5e-7, "1.5e-07"), (1e21, "1e+21"), (0.001, "0.001"), (-2.5, "-2.5"),
      (999_999, "999999"), (1_000_000, "1e+06"), (1_234_567.5, "1.2345675e+06"),
      (123_456_789, "1.23456789e+08"), (-0.0, "-0"), (0, "0"), (.infinity, "+Inf"),
      (-.infinity, "-Inf"), (.nan, "NaN"), (5e-324, "5e-324"),
      (1.7976931348623157e308, "1.7976931348623157e+308"),
    ])
  func testGoFormat_shortest(value: Double, expected: String) {
    #expect(GoFormat.shortest(value) == expected)
  }

  @Test(
    "%.Nf rounds the exact binary value (ties to even, as Go)",
    arguments: [(0.125, 2, "0.12"), (0.06, 3, "0.060"), (0.5, 2, "0.50"), (1.005, 2, "1.00")])
  func testGoFormat_fixed(value: Double, decimals: Int, expected: String) {
    #expect(GoFormat.fixed(value, decimals: decimals) == expected)
  }
}

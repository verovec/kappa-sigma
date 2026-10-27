import FilterKit
import Foundation
import ProcessKit
import Testing

/// `LineKernels` mirrors `Shaders/Lines.h` (card 0136): the slot count and the per-line structs
/// the injection and screen kernels read.
@Suite("Lines.h — the line kernels' slots and per-line structs")
struct LinesHeaderTests {
  /// `Lines.h` as bundled with ProcessKit's shaders.
  static func header() throws -> String {
    let url = try #require(
      ProcessKitResources.bundle.url(forResource: "Shaders/Lines.h", withExtension: nil))
    return try String(contentsOf: url, encoding: .utf8)
  }

  @Test("maxLines is the header's MAX_LINES")
  func testMaxLinesMatchesHeader() throws {
    let header = try Self.header()
    let match = try #require(header.firstMatch(of: /#define MAX_LINES (\d+)/))
    #expect(Int(match.1) == LineKernels.maxLines)
  }

  @Test("every narrowband filter of the catalogue fits in the kernels' slots")
  func testCatalogueFitsMaxLines() {
    #expect(Filter.narrowband.count <= LineKernels.maxLines)
    #expect(EmissionLine.allCases.count <= LineKernels.maxLines)
  }

  @Test(
    "the Swift structs have the header's layouts: plain floats, no padding",
    arguments: zip(
      ["InjectLine", "ScreenLine"],
      [MemoryLayout<LineKernels.InjectLine>.stride, MemoryLayout<LineKernels.ScreenLine>.stride]))
  func testStructLayouts(name: String, stride: Int) throws {
    let header = try Self.header()
    let body = try #require(
      header.firstMatch(of: try Regex("struct \(name) \\{([^}]*)\\}")), "\(name) in Lines.h")
    let text = try #require(body.output[1].substring)
    // Every field is a float or a float array: the size is the float count × 4.
    let floats = text.matches(of: /float\s+\w+(?:\[(\d+)\])?;/).map { Int($0.1 ?? "1") ?? 0 }
    #expect(floats.reduce(0, +) * MemoryLayout<Float>.stride == stride)
  }
}

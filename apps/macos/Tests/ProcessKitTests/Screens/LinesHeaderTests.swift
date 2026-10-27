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

  /// One mirror: the header's struct name, the Swift fields in order with their float counts.
  static let mirrors: [(name: String, fields: [(String, Int)], stride: Int)] = [
    (
      "InjectLine",
      Self.fields(of: LineKernels.InjectLine(weight: (0, 0, 0), k: 0, black: 0)),
      MemoryLayout<LineKernels.InjectLine>.stride
    ),
    (
      "ScreenLine", Self.fields(of: LineKernels.ScreenLine(alpha: 0, tint: (0, 0, 0))),
      MemoryLayout<LineKernels.ScreenLine>.stride
    ),
  ]

  /// The stored fields of `value` in declaration order, a tuple counting its elements.
  static func fields(of value: Any) -> [(String, Int)] {
    Mirror(reflecting: value).children.map { child in
      (child.label ?? "", max(Mirror(reflecting: child.value).children.count, 1))
    }
  }

  @Test(
    "the Swift structs have the header's fields, in order, as plain floats without padding",
    arguments: 0..<2)
  func testStructLayouts(index: Int) throws {
    let mirror = Self.mirrors[index]
    let header = try Self.header()
    let body = try #require(
      header.firstMatch(of: try Regex("struct \(mirror.name) \\{([^}]*)\\}")),
      "\(mirror.name) in Lines.h")
    let text = try #require(body.output[1].substring)
    let fields = text.matches(of: /float\s+(\w+)(?:\[(\d+)\])?;/).map {
      (String($0.1), Int($0.2 ?? "1") ?? 0)
    }
    #expect(fields.map(\.0) == mirror.fields.map(\.0))
    #expect(fields.map(\.1) == mirror.fields.map(\.1))
    #expect(fields.map(\.1).reduce(0, +) * MemoryLayout<Float>.stride == mirror.stride)
  }
}

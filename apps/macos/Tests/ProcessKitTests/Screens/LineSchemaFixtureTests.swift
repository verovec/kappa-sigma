import Foundation
import ProcessKit
import TestSupport
import Testing

/// The screens and injection schemas, spec by spec, equal the recording made before `EmissionLine`
/// became a projection of FilterKit (card 0133): ids, titles, units, levels, kinds and defaults —
/// what stored recipes and the parity oracles read. `RECORD=1` rewrites the fixture.
@Suite("Line schemas — recorded spec list, untouched by the FilterKit move")
struct LineSchemaFixtureTests {
  static let fixture = "schemas/line-schemas.txt"

  @Test("both line schemas equal the recorded fixture")
  func testSchemasMatchRecordedFixture() throws {
    let rendered =
      Self.render(EmissionScreensProcess.schema, name: EmissionScreensProcess.id)
      + Self.render(LineInjectionProcess.schema, name: LineInjectionProcess.id)
    let text = rendered.joined(separator: "\n") + "\n"
    if ProcessInfo.processInfo.environment["RECORD"] == "1" {
      let root = URL(fileURLWithPath: try ModuleBoundary.packageRoot(from: #filePath))
      let file = root.appendingPathComponent("Tests/ProcessKitTests/Fixtures/\(Self.fixture)")
      try text.write(to: file, atomically: true, encoding: .utf8)
      // The bundle still holds the copy built before this run: say so instead of passing.
      Issue.record("fixture re-recorded at \(file.path): review the diff, then run without RECORD")
      return
    }
    let url = try #require(
      Bundle.module.url(forResource: "Fixtures/\(Self.fixture)", withExtension: nil))
    let recorded = try String(contentsOf: url, encoding: .utf8)
    #expect(recorded.split(separator: "\n") == text.split(separator: "\n"))
  }

  /// One line per spec: `process | id | title | unit | level | kind`.
  static func render(_ schema: ParamSchema, name: String) -> [String] {
    schema.specs.map { spec in
      [name, spec.id, spec.title, "\(spec.unit)", "\(spec.level)", kind(spec.kind)]
        .joined(separator: " | ")
    }
  }

  static func kind(_ kind: ParamSpec.Kind) -> String {
    switch kind {
    case .number(let value, let bounds): "number \(value) in \(bounds)"
    case .flag(let value): "flag \(value)"
    case .choice(let value, let options): "choice \(value) of \(options.joined(separator: ","))"
    case .points(let points, let maxCount): "points \(points.count) max \(maxCount)"
    case .text(let value, let maxLength): "text \(value) max \(maxLength)"
    }
  }
}

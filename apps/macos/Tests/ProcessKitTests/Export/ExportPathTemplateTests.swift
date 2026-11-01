import Foundation
import ProcessKit
import Testing

/// The export sub-path template (card 0151): `{object}/{stack}/{date}-{time}` under the base
/// folder, each value made safe for one path component, never a path that leaves the base.
@Suite("ExportPathTemplate — the sub-path of an export under its base folder")
struct ExportPathTemplateTests {
  /// 2026-10-22 12:00:05 UTC.
  static let stamp = Date(timeIntervalSince1970: 1_792_670_405)

  static func values(object: String = "M 31", project: String = "M31") throws
    -> ExportPathTemplate.Values
  {
    ExportPathTemplate.Values(
      object: object, stack: "run1", project: project, date: Self.stamp,
      zone: try #require(TimeZone(identifier: "UTC")))
  }

  struct Case: Sendable, CustomTestStringConvertible {
    let template: String
    let object: String
    let expected: Result<String, ExportPathTemplate.Refusal>
    var testDescription: String { "« \(template) » (object « \(object) »)" }
  }

  static let cases: [Case] = [
    Case(
      template: ExportPathTemplate.standard, object: "M 31",
      expected: .success("M 31/run1/2026-10-22-120005")),
    Case(template: "{object}", object: "IC 1848", expected: .success("IC 1848")),
    Case(template: "{stack}", object: "M 31", expected: .success("run1")),
    Case(template: "{date}", object: "M 31", expected: .success("2026-10-22")),
    Case(template: "{time}", object: "M 31", expected: .success("120005")),
    Case(template: "{project}", object: "M 31", expected: .success("M31")),
    Case(template: "astro/{object}", object: "", expected: .success("astro/M31")),
    Case(template: "{object}", object: "M 31/core", expected: .success("M 31-core")),
    Case(template: "{object}", object: "a:b", expected: .success("a-b")),
    Case(template: "", object: "M 31", expected: .success("")),
    Case(template: "a//{stack}/", object: "M 31", expected: .success("a/run1")),
    Case(
      template: "{target}/{date}", object: "M 31",
      expected: .failure(.unknownToken("target", valid: ExportPathTemplate.tokens))),
    Case(template: "../x", object: "M 31", expected: .failure(.leavesBase("../x"))),
    Case(template: "a/./b", object: "M 31", expected: .failure(.leavesBase("a/./b"))),
    Case(template: "{object}", object: "..", expected: .failure(.leavesBase("{object}"))),
    Case(template: "/Volumes/x", object: "M 31", expected: .failure(.leavesBase("/Volumes/x"))),
    Case(
      template: "{object/{date}", object: "M 31",
      expected: .failure(.unbalancedBrace("{object/{date}"))),
    Case(template: "{obj", object: "M 31", expected: .failure(.unbalancedBrace("{obj"))),
    Case(template: "a}b", object: "M 31", expected: .failure(.unbalancedBrace("a}b"))),
  ]

  @Test("testResolve", arguments: Self.cases)
  func testResolve(_ row: Case) throws {
    let base = URL(fileURLWithPath: "/Users/someone/Pictures/AstroStack", isDirectory: true)
    let template = ExportPathTemplate(row.template)
    let values = try Self.values(object: row.object)
    switch row.expected {
    case .success(let relative):
      let folder = try template.folder(under: base, values)
      let expected = relative.isEmpty ? base : base.appendingPathComponent(relative)
      #expect(folder.standardizedFileURL.path == expected.standardizedFileURL.path)
      #expect(template.refusal(values) == nil)
    case .failure(let refusal):
      #expect(throws: refusal) { try template.folder(under: base, values) }
      #expect(template.refusal(values) == refusal)
    }
  }

  @Test("the refusal of an unknown token lists the valid ones, in braces")
  func testUnknownTokenListsValid() {
    #expect(ExportPathTemplate.tokens == ["object", "stack", "date", "time", "project"])
    #expect(
      ExportPathTemplate("{nope}").refusal(.example)
        == .unknownToken("nope", valid: ExportPathTemplate.tokens))
    #expect(ExportPathTemplate.listed == "{object}, {stack}, {date}, {time}, {project}")
  }

  @Test("the date and time are the user's zone, to the second, 24-hour")
  func testStampInZone() throws {
    let paris = try #require(TimeZone(identifier: "Europe/Paris"))
    let values = ExportPathTemplate.Values(
      object: "M 31", stack: "run1", project: "M31", date: Self.stamp, zone: paris)
    let folder = try ExportPathTemplate("{date}-{time}").folder(
      under: URL(fileURLWithPath: "/x", isDirectory: true), values)
    #expect(folder.lastPathComponent == "2026-10-22-140005")
  }
}

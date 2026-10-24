import AstroStackApp
import Foundation
import StackKit
import Testing

/// What the next run redoes (card 0100): every checked night and its lights, and the capture
/// folders added since the last stack — a run re-stacks them all, nothing is reused.
@MainActor
@Suite("RestackPlan — every night again, the folders added since the last stack")
struct RestackPlanTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let objects: [String]
    let nights: [String]
    let sources: [Int64]
    let lastStack: [Int64]?
    let expected: RestackPlan
    var testDescription: String { name }
  }

  nonisolated static let twoNights = ["2026-09-21", "2026-09-22"]

  nonisolated static let cases = [
    Case(
      name: "first stack: no earlier stack to compare", objects: ["M 31"], nights: twoNights,
      sources: [1, 2], lastStack: nil, expected: RestackPlan(nights: 2, frames: 6, added: nil)),
    Case(
      name: "one folder added since the last stack", objects: ["M 31"], nights: twoNights,
      sources: [1, 2], lastStack: [1], expected: RestackPlan(nights: 2, frames: 6, added: 1)),
    Case(
      name: "nothing added: the same nights again", objects: ["M 31"], nights: twoNights,
      sources: [1, 2], lastStack: [1, 2], expected: RestackPlan(nights: 2, frames: 6, added: 0)),
    Case(
      name: "two objects on the same two nights: two nights", objects: ["IC 1848", "M 31"],
      nights: twoNights, sources: [1], lastStack: [1],
      expected: RestackPlan(nights: 2, frames: 12, added: 0)),
    Case(
      name: "a single-night scan of two objects is one night", objects: ["IC 1848", "M 31"],
      nights: [""], sources: [1, 2], lastStack: nil,
      expected: RestackPlan(nights: 1, frames: 6, added: nil)),
    Case(
      name: "an undated set is one night", objects: ["M 31"], nights: [""], sources: [1],
      lastStack: nil, expected: RestackPlan(nights: 1, frames: 3, added: nil)),
  ]

  @Test(
    "the checked nights, their lights and the folders new since the last stack", arguments: cases)
  func testPlan(_ row: Case) throws {
    let series = StackingStageModel(
      inventory: StackingStageModelTests.inventory(objects: row.objects, nights: row.nights))
    let plan = try #require(
      RestackPlan(series: series, nightSourceIDs: row.sources, lastStackSourceIDs: row.lastStack))
    #expect(plan == row.expected)
  }

  @Test("an unchecked night is not redone; nothing checked is no plan")
  func testUncheckedNights() throws {
    let series = StackingStageModel(
      inventory: StackingStageModelTests.inventory(objects: ["M 31"], nights: Self.twoNights))
    let ids = series.groups.flatMap(\.nights).flatMap(\.series).map(\.id)
    series.set(try #require(ids.first), checked: false)
    #expect(
      RestackPlan(series: series, nightSourceIDs: [1], lastStackSourceIDs: nil)
        == RestackPlan(nights: 1, frames: 3, added: nil))
    for id in ids { series.set(id, checked: false) }
    #expect(RestackPlan(series: series, nightSourceIDs: [1], lastStackSourceIDs: nil) == nil)
  }

  @Test("without a scan there is nothing to say")
  func testNoScan() {
    let series = StackingStageModel(inventory: nil)
    #expect(RestackPlan(series: series, nightSourceIDs: [1], lastStackSourceIDs: [1]) == nil)
  }
}

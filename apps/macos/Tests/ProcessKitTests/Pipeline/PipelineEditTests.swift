import Foundation
import ProcessKit
import Testing

/// Steps removed and moved (card 0107): the pure edits the Studio's pipeline column makes.
@Suite("Pipeline edits — remove a step, move a step")
struct PipelineEditTests {
  /// A pipeline of `DummyGain` steps whose gains are `gains`, in order.
  static func pipeline(_ gains: [Double]) throws -> Pipeline {
    Pipeline(name: "p", steps: try gains.map { try PipelineDiffTests.step($0) })
  }

  /// The gains of `pipeline`'s steps, in order.
  static func gains(_ pipeline: Pipeline) -> [Double] {
    pipeline.steps.map {
      ParamSet.loading($0.recipe.params, onto: DummyGain.schema).params.number("gain")
    }
  }

  struct RemoveCase: Sendable, CustomTestStringConvertible {
    let name: String
    let index: Int
    let expected: [Double]
    var testDescription: String { name }
  }

  @Test(
    "removing a step drops it; out of range leaves the pipeline unchanged",
    arguments: [
      RemoveCase(name: "first", index: 0, expected: [2, 3, 4]),
      RemoveCase(name: "middle", index: 2, expected: [1, 2, 4]),
      RemoveCase(name: "last", index: 3, expected: [1, 2, 3]),
      RemoveCase(name: "past the end", index: 4, expected: [1, 2, 3, 4]),
      RemoveCase(name: "negative", index: -1, expected: [1, 2, 3, 4]),
    ])
  func testRemoving(_ row: RemoveCase) throws {
    let pipeline = try Self.pipeline([1, 2, 3, 4])
    let removed = pipeline.removing(at: row.index)
    #expect(Self.gains(removed) == row.expected)
    #expect(removed.name == pipeline.name)
  }

  struct MoveCase: Sendable, CustomTestStringConvertible {
    let name: String
    let from: Int
    let to: Int
    let expected: [Double]
    var testDescription: String { name }
  }

  @Test(
    "moving a step puts it at the destination index; out of range leaves it unchanged",
    arguments: [
      MoveCase(name: "first to last", from: 0, to: 3, expected: [2, 3, 4, 1]),
      MoveCase(name: "last to first", from: 3, to: 0, expected: [4, 1, 2, 3]),
      MoveCase(name: "middle down one", from: 1, to: 2, expected: [1, 3, 2, 4]),
      MoveCase(name: "middle up one", from: 2, to: 1, expected: [1, 3, 2, 4]),
      MoveCase(name: "in place", from: 2, to: 2, expected: [1, 2, 3, 4]),
      MoveCase(name: "destination past the end", from: 1, to: 4, expected: [1, 2, 3, 4]),
      MoveCase(name: "source past the end", from: 4, to: 0, expected: [1, 2, 3, 4]),
      MoveCase(name: "negative", from: -1, to: 0, expected: [1, 2, 3, 4]),
    ])
  func testMoving(_ row: MoveCase) throws {
    let pipeline = try Self.pipeline([1, 2, 3, 4])
    #expect(Self.gains(pipeline.moving(from: row.from, to: row.to)) == row.expected)
  }

  @Test("a moved step keeps its breakpoint and its lock")
  func testMovingKeepsModeAndLock() throws {
    var pipeline = try Self.pipeline([1, 2, 3])
    pipeline.steps[0].mode = .stop
    pipeline.steps[0].locked = true
    let moved = pipeline.moving(from: 0, to: 2)
    #expect(moved.steps[2].mode == .stop && moved.steps[2].locked)
    #expect(moved.steps[0].mode == .auto && !moved.steps[0].locked)
  }
}

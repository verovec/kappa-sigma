import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

extension HistoryTests {
  /// Card 0092: a step may rewrite bundle layers by id (a background extraction of the Hα
  /// layer): the later steps read the rewritten layer under the bundle's id, undo takes it
  /// away, a reopened history finds it again and `save` keeps it while referenced.
  @Test("testReplacedLayersRoundTrip", .scratchDirectory)
  func testReplacedLayersRoundTrip() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let original = try Self.image([0, 1, 2, 3])
    let history = try History(directory: directory, original: original)
    let bundle = ["RGB": try Self.image([9, 9, 9, 9]), "Ha": try Self.image([8, 8, 8, 8])]

    try history.apply(
      processID: "bge", params: Self.params, result: try Self.image([1, 1, 1, 1]),
      outputs: [.backgroundModel: try Self.image([7, 7, 7, 7])],
      replacing: ["Ha": try Self.image([2, 2, 2, 2])])
    #expect(history.steps.last?.replaced.keys.sorted() == ["Ha"])
    #expect(history.layerRoles == [.backgroundModel], "a rewritten bundle layer adds no role")
    var context = try history.context(over: bundle)
    #expect(context["Ha"]?.planes == [[2, 2, 2, 2]])
    #expect(context["RGB"]?.planes == [[9, 9, 9, 9]], "a layer not rewritten is the bundle's")
    #expect(context["backgroundModel"]?.planes == [[7, 7, 7, 7]])

    // A later rewrite of the same layer wins; undo restores the earlier one, then the bundle's.
    try history.apply(
      processID: "bge", params: Self.params, result: try Self.image([1, 1, 1, 1]),
      replacing: ["Ha": try Self.image([3, 3, 3, 3])])
    #expect(try history.context(over: bundle)["Ha"]?.planes == [[3, 3, 3, 3]])
    try history.undo()
    #expect(try history.context(over: bundle)["Ha"]?.planes == [[2, 2, 2, 2]])

    let reopened = try History.reopen(directory: directory, original: original) { _ in
      Self.gainSchema
    }
    #expect(reopened.steps == history.steps && reopened.undone == history.undone)
    context = try reopened.context(over: bundle)
    #expect(context["Ha"]?.planes == [[2, 2, 2, 2]])
    #expect(reopened.referencedFiles.contains { $0.hasSuffix("-Ha.fits") })

    try reopened.undo()
    #expect(try reopened.context(over: bundle)["Ha"]?.planes == [[8, 8, 8, 8]])
    try reopened.apply(processID: "b", params: Self.params, result: try Self.image([4, 4, 4, 4]))
    let before = try Self.files(in: directory)
    try reopened.save()
    let removed = before.subtracting(try Self.files(in: directory))
    #expect(removed.count == 5, "two dropped steps: images, model, two rewritten Hα: \(removed)")
  }
}

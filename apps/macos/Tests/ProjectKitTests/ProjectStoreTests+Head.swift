import Foundation
import ProjectKit
import TestSupport
import Testing

extension ProjectStoreTests {
  /// Card 0087: undo moves an image's head back without deleting the step (redo needs it); the
  /// head can be none (the original) and only ever a step of that image.
  @Test(
    "setHead moves the head back and forth, to none, never to another image's step",
    .scratchDirectory)
  func testSetHead() throws {
    let package = try Self.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try store.addStack(bundlePath: "stacks/1", sourceIDs: [], paramsJSON: "{}")
    let image = try store.addImage(stackID: stack.id, role: "studio")
    let other = try store.addImage(stackID: stack.id, role: "other")
    let first = try store.appendHistoryStep(
      imageID: image.id, processID: "a", paramsJSON: "[]", output: nil, contentHash: nil)
    let second = try store.appendHistoryStep(
      imageID: image.id, processID: "b", paramsJSON: "[]", output: nil, contentHash: nil)
    let foreign = try store.appendHistoryStep(
      imageID: other.id, processID: "c", paramsJSON: "[]", output: nil, contentHash: nil)
    func head() throws -> Int64? {
      try store.images(stackID: stack.id).first { $0.id == image.id }?.headStepID
    }
    #expect(try head() == second.id)
    try store.setHead(imageID: image.id, stepID: first.id)
    #expect(try head() == first.id)
    try store.setHead(imageID: image.id, stepID: nil)
    #expect(try head() == nil)
    try store.setHead(imageID: image.id, stepID: second.id)
    #expect(try head() == second.id)
    #expect(throws: ProjectStoreError.self) {
      try store.setHead(imageID: image.id, stepID: foreign.id)
    }
    #expect(try head() == second.id && store.history(imageID: image.id).count == 2)
  }
}

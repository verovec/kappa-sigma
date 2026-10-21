import Foundation
import ProjectKit
import TestSupport
import Testing

/// `pipelines` (migration 0001, card 0059): the project's saved pipelines, by name, as the JSON
/// ProcessKit writes — « Save pipeline as… » / « Load ».
@Suite("ProjectStore: saved pipelines by name")
struct PipelineStoreTests {
  @Test(
    "a pipeline is saved, listed, overwritten, kept across reopen and deleted", .scratchDirectory)
  func testPipelineRoundTrip() throws {
    let package = try ProjectStoreTests.newPackage()
    #expect(try package.store.pipelineNames() == [])
    #expect(try package.store.pipeline(named: "M31 v9") == nil)
    try package.store.savePipeline(named: "M31 v9", json: Data(#"{"a":1}"#.utf8))
    try package.store.savePipeline(named: "IC 1848 doux", json: Data(#"{"b":2}"#.utf8))
    try package.store.savePipeline(named: "M31 v9", json: Data(#"{"a":2}"#.utf8))
    #expect(try package.store.pipelineNames() == ["IC 1848 doux", "M31 v9"])
    try package.close()

    let reopened = try ProjectPackage.open(at: package.url)
    defer { try? reopened.close() }
    #expect(try reopened.store.pipeline(named: "M31 v9") == Data(#"{"a":2}"#.utf8))
    try reopened.store.deletePipeline(named: "M31 v9")
    #expect(try reopened.store.pipelineNames() == ["IC 1848 doux"])
  }

  @Test("a name is trimmed alike for save, read and delete", .scratchDirectory)
  func testNameTrimmedAlike() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    try package.store.savePipeline(named: "M31 v9 \n", json: Data("{}".utf8))
    #expect(try package.store.pipeline(named: " M31 v9") == Data("{}".utf8))
    try package.store.deletePipeline(named: "M31 v9\t")
    #expect(try package.store.pipelineNames() == [])
    #expect(throws: ProjectStoreError.emptyName) {
      try package.store.savePipeline(named: "\n", json: Data("{}".utf8))
    }
  }

  @Test("an empty name or a body that is not text is refused, never stored", .scratchDirectory)
  func testEmptyNameRefused() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    #expect(throws: (any Error).self) {
      try package.store.savePipeline(named: "  ", json: Data("{}".utf8))
    }
    #expect(throws: ProjectStoreError.notText) {
      try package.store.savePipeline(named: "M31", json: Data([0xFF, 0xFE]))
    }
    #expect(try package.store.pipelineNames() == [])
  }
}

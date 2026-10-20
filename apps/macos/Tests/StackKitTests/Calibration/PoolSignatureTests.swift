import Foundation
import StackKit
import TestSupport
import Testing

/// Translated from `poolsig_test.go` and the `builtFromSet` half of `provenance_test.go`: a master
/// is reused only when the library can prove it was stacked from THESE frames.
@Suite("PoolSignature — which frames a master was stacked from")
struct PoolSignatureTests {
  static func write(_ name: String, bytes: Int, in dir: URL) throws -> String {
    let url = dir.appendingPathComponent(name)
    try Data(count: bytes).write(to: url)
    return url.path
  }

  @Test("order-independent; a resized, touched or dropped frame changes it", .scratchDirectory)
  func testPoolSignature_changes() throws {
    let dir = try ScratchDirectory.url
    let a = try Self.write("a.fits", bytes: 100, in: dir)
    let b = try Self.write("b.fits", bytes: 200, in: dir)
    let signature = PoolSignature.of([a, b])
    #expect(signature.count == 64)
    #expect(PoolSignature.of([b, a]) == signature)
    _ = try Self.write("b.fits", bytes: 999, in: dir)
    let resized = PoolSignature.of([a, b])
    #expect(resized != signature)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: b)
    #expect(PoolSignature.of([a, b]) != resized)
    #expect(PoolSignature.of([a]) != PoolSignature.of([a, b]))
  }

  @Test(
    "the .sig sidecar reads v2 (hash + count) and v1 (hash alone); absent is nil",
    .scratchDirectory, arguments: [("abc\n12", "abc", 12), ("abc\n", "abc", 0), ("  def  ", "def", 0)])
  func testPoolSignature_read(text: String, hash: String, count: Int) throws {
    let url = try ScratchDirectory.url.appendingPathComponent("m.sig")
    try Data(text.utf8).write(to: url)
    let read = try #require(PoolSignature.read(at: url.path))
    #expect(read.hash == hash)
    #expect(read.frameCount == count)
    #expect(PoolSignature.read(at: url.path + ".absent") == nil)
    #expect(PoolSignature.format(hash: "abc", frameCount: 12) == "abc\n12")
  }

  @Test("a master proves its pool only through a matching sidecar", .scratchDirectory)
  func testPoolSignature_builtFrom() throws {
    let dir = try ScratchDirectory.url
    let master = dir.appendingPathComponent("master_DARK.fits").path
    let mine = try ["d1.fits", "d2.fits", "d3.fits"].map { try Self.write($0, bytes: 10, in: dir) }
    let theirs = try ["x1.fits", "x2.fits"].map { try Self.write($0, bytes: 10, in: dir) }
    #expect(!PoolSignature.proves(master: master, builtFrom: mine))
    let sig = dir.appendingPathComponent("master_DARK.sig")
    try Data(PoolSignature.format(hash: PoolSignature.of(mine), frameCount: 3).utf8).write(to: sig)
    #expect(PoolSignature.proves(master: master, builtFrom: mine))
    try Data(PoolSignature.format(hash: PoolSignature.of(theirs), frameCount: 2).utf8).write(to: sig)
    #expect(!PoolSignature.proves(master: master, builtFrom: mine))
    try Data(PoolSignature.format(hash: PoolSignature.of(mine), frameCount: 3).utf8).write(to: sig)
    try Data("re-exported, different bytes".utf8).write(to: URL(fileURLWithPath: mine[0]))
    #expect(!PoolSignature.proves(master: master, builtFrom: mine))
  }
}

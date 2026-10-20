import Foundation
import StackKit
import Testing

@Suite("LineSplitter: lines out of arbitrary chunks")
struct LineSplitterTests {
  @Test(
    "chunks split anywhere give the same lines; CR dropped; the tail waits",
    arguments: [
      (["ready\nstatus: starting load\n"], ["ready", "status: starting load"]),
      (["rea", "dy\nlog: a", "bc\n"], ["ready", "log: abc"]),
      (["line\r\n", "\n"], ["line", ""]),
      (["no newline yet"], []),
      (["é\n"], ["é"]),
    ])
  func testLineSplitter_append(chunks: [String], expected: [String]) {
    let splitter = LineSplitter()
    let lines = chunks.flatMap { splitter.append(Data($0.utf8)) }
    #expect(lines == expected)
  }

  @Test("at end of stream the unfinished line is returned once")
  func testLineSplitter_flush() {
    let splitter = LineSplitter()
    #expect(splitter.append(Data("a\nlast".utf8)) == ["a"])
    #expect(splitter.flush() == ["last"])
    #expect(splitter.flush().isEmpty)
  }

  @Test("a multi-byte character cut between chunks is reassembled")
  func testLineSplitter_utf8AcrossChunks() {
    let splitter = LineSplitter()
    let bytes = Array("é\n".utf8)
    let lines = splitter.append(Data(bytes[..<1])) + splitter.append(Data(bytes[1...]))
    #expect(lines == ["é"])
  }
}

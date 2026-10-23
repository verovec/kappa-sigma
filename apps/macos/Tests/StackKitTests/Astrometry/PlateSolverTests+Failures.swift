import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// A solve that reads nothing says which part is missing — Siril's report (with its last
/// lines), the file, or the solution in it — never one message for all three.
extension PlateSolverTests {
  static func transcript(_ name: String) throws -> [String] {
    let url = try #require(
      Bundle.module.url(
        forResource: name, withExtension: "log", subdirectory: "Fixtures/platesolve"))
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
      .map { SirilLine(parsing: String($0)).text }
  }

  @Test("no report in the log: its last three lines are said", .scratchDirectory)
  func testSolved_NoReport() throws {
    let file = (try ScratchDirectory.url).appendingPathComponent("solved.fits")
    let log = ["Running command: platesolve", "", "Saving FITS: file solved.fits", "  done  "]
    #expect(
      throws: PlateSolveError.noReport(
        lastLines: "Running command: platesolve · Saving FITS: file solved.fits · done")
    ) { try PlateSolver.solved(log: log, file: file) }
  }

  @Test("a report without the file names the file", .scratchDirectory)
  func testSolved_NoFile() throws {
    let file = (try ScratchDirectory.url).appendingPathComponent("solved.fits")
    let log = try Self.transcript("m31-crop-solved")
    #expect(throws: PlateSolveError.noFile(path: file.path)) {
      try PlateSolver.solved(log: log, file: file)
    }
  }

  @Test("a file without a TAN solution is said as such; with one it is read", .scratchDirectory)
  func testSolved_FileWithoutSolution() throws {
    let scratch = try ScratchDirectory.url
    let log = try Self.transcript("m31-crop-solved")
    try TestFITS.write("bare.fits", in: scratch, width: 4, height: 3, cards: [:])
    let bare = scratch.appendingPathComponent("bare.fits")
    #expect(throws: PlateSolveError.noSolution(path: bare.path)) {
      try PlateSolver.solved(log: log, file: bare)
    }
    try Self.solvedFile(in: scratch)
    let solved = try PlateSolver.solved(
      log: log, file: scratch.appendingPathComponent("solved.fits"))
    #expect(solved.solution.scaleArcsecPerPx == 3.117)
  }
}

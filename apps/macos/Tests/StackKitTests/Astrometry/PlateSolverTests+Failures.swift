import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// A solve that reads nothing says which part is missing — Siril's report (with its last
/// lines), a report this reader missed, the file, or the solution in it — and where the log is.
extension PlateSolverTests {
  static let kept = URL(fileURLWithPath: "/support/siril-platesolve.failed.log")

  static func transcript(_ name: String) throws -> [String] {
    try Replay(name, succeeds: true).transcript.split(separator: "\n")
      .map { SirilLine(parsing: String($0)).text }
  }

  @Test("no report in the log: the last lines platesolve printed are said", .scratchDirectory)
  func testSolved_NoReport() throws {
    let file = (try ScratchDirectory.url).appendingPathComponent("solved.fits")
    let log = [
      "Running command: load", "Running command: platesolve", "Using provided focal length",
      "", "Findstar: processing", "Fetched 0 stars", "progress: , 0.00%",
      "1792673991: running command save", "Script execution finished successfully.",
      "closing pipes",
    ]
    #expect(
      throws: PlateSolveError.noReport(
        lastLines: "Using provided focal length · Findstar: processing · Fetched 0 stars",
        log: Self.kept.path)
    ) { try PlateSolver.solved(log: log, file: file, kept: Self.kept) }
  }

  @Test("Siril saying it solved, its report unread, is this reader's miss", .scratchDirectory)
  func testSolved_ReportUnread() throws {
    let file = (try ScratchDirectory.url).appendingPathComponent("solved.fits")
    let log = ["Running command: platesolve", "Image centre: 00 42 44", "Siril solve succeeded."]
    #expect(throws: PlateSolveError.reportUnread(log: Self.kept.path)) {
      try PlateSolver.solved(log: log, file: file, kept: Self.kept)
    }
  }

  @Test("a file that cannot be read is said unreadable", .scratchDirectory)
  func testSolved_UnreadableFile() throws {
    let file = (try ScratchDirectory.url).appendingPathComponent("solved.fits")
    try Data("not a FITS file".utf8).write(to: file)
    #expect(throws: PlateSolveError.unreadableFile(log: Self.kept.path)) {
      try PlateSolver.solved(
        log: try Self.transcript("m31-crop-solved"), file: file, kept: Self.kept)
    }
  }

  @Test("without a platesolve echo, the script's closing lines are still left out")
  func testTail_NoEcho_SkipsClosingLines() {
    let log = ["Findstar: processing", "Script execution finished successfully.", "closing pipes"]
    #expect(PlateSolver.platesolveTail(log) == "Findstar: processing")
  }

  @Test("no line at all is said « — », never an empty quote", .scratchDirectory)
  func testSolved_NoReport_Silent() throws {
    let file = (try ScratchDirectory.url).appendingPathComponent("solved.fits")
    #expect(throws: PlateSolveError.noReport(lastLines: "—", log: Self.kept.path)) {
      try PlateSolver.solved(log: ["", "  "], file: file, kept: Self.kept)
    }
  }

  @Test("a report without the file names the file", .scratchDirectory)
  func testSolved_NoFile() throws {
    let file = (try ScratchDirectory.url).appendingPathComponent("solved.fits")
    let log = try Self.transcript("m31-crop-solved")
    #expect(throws: PlateSolveError.noFile(log: Self.kept.path)) {
      try PlateSolver.solved(log: log, file: file, kept: Self.kept)
    }
  }

  @Test("a file without a TAN solution is said as such; with one it is read", .scratchDirectory)
  func testSolved_FileWithoutSolution() throws {
    let scratch = try ScratchDirectory.url
    let log = try Self.transcript("m31-crop-solved")
    try TestFITS.write("bare.fits", in: scratch, width: 4, height: 3, cards: [:])
    let bare = scratch.appendingPathComponent("bare.fits")
    #expect(throws: PlateSolveError.noSolution(log: Self.kept.path)) {
      try PlateSolver.solved(log: log, file: bare, kept: Self.kept)
    }
    try Self.solvedFile(in: scratch)
    let solved = try PlateSolver.solved(
      log: log, file: scratch.appendingPathComponent("solved.fits"), kept: Self.kept)
    #expect(solved.solution.scaleArcsecPerPx == 3.117)
  }
}

extension PlateSolverTests {
  @Test(
    "a failed solve's log is kept apart: neither a successful nor a silent retry replaces it",
    .scratchDirectory)
  func testLogKept() async throws {
    let scratch = try ScratchDirectory.url
    let support = scratch.appendingPathComponent("Support")
    let catalogues = try Self.catalogues()
    let failing = PlateSolver(
      siril: try Replay("m31-crop-failed", succeeds: false).runner, support: support,
      catalogues: catalogues)
    _ = try? await failing.solve(Self.image(), request: Self.request, scratch: scratch) { _ in }
    let solving = PlateSolver(
      siril: try Replay("m31-crop-solved", succeeds: true).runner, support: support,
      catalogues: catalogues)
    _ = try await solving.solve(Self.image(), request: Self.request, scratch: scratch) { _ in }
    let silent = PlateSolver(
      siril: SirilRunner { _, _, _ in throw SirilError.scriptFailed(exitCode: 1, hint: "") },
      support: support, catalogues: catalogues)
    _ = try? await silent.solve(Self.image(), request: Self.request, scratch: scratch) { _ in }

    let last = try String(contentsOf: solving.logFile, encoding: .utf8)
    let failed = try String(contentsOf: solving.failedLogFile, encoding: .utf8)
    #expect(last.contains("Siril solve succeeded") && failed.contains("Plate solving failed"))
    #expect(solving.failedLogFile.lastPathComponent == "siril-platesolve.failed.log")
  }
}

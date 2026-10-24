import Foundation
import TestSupport
import Testing

/// The repo hygiene gate (`scripts/hygiene.sh`, card 0064): the rules live once, in the script,
/// because the Linux `test continuity` job runs it without a Swift toolchain. These tests run it
/// on this repository and on scratch git repositories holding one forbidden item each.
@Suite("RepoHygiene — Swift only, no pixels, no data folders, no large blobs, planning local")
struct RepoHygieneTests {
  /// One forbidden item: the files to write (path → contents), the symlinks to make (path →
  /// target), and the words of the rule the gate must name.
  struct Case: Sendable, CustomTestStringConvertible {
    let item: String
    var files: [String: String] = [:]
    var links: [String: String] = [:]
    var removed: [String] = []
    let rule: String
    var testDescription: String { item }
  }

  static let cases: [Case] = [
    Case(item: "Go source", files: ["core/main.go": "package main\n"], rule: "non-Swift code"),
    Case(item: "go.mod", files: ["go.mod": "module x\n"], rule: "non-Swift code"),
    Case(item: "Dockerfile", files: ["Dockerfile": "FROM scratch\n"], rule: "non-Swift code"),
    Case(item: "compose file", files: ["compose.yaml": "services: {}\n"], rule: "non-Swift code"),
    Case(item: "Python script", files: ["tools/run.py": "print()\n"], rule: "non-Swift code"),
    Case(item: "frontend folder", files: ["frontend/index.html": "<p>\n"], rule: "'frontend/'"),
    Case(item: "nested frontend", files: ["apps/frontend/a.css": "p {}\n"], rule: "'frontend/'"),
    Case(item: "frontend under docs", files: ["docs/frontend/a.vue": "<p>\n"], rule: "'frontend/'"),
    Case(item: "file over 2 MB", files: ["notes.txt": big], rule: "files over 2 MB"),
    Case(item: "FITS under Tests", files: ["Tests/Fixtures/m.fits": "SIMPLE\n"], rule: "pixel"),
    Case(item: "PNG under Tests", files: ["Tests/Fixtures/m.png": "x\n"], rule: "pixel"),
    Case(item: "input folder", files: ["input/a.txt": "x\n"], rule: "'input/' exists"),
    Case(item: "output folder", files: ["output/a.txt": "x\n"], rule: "'output/' exists"),
    Case(item: "library symlink", links: ["library": "/tmp"], rule: "'library/' exists"),
    Case(item: "nested data symlink", links: ["apps/input": "/tmp"], rule: "symlinks tracked"),
    Case(item: "roadmap tracked", files: ["roadmap.md": "# r\n"], rule: "local planning files"),
    Case(
      item: "raw value as a label",
      files: ["apps/macos/Sources/RenderKit/V.swift": "Text(stage.rawValue)\n"],
      rule: "enum raw values"),
    Case(
      item: "literal colour",
      files: ["apps/macos/Sources/AstroStackApp/V.swift": "x.foregroundStyle(.red)\n"],
      rule: "literal colours"),
    Case(item: "broken link", files: ["docs/a.md": "[x](missing.md)\n"], rule: "broken relative"),
    Case(
      item: "French README with another command",
      files: ["README.fr.md": french.replacing("just run", with: "just build")],
      rule: "README.fr.md commands differ"),
    Case(
      item: "French README missing a section",
      files: ["README.fr.md": french.replacing("## Démarrer\n\n", with: "")],
      rule: "README.fr.md has 0 sections"),
    Case(
      item: "French README with a fenced heading only",
      files: [
        "README.fr.md": french.replacing("## Démarrer\n\n", with: "```text\n## x\n```\n\n")
      ],
      rule: "README.fr.md has 0 sections"),
    Case(
      item: "French README without the English one",
      files: ["README.fr.md": french], removed: ["README.md"], rule: "without the README.md"),
    Case(
      item: "broken link in the French README",
      files: ["README.fr.md": french + "[x](absent.md)\n"], rule: "broken relative"),
  ]

  /// The fixture README, with one section and one command.
  static let english =
    "# Clean\n\n## Start\n\n```bash\njust run   # go\n```\n\n[docs](docs/a.md)\n"

  /// Its French mirror: the same section count and command, the comment translated.
  static let french =
    "# Propre\n\n## Démarrer\n\n```bash\njust run   # vas-y\n```\n\n[docs](docs/a.md)\n"

  /// A text file one byte over the 2 MB limit.
  static let big = String(repeating: "a", count: 2_000_001)

  @Test(
    "the gate refuses a tree holding a forbidden item, naming its rule", .scratchDirectory,
    arguments: cases)
  func testNoForbiddenArtifacts_fixture(_ testCase: Case) throws {
    let tree = try Self.cleanTree()
    for (path, contents) in testCase.files {
      let url = tree.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    for path in testCase.removed {
      try FileManager.default.removeItem(at: tree.appendingPathComponent(path))
    }
    for (path, target) in testCase.links {
      let url = tree.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.createSymbolicLink(
        atPath: url.path, withDestinationPath: target)
    }
    try Self.git(["add", "-A", "-f"], in: tree)
    let gate = try Self.run("/bin/bash", ["scripts/hygiene.sh"], in: tree)
    #expect(gate.status == 1)
    #expect(gate.output.contains(testCase.rule), "\(gate.output)")
  }

  @Test("the gate passes a clean tree", .scratchDirectory)
  func testNoForbiddenArtifacts_cleanFixture() throws {
    let gate = try Self.run("/bin/bash", ["scripts/hygiene.sh"], in: try Self.cleanTree())
    #expect(gate.status == 0, "\(gate.output)")
  }

  @Test("the gate passes a French README that translates only the prose", .scratchDirectory)
  func testNoForbiddenArtifacts_frenchMirror() throws {
    let tree = try Self.cleanTree()
    try Self.french.write(
      to: tree.appendingPathComponent("README.fr.md"), atomically: true, encoding: .utf8)
    try Self.git(["add", "-A", "-f"], in: tree)
    let gate = try Self.run("/bin/bash", ["scripts/hygiene.sh"], in: tree)
    #expect(gate.status == 0, "\(gate.output)")
  }

  @Test("reference code under docs/ is allowed, as the language rule says", .scratchDirectory)
  func testNoForbiddenArtifacts_referenceSnippet() throws {
    let tree = try Self.cleanTree()
    try "print()\n".write(
      to: tree.appendingPathComponent("docs/snippet.py"), atomically: true, encoding: .utf8)
    try Self.git(["add", "-A", "-f"], in: tree)
    let gate = try Self.run("/bin/bash", ["scripts/hygiene.sh"], in: tree)
    #expect(gate.status == 0, "\(gate.output)")
  }

  @Test("the French README is judged as staged, not as edited on disk", .scratchDirectory)
  func testNoForbiddenArtifacts_frenchMirrorFromIndex() throws {
    let tree = try Self.cleanTree()
    let page = tree.appendingPathComponent("README.fr.md")
    try Self.french.write(to: page, atomically: true, encoding: .utf8)
    try Self.git(["add", "-A", "-f"], in: tree)
    try Self.french.replacing("just run", with: "just build").write(
      to: page, atomically: true, encoding: .utf8)
    let gate = try Self.run("/bin/bash", ["scripts/hygiene.sh"], in: tree)
    #expect(gate.status == 0, "\(gate.output)")
  }

  @Test("a French README in an unresolved merge conflict is reported", .scratchDirectory)
  func testNoForbiddenArtifacts_frenchMirrorConflict() throws {
    let tree = try Self.cleanTree()
    let page = tree.appendingPathComponent("README.fr.md")
    let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-am", "x"]
    try Self.french.write(to: page, atomically: true, encoding: .utf8)
    try Self.git(["add", "-A", "-f"], in: tree)
    try Self.git(commit, in: tree)
    try Self.git(["checkout", "-q", "-b", "other"], in: tree)
    try (Self.french + "un\n").write(to: page, atomically: true, encoding: .utf8)
    try Self.git(commit, in: tree)
    try Self.git(["checkout", "-q", "-"], in: tree)
    try (Self.french + "deux\n").write(to: page, atomically: true, encoding: .utf8)
    try Self.git(commit, in: tree)
    let merge = try Self.run("/usr/bin/git", ["merge", "-q", "other"], in: tree)
    try #require(merge.status != 0, "the merge conflicts")
    let gate = try Self.run("/bin/bash", ["scripts/hygiene.sh"], in: tree)
    #expect(gate.status == 1)
    #expect(gate.output.contains("cannot be read from the index"), "\(gate.output)")
  }

  /// A real repository lists more than a pipe holds after README.fr.md: the rule must still run
  /// (a `grep -q` that exits early would kill the writer, and `pipefail` would skip the check).
  @Test("the French README check runs on a tree whose file list outgrows a pipe", .scratchDirectory)
  func testNoForbiddenArtifacts_largeTree() throws {
    let tree = try Self.cleanTree()
    let filler = tree.appendingPathComponent("zz", isDirectory: true)
    try FileManager.default.createDirectory(at: filler, withIntermediateDirectories: true)
    // About 300 KB of names after README.fr.md: several pipe buffers, from few files.
    let long = String(repeating: "a", count: 240)
    for index in 0..<1200 {
      let name = filler.appendingPathComponent(long + String(format: "%04d", index))
      try #require(FileManager.default.createFile(atPath: name.path, contents: nil), "filler")
    }
    try Self.french.replacing("just run", with: "just build").write(
      to: tree.appendingPathComponent("README.fr.md"), atomically: true, encoding: .utf8)
    try Self.git(["add", "-A", "-f"], in: tree)
    let gate = try Self.run("/bin/bash", ["scripts/hygiene.sh"], in: tree)
    #expect(gate.status == 1)
    #expect(gate.output.contains("README.fr.md commands differ"), "\(gate.output)")
  }

  @Test("the gate passes this repository")
  func testNoForbiddenArtifacts_thisRepository() throws {
    let gate = try Self.run(
      "/bin/bash", ["scripts/hygiene.sh"], in: try Self.repositoryRoot(), isolated: false)
    #expect(gate.status == 0, "\(gate.output)")
  }

  // MARK: - Fixture trees

  /// The repository root: two levels above this package (`apps/macos`).
  static func repositoryRoot() throws -> URL {
    URL(fileURLWithPath: try ModuleBoundary.packageRoot(from: #filePath))
      .deletingLastPathComponent().deletingLastPathComponent()
  }

  /// A fresh git repository in the test's scratch folder with the gate's scripts and a README, all tracked.
  static func cleanTree() throws -> URL {
    let tree = try ScratchDirectory.url
    let scripts = tree.appendingPathComponent("scripts", isDirectory: true)
    try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
    for name in ["hygiene.sh", "check-links.sh"] {
      try FileManager.default.copyItem(
        at: try repositoryRoot().appendingPathComponent("scripts/\(name)"),
        to: scripts.appendingPathComponent(name))
    }
    try english.write(
      to: tree.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(
      at: tree.appendingPathComponent("docs"), withIntermediateDirectories: true)
    try "# A\n".write(
      to: tree.appendingPathComponent("docs/a.md"), atomically: true, encoding: .utf8)
    try git(["init", "-q"], in: tree)
    try git(["add", "-A", "-f"], in: tree)
    return tree
  }

  /// Runs git in the fixture tree and fails the test when it fails. `add -f`: a global ignore
  /// (`core.excludesFile`) must not keep a case's forbidden file out of the index.
  static func git(_ arguments: [String], in tree: URL) throws {
    let result = try run("/usr/bin/git", arguments, in: tree)
    try #require(result.status == 0, "git \(arguments.joined(separator: " ")): \(result.output)")
  }

  /// Runs `executable` in `directory` and returns its status with stdout and stderr together.
  /// In a fixture tree (`isolated`) the GIT_* variables a hook exports (GIT_DIR, GIT_INDEX_FILE…)
  /// are dropped, or git would act on the real repository; on the real one they are kept, so the
  /// gate judges the index being committed.
  static func run(
    _ executable: String, _ arguments: [String], in directory: URL, isolated: Bool = true
  ) throws
    -> (status: Int32, output: String)
  {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    if isolated {
      process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
  }
}

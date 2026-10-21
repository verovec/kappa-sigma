import Foundation
import ImageKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// StarNet is played by shell scripts: one per CLI generation, printing progress the way StarNet2
/// does (no line breaks) and copying its input to its output.
@Suite("StarNetRunner: CLI generations, progress, missing binary, failures", .serialized)
struct StarNetRunnerTests {
  /// StarNet2 (flags): answers `--machine-info`, refuses positional arguments.
  static let flagsScript = """
    #!/bin/sh
    if [ "$1" = "--machine-info" ]; then
      echo 'StarNet2 {"schema": "starnetastro.cli.machine-info/1", "version": "2.5"}'; exit 0
    fi
    [ "$1" = "-i" ] || { echo "positional arguments are not supported"; exit 2; }
    printf 'Working: 0.0%%Working: 8.3%%Working: 50.0%%'
    printf 'Working: 100.0%%Working: Done!\\n'
    cp "$2" "$4"
    """

  /// StarNet++ v2 (positional): no `--machine-info`.
  static let positionalScript = """
    #!/bin/sh
    [ "$1" = "--machine-info" ] && exit 1
    [ "$1" = "-i" ] && { echo "unknown option -i"; exit 2; }
    echo "Processing 25 %"; echo "Processing 100 %"
    cp "$1" "$2"
    """

  static func install(_ script: String, named name: String) throws -> String {
    let url = try ScratchDirectory.url.appendingPathComponent(name)
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
  }

  static func input() throws -> URL {
    let url = try ScratchDirectory.url.appendingPathComponent("in.tif")
    try Data("pixels".utf8).write(to: url)
    return url
  }

  @Test(
    "progress events are forwarded in order, with either CLI generation", .scratchDirectory,
    arguments: [("flags", [0, 8.3, 50, 100]), ("positional", [25, 100])])
  func testProgressAndMissingBinary(generation: String, expected: [Double]) async throws {
    let binary = try Self.install(
      generation == "flags" ? Self.flagsScript : Self.positionalScript, named: "starnet")
    let output = try ScratchDirectory.url.appendingPathComponent("out.tif")
    let seen = Mutex<[Double]>([])
    let tools = HostTools { _ in .found(path: binary, version: nil) }
    _ = try await StarNetRunner.located(by: tools).run(try Self.input(), output) { percent in
      seen.withLock { $0.append(percent) }
    }
    #expect(seen.withLock { $0 } == expected)
    #expect(try Data(contentsOf: output) == Data("pixels".utf8))
  }

  @Test("a missing StarNet is StarNetError.missing with the path HostTools looked at")
  func testMissingBinary() async throws {
    let tools = HostTools { _ in .missing(path: "/usr/local/bin/starnet2") }
    await #expect(throws: StarNetError.missing(path: "/usr/local/bin/starnet2")) {
      try await StarNetRunner.located(by: tools)
    }
  }

  @Test(
    "a failing StarNet throws its exit code and log; a silent one, the missing output",
    .scratchDirectory)
  func testFailures() async throws {
    let output = try ScratchDirectory.url.appendingPathComponent("out.tif")
    let failing = try Self.install("#!/bin/sh\necho 'model not found'\nexit 3\n", named: "failing")
    await #expect(throws: StarNetError.failed(exitCode: 3, log: "model not found\n")) {
      try await StarNetRunner.live(binary: failing).run(try Self.input(), output) { _ in }
    }
    let silent = try Self.install("#!/bin/sh\nexit 0\n", named: "silent")
    await #expect(throws: StarNetError.noOutput(path: output.path)) {
      try await StarNetRunner.live(binary: silent).run(try Self.input(), output) { _ in }
    }
  }

  @Test(
    "starless(of:) writes a 16-bit TIFF, runs StarNet on it and reads its output back",
    .scratchDirectory)
  func testStarlessRoundTrip() async throws {
    let binary = try Self.install(Self.flagsScript, named: "starnet")
    let image = AstroImage(
      width: 2, height: 1, planes: [[0, 1], [0.5, 0.25], [1, 0]],
      metadata: ImageMetadata(rowOrder: .topDown))
    let starless = try await StarNetRunner.live(binary: binary).starless(
      of: image, in: try ScratchDirectory.url.appendingPathComponent("scratch")
    ) { _ in }
    // The TIFF holds 16-bit samples: one level is the round trip's whole error.
    let worst = zip(starless.planes.joined(), image.planes.joined()).map { abs($0 - $1) }.max()
    #expect(starless.width == 2 && (worst ?? 1) <= Float(0.5 / 65535))
  }

  @Test(
    "percentages are read wherever they fall in the chunks; over 100 is not one",
    arguments: [
      (["Working: 8.", "3%Working: 16.7%"], [8.3, 16.7]), (["12 %", " 40%", "250%"], [12, 40]),
      (["no progress here\n"], []),
    ])
  func testProgressParsing(chunks: [String], expected: [Double]) {
    let parser = StarNetProgress()
    #expect(chunks.flatMap { parser.append(Data($0.utf8)) } == expected)
  }

  @Test(
    "--machine-info decides the generation; a failed probe is the positional one",
    arguments: [
      ("{\"schema\": \"starnetastro.cli.machine-info/1\"}", true, StarNetCLI.flags),
      ("banner {\"schema\": \"starnetastro.cli.machine-info/2\"}", true, .flags),
      ("{\"schema\": \"other\"}", true, .positional),
      ("{\"schema\": \"starnetastro.cli.machine-info/1\"}", false, .positional),
      ("usage: starnet++ in out", true, .positional),
    ])
  func testGeneration(output: String, clean: Bool, expected: StarNetCLI) {
    #expect(StarNetCLI.generation(machineInfo: output, exitedCleanly: clean) == expected)
  }
}

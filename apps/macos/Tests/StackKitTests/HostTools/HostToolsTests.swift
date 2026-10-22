import StackKit
import Testing

@Suite("HostTools: where each host tool is, and whether it can be used")
struct HostToolsTests {
  /// What the fake file system and `--version` probe answer for one case.
  struct Case: Sendable, CustomTestStringConvertible {
    let tool: HostTool
    let environment: [String: String]
    let executables: Set<String>
    let folders: Set<String>
    let sirilVersion: Result<String, SirilError>
    let expected: ToolStatus

    var testDescription: String { "\(tool) → \(expected)" }
  }

  static let siril = "/Applications/Siril.app/Contents/MacOS/siril-cli"
  static let graxpert = "/Applications/GraXpert.app"
  static let starnet = "/usr/local/bin/starnet2"

  static let cases: [Case] = [
    Case(
      tool: .siril, environment: [:], executables: [siril], folders: [],
      sirilVersion: .success("1.4.4"), expected: .found(path: siril, version: "1.4.4")),
    Case(
      tool: .siril, environment: [:], executables: [], folders: [],
      sirilVersion: .success("1.4.4"), expected: .missing(path: siril)),
    Case(
      tool: .siril, environment: [:], executables: [siril], folders: [],
      sirilVersion: .failure(.tooOld(version: "1.2.6")),
      expected: .tooOld(path: siril, version: "1.2.6")),
    Case(
      tool: .siril, environment: [:], executables: [siril], folders: [],
      sirilVersion: .failure(.notSiril(output: "bash")), expected: .missing(path: siril)),
    Case(
      tool: .siril, environment: ["SIRIL_BIN": "/opt/siril"], executables: ["/opt/siril"],
      folders: [], sirilVersion: .success("1.4.0"),
      expected: .found(path: "/opt/siril", version: "1.4.0")),
    Case(
      tool: .graxpert, environment: [:], executables: [], folders: [graxpert],
      sirilVersion: .success(""), expected: .found(path: graxpert, version: nil)),
    Case(
      tool: .graxpert, environment: [:], executables: [], folders: [],
      sirilVersion: .success(""), expected: .missing(path: graxpert)),
    Case(
      tool: .graxpert, environment: ["GRAXPERT_APP": "/Apps/G.app"], executables: [],
      folders: ["/Apps/G.app"], sirilVersion: .success(""),
      expected: .found(path: "/Apps/G.app", version: nil)),
    Case(
      tool: .starnet, environment: [:], executables: [starnet], folders: [],
      sirilVersion: .success(""), expected: .found(path: starnet, version: nil)),
    Case(
      tool: .starnet, environment: [:], executables: [], folders: [],
      sirilVersion: .success(""), expected: .missing(path: starnet)),
    Case(
      tool: .starnet, environment: ["STARNET_BIN": "/opt/starnet2"], executables: [],
      folders: [], sirilVersion: .success(""), expected: .missing(path: "/opt/starnet2")),
  ]

  @Test("found, missing or too old, for each tool and its environment override", arguments: cases)
  func testStatus(_ testCase: Case) async {
    let probe = HostTools.Probe(
      isExecutable: { testCase.executables.contains($0) },
      isApp: { testCase.folders.contains($0) },
      sirilVersion: { _ in try testCase.sirilVersion.get() })
    let tools = HostTools.live(environment: testCase.environment, probe: probe)

    #expect(await tools.locate(testCase.tool) == testCase.expected)
  }

  @Test(
    "only a found tool can be used; its path is the one that was looked at",
    arguments: zip(
      [
        ToolStatus.found(path: "/a", version: nil), .missing(path: "/b"),
        .tooOld(path: "/c", version: "1.2"),
      ],
      [(true, "/a"), (false, "/b"), (false, "/c")]))
  func testStatusAccessors(_ status: ToolStatus, _ expected: (usable: Bool, path: String)) {
    #expect(status.isUsable == expected.usable)
    #expect(status.path == expected.path)
  }

  @Test("a Siril whose --version hangs counts as unusable once the timeout passes")
  func testHangingVersionTimesOut() async {
    let probe = HostTools.Probe(
      isExecutable: { _ in true }, isApp: { _ in false },
      sirilVersion: { _ in
        // Never answers: the stream yields nothing and only ends when the probe is cancelled.
        let (silence, continuation) = AsyncStream<Never>.makeStream()
        defer { continuation.finish() }
        for await _ in silence {}
        try Task.checkCancellation()
        return "1.4.4"
      })
    let tools = HostTools.live(environment: [:], probe: probe, timeout: .milliseconds(50))

    #expect(await tools.locate(.siril) == .missing(path: Self.siril))
  }
}

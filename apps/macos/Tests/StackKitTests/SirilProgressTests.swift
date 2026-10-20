import StackKit
import Testing

/// The output handling of the legacy runner (`runner.go`, `runner_test.go`) plus the `status:`
/// lines of Siril's pipe mode.
@Suite("SirilOutput: log, progress and status lines; error hints; limits; version")
struct SirilProgressTests {
  static let twoImages =
    "Provided filtering options do not allow at least two images to be processed."
  static let diskSpace =
    "Not enough free disk space to perform this operation: 237.4 MiB available for 625.3 MiB needed"

  /// A log: one `\n` after each line.
  static func log(_ lines: String...) -> String { lines.map { $0 + "\n" }.joined() }

  @Test(
    "each line: prefix stripped, percent read the legacy way, status recognised",
    arguments: [
      ("log: 10 images loaded", SirilLine(text: "10 images loaded", percent: nil, status: nil)),
      ("log:Stacking", SirilLine(text: "Stacking", percent: nil, status: nil)),
      (
        "progress: Registration, 45%",
        SirilLine(text: "progress: Registration, 45%", percent: 45, status: nil)
      ),
      ("progress: 50 %", SirilLine(text: "progress: 50 %", percent: 50, status: nil)),
      // Leftmost match of (\d+)\s?% — the legacy quirk, kept for parity.
      (
        "progress: Script execution failed., 100.00%",
        SirilLine(text: "progress: Script execution failed., 100.00%", percent: 0, status: nil)
      ),
      ("progress: 45.67%", SirilLine(text: "progress: 45.67%", percent: 67, status: nil)),
      ("progress: 150%", SirilLine(text: "progress: 150%", percent: nil, status: nil)),
      (
        "status: starting stack",
        SirilLine(text: "status: starting stack", percent: nil, status: .starting)
      ),
      (
        "status: success stack",
        SirilLine(text: "status: success stack", percent: nil, status: .success)
      ),
      ("status: error stack", SirilLine(text: "status: error stack", percent: nil, status: .error)),
      ("status: exit", SirilLine(text: "status: exit", percent: nil, status: .exit)),
      ("ready", SirilLine(text: "ready", percent: nil, status: nil)),
    ])
  func testParsesThreePrefixes(raw: String, expected: SirilLine) {
    #expect(SirilLine(parsing: raw) == expected)
  }

  @Test(
    "error hints (runner_test.go TestSirilErrorHint)",
    arguments: [
      (
        log(
          "log: Searching for sequences...", "log: Reading sequence failed: r_light.seq",
          "log: \(twoImages)", "log: Error in line 12: 'stack r_pp_light_ rej g 0.3 0.05'.",
          "log: Script execution failed."),
        "\(twoImages); Error in line 12: 'stack r_pp_light_ rej g 0.3 0.05'."
      ),
      (
        log("log: Reading sequence failed: r_light.seq", "log: cannot open image light_00002.fits"),
        "cannot open image light_00002.fits"
      ),
      (log("log: Reading sequence failed: r_light.seq"), "Reading sequence failed: r_light.seq"),
      (log("log: \(twoImages)", "progress: Script execution failed., 100.00%"), twoImages),
      (
        log(
          "log: Conversion succeeded, 10 file(s) created for 10 input file(s) "
            + "(10 image(s) converted, 0 failed)", "log: \(diskSpace)",
          "log: Not enough space to save the output images, aborting",
          "log: Registration aborted.", "log: Finalizing sequence processing failed.",
          "progress: Script execution failed., 100.00%"),
        "\(diskSpace); Not enough space to save the output images, aborting; Registration aborted."
      ),
      (log("log: 10 images loaded"), ""),
    ])
  func testSirilOutput_errorHint(log: String, expected: String) {
    #expect(SirilOutput.errorHint(log: log) == expected)
  }

  @Test(
    "CPU and memory limits go right after `requires` (runner_test.go TestLimitsApply)",
    arguments: [
      (
        SirilLimits(maxCPUs: 10, memoryRatio: 0.5),
        "requires 1.2.0\nsetext fits\nstack r_ rej 3 3\n",
        "requires 1.2.0\nsetcpu 10\nsetmem 0.50\nsetext fits\nstack r_ rej 3 3\n"
      ),
      (
        SirilLimits(), "requires 1.2.0\nsetext fits\nstack r_ rej 3 3\n",
        "requires 1.2.0\nsetext fits\nstack r_ rej 3 3\n"
      ),
      (SirilLimits(maxCPUs: 8), "load light\n", "load light\n"),
    ])
  func testSirilLimits_apply(limits: SirilLimits, script: String, expected: String) {
    #expect(limits.apply(to: script) == expected)
  }

  @Test(
    "the version is read and must be at least 1.4",
    arguments: [
      ("siril 1.4.4\n", Optional("1.4.4")), ("Siril v1.4\n", "1.4"), ("siril 1.2.6\n", nil),
      ("Siril is started as macOS application\nsiril 1.4.0\n", "1.4.0"), ("hello\n", nil),
    ])
  func testSirilVersion_parse(output: String, expected: String?) {
    #expect((try? SirilVersion.parse(output)) == expected)
  }
}

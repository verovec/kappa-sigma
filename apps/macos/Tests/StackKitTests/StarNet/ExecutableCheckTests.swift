import Foundation
import StackKit
import TestSupport
import Testing

@Suite("ExecutableCheck: an Intel-only tool needs Rosetta on Apple silicon")
struct ExecutableCheckTests {
  /// A Mach-O header (thin, little-endian) of `cpu`, or a universal one of `cpus`.
  static func header(thin cpu: UInt32) -> [UInt8] {
    [0xCF, 0xFA, 0xED, 0xFE] + withUnsafeBytes(of: cpu.littleEndian, Array.init)
      + [UInt8](
        repeating: 0, count: 24)
  }

  static func header(fat cpus: [UInt32]) -> [UInt8] {
    var bytes: [UInt8] =
      [0xCA, 0xFE, 0xBA, 0xBE]
      + withUnsafeBytes(
        of: UInt32(cpus.count).bigEndian, Array.init)
    for cpu in cpus {
      bytes += withUnsafeBytes(of: cpu.bigEndian, Array.init) + [UInt8](repeating: 0, count: 16)
    }
    return bytes
  }

  static let (x86, arm) = (UInt32(0x0100_0007), UInt32(0x0100_000C))

  @Test(
    "the architectures of thin, universal and non-Mach-O files; the refusal without Rosetta",
    .scratchDirectory,
    arguments: [
      ("intel", Self.header(thin: Self.x86), ["x86_64"], true),
      ("apple", Self.header(thin: Self.arm), ["arm64"], false),
      ("universal", Self.header(fat: [Self.x86, Self.arm]), ["x86_64", "arm64"], false),
      ("script", Array("#!/bin/sh\necho hi\n".utf8), [], false),
    ])
  func testArchitectures(name: String, bytes: [UInt8], expected: [String], refused: Bool) throws {
    let url = try ScratchDirectory.url.appendingPathComponent(name)
    try Data(bytes).write(to: url)
    #expect(ExecutableCheck.architectures(of: url) == expected)
    let reason = ExecutableCheck.refusal(path: url.path, rosettaInstalled: false)
    #expect((reason != nil) == refused)
    if refused { #expect(reason?.contains("install Rosetta") == true) }
    #expect(ExecutableCheck.refusal(path: url.path, rosettaInstalled: true) == nil)
  }

  @Test("a StarNet this Mac cannot launch is StarNetError.cannotRun, with the reason")
  func testCannotRun() async throws {
    let tools = HostTools { _ in .found(path: "/usr/local/bin/starnet2", version: nil) }
    await #expect(
      throws: StarNetError.cannotRun(path: "/usr/local/bin/starnet2", reason: "needs Rosetta")
    ) {
      try await StarNetRunner.located(by: tools) { _ in "needs Rosetta" }
    }
  }
}

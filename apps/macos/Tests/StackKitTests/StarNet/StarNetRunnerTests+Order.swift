import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

extension StarNetRunnerTests {
  @Test(
    "a bottom-up original gets its starless back bottom-up, pixel for pixel", .scratchDirectory)
  func testStarlessKeepsRowOrder() async throws {
    let binary = try Self.install(Self.flagsScript, named: "starnet")
    let rows: [Float] = [0, 0.25, 0.5, 1]
    let scratch = try ScratchDirectory.url.appendingPathComponent("scratch")
    let starless = try await StarNetRunner.live(binary: binary).starless(
      of: AstroImage(
        width: 1, height: 4, planes: [rows, rows, rows],
        metadata: ImageMetadata(rowOrder: .bottomUp)),
      in: scratch
    ) { _ in }
    #expect(starless.metadata.rowOrder == .bottomUp)
    let worst = zip(starless.planes[0], rows).map { abs($0 - $1) }.max() ?? 1
    #expect(worst <= Float(0.5 / 65535))
  }

  @Test(
    "a --machine-info probe that hangs is stopped and refused, never guessed", .scratchDirectory)
  func testProbeTimeout() async throws {
    let binary = try Self.install("#!/bin/sh\nsleep 30\n", named: "hanging")
    let start = ContinuousClock.now
    await #expect(throws: StarNetError.probeTimedOut(path: binary)) {
      try await StarNetCLI.detect(binary: binary, timeout: .milliseconds(300))
    }
    #expect(ContinuousClock.now - start < .seconds(20))
  }
}

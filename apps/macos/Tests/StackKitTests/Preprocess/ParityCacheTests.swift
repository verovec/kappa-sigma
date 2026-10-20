import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

/// `ParityCache` is `parityCache`: one probe per session, a mirrored session flipped and verified,
/// an unverifiable flip undone, an unsolved session left alone with the recorded note.
@Suite("ParityCache — one probe per session, flips verified")
struct ParityCacheTests {
  static func group(night: String = "2024-03-01", filter: String = "L") -> FrameSet {
    FrameSet(
      key: SetKey(type: .light, object: "T", filter: filter, gain: 100, offset: 10, session: night),
      frames: [CaptureFrame(path: "/a"), CaptureFrame(path: "/b")], indices: [0, 1])
  }

  /// A group folder with two calibrated frames.
  static func folder(_ name: String) throws -> URL {
    let folder = try ScratchDirectory.url.appendingPathComponent(name)
    for index in 1...2 {
      try PipelineSiril.frame(
        folder.appendingPathComponent(String(format: "pp_light_%05d.fits", index)))
    }
    return folder
  }

  /// det(CD) per successive solve, the last one repeating.
  static func solves(_ values: [Double?]) -> @Sendable (String) -> Double? {
    let next = Mutex(0)
    return { _ in
      let index = next.withLock { count -> Int in
        defer { count += 1 }
        return count
      }
      return values[min(index, values.count - 1)]
    }
  }

  @Test(
    "unsolved: the recorded note, nothing flipped, and the session is not probed again",
    .scratchDirectory)
  func testUnsolved() async throws {
    let siril = PipelineSiril()
    let cache = ParityCache(runner: siril.runner)
    let first = try await cache.correct(
      Self.group(), folder: try Self.folder("g0"), base: "pp_light")
    #expect(
      first.note == "session 0: parity undetermined (plate-solve failed) — flip not applied"
        && !first.flipped)
    let other = try await cache.correct(
      Self.group(filter: "R"), folder: try Self.folder("g1"), base: "pp_light")
    #expect(other.note.isEmpty && siril.calls.count == 1)
  }

  @Test(
    """
    East-left is left alone; mirrored is flipped and verified; a flip that re-reads mirrored \
    is undone
    """,
    .scratchDirectory)
  func testFlips() async throws {
    let eastLeft = PipelineSiril(solve: Self.solves([-1]))
    let kept = try await ParityCache(runner: eastLeft.runner).correct(
      Self.group(), folder: try Self.folder("e"), base: "pp_light")
    #expect(kept.note.isEmpty && !kept.flipped)

    let mirrored = PipelineSiril(solve: Self.solves([1, -1]))
    let fixed = try await ParityCache(runner: mirrored.runner).correct(
      Self.group(), folder: try Self.folder("m"), base: "pp_light")
    #expect(fixed.flipped && fixed.note.contains("parity flip, verified"))
    #expect(
      mirrored.calls.contains {
        $0.script.contains("load pp_light_00002\nmirrorx\nsave pp_light_00002")
      })

    let stubborn = PipelineSiril(solve: Self.solves([1, 1]))
    let cache = ParityCache(runner: stubborn.runner)
    let undone = try await cache.correct(
      Self.group(), folder: try Self.folder("s"), base: "pp_light")
    #expect(!undone.flipped && undone.note.contains("did not verify"))
    #expect(stubborn.calls.filter { $0.script.contains("mirrorx") }.count == 2)
    let sibling = try await cache.correct(
      Self.group(filter: "R"), folder: try Self.folder("s2"), base: "pp_light")
    #expect(
      !sibling.flipped && sibling.note.isEmpty, "an unreliable session is cached as undetermined")
  }

  @Test(
    """
    a flip Siril cannot run leaves the frames unmirrored; an unsolvable re-probe keeps the flip; \
    a failed undo says the frames may be mirrored
    """,
    .scratchDirectory)
  func testFlipFailures() async throws {
    let failing = PipelineSiril(solve: Self.solves([1]), fails: { $0.contains("mirrorx") })
    let unflipped = try await ParityCache(runner: failing.runner).correct(
      Self.group(), folder: try Self.folder("f"), base: "pp_light")
    #expect(
      !unflipped.flipped && unflipped.note.hasPrefix("session 0: parity flip failed (")
        && unflipped.note.hasSuffix("— frames left unmirrored"))

    let unsure = PipelineSiril(solve: Self.solves([1, nil]))
    let kept = try await ParityCache(runner: unsure.runner).correct(
      Self.group(), folder: try Self.folder("u"), base: "pp_light")
    #expect(
      kept.flipped
        && kept.note == "session 0: mirror-corrected (parity flip; verification probe undetermined)"
    )

    let mirrors = Mutex(0)
    // The flip runs, the re-probe still reads mirrored, the undo fails.
    let stuck = PipelineSiril(
      solve: Self.solves([1, 1]),
      fails: { script in
        script.contains("mirrorx")
          && mirrors.withLock { count in
            count += 1
            return count == 2
          }
      })
    let left = try await ParityCache(runner: stuck.runner).correct(
      Self.group(), folder: try Self.folder("x"), base: "pp_light")
    #expect(
      left.flipped && left.note.hasPrefix("session 0: parity flip did not verify AND undo failed")
        && left.note.hasSuffix("— frames may be mirrored"))
  }
}

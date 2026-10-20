package import Foundation

/// Mirror parity per physical session, shared by every channel of a run (`parityCache`): a night
/// shot through another optical train (a star diagonal) is mirrored and can never co-register by
/// rotation. One calibrated frame per session is plate-solved without flipping; a session that is
/// not East-left gets `mirrorx` on every frame, verified by a second probe.
package actor ParityCache {
  private let normalizer: ParityNormalizer
  /// Session key → sign (−1/+1), or 0 when undetermined.
  private var seen: [String: Int] = [:]

  /// A cache probing through `runner`.
  package init(runner: SirilRunner, coordinates: String? = nil) {
    normalizer = ParityNormalizer(runner: runner, coordinates: coordinates)
  }

  /// The session of `group`: parity belongs to the optical train, so filter and exposure are out;
  /// camera settings and the night are in (`parityKey`, session id 0 = this capture).
  static func key(_ group: FrameSet) -> String {
    let key = group.key
    return "0|\(key.gain)|\(key.offset)|\(key.bin)|\(key.tempBucketC)|\(key.session)"
  }

  /// Flips `group`'s calibrated frames (`<base>_00001…` in `folder`) when its session is mirrored;
  /// returns the note ("" when nothing happened) and whether the frames are mirrored on disk.
  package func correct(_ group: FrameSet, folder: URL, base: String) async throws -> (
    note: String, flipped: Bool
  ) {
    let names = (1...max(1, group.count)).map { base + String(format: "_%05d", $0) }
    let first = folder.appendingPathComponent(names[0] + ".fits").path
    let key = Self.key(group)
    var note = ""
    let sign: Int
    if let cached = seen[key] {
      sign = cached
    } else {
      let probe = try await normalizer.probeWithReason(first)
      (sign, seen[key]) = (probe.sign, probe.sign)
      if !probe.reason.isEmpty { note = "session 0: " + probe.reason }
    }
    guard sign > 0 else { return (note, false) }
    do {
      _ = try await normalizer.runner.run(SirilScripts.mirrorFrames(names), folder) { _ in }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return (
        "session 0: parity flip failed (\(ChannelStacker.describe(error))) "
          + "— frames left unmirrored",
        false
      )
    }
    return try await verify(key, names: names, folder: folder, first: first)
  }

  /// Re-probes after the flip: still mirrored means the readings cannot be trusted, so the flip is
  /// undone and the session cached as undetermined (`verifyFlip`).
  private func verify(_ key: String, names: [String], folder: URL, first: String) async throws
    -> (note: String, flipped: Bool)
  {
    switch try await normalizer.probe(first) {
    case -1:
      return (
        "session 0: mirror-corrected (parity flip, verified) so it stacks with the other sessions",
        true
      )
    case 0:
      return ("session 0: mirror-corrected (parity flip; verification probe undetermined)", true)
    default: break
    }
    seen[key] = 0
    do {
      _ = try await normalizer.runner.run(SirilScripts.mirrorFrames(names), folder) { _ in }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return (
        "session 0: parity flip did not verify AND undo failed "
          + "(\(ChannelStacker.describe(error))) — frames may be mirrored",
        true
      )
    }
    return (
      "session 0: parity flip did not verify (probe still reads mirrored) "
        + "— frames left as captured",
      false
    )
  }
}

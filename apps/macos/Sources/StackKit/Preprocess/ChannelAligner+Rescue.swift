internal import Foundation

extension ChannelAligner {
  /// Copies each channel whose registered frame exists to `out/aligned_<tag>.fits`
  /// (`collectAligned`); the rest are failed.
  static func collect(
    folder: URL, out: URL, ordered: [String], journal: inout PreprocessJournal
  ) -> (aligned: [String: String], failed: [String]) {
    var aligned: [String: String] = [:]
    var failed: [String] = []
    for (index, filter) in ordered.enumerated() {
      let registered = folder.appendingPathComponent(String(format: "r_ch_%05d.fits", index + 1))
      guard FileManager.default.fileExists(atPath: registered.path) else {
        failed.append(filter)
        continue
      }
      let name = "aligned_" + ChannelTag.of(filter)
      do {
        try FileReplace.copy(registered, over: out.appendingPathComponent(name + ".fits"))
        aligned[filter] = name
      } catch {
        journal.warn(
          "channel \(filter): alignment copy failed: \(ChannelStacker.describe(error))", live: false
        )
        failed.append(filter)
      }
    }
    return (aligned, failed)
  }

  /// Re-registers each failed master alone against the first aligned channel (`retryPairAlign`);
  /// returns the channels still failing.
  func rescue(
    _ failed: [String], masters: [String: String], aligned: inout [String: String], work: URL,
    out: URL
  ) async throws -> [String] {
    guard let first = Self.ordered(aligned.keys).first, let name = aligned[first], !failed.isEmpty
    else { return failed }
    let reference = out.appendingPathComponent(name + ".fits").path
    var still: [String] = []
    for filter in failed {
      let folder = work.appendingPathComponent("pair_" + ChannelTag.sanitize(filter))
      if try await pair(
        reference: reference, master: masters[filter] ?? "", filter: filter, folder: folder,
        out: out)
      {
        aligned[filter] = "aligned_" + ChannelTag.of(filter)
      } else {
        still.append(filter)
      }
    }
    return still
  }

  /// One master registered onto the pinned reference (`pairAlignOne`); false on any failure.
  private func pair(reference: String, master: String, filter: String, folder: URL, out: URL)
    async throws -> Bool
  {
    do {
      try Self.link([reference, master], names: ["pair", "pair"], into: folder)
      _ = try await runner.run(SirilScripts.alignPair(seq: "pair"), folder) { _ in }
      let registered = folder.appendingPathComponent("r_pair_00002.fits")
      guard FileManager.default.fileExists(atPath: registered.path) else { return false }
      try FileReplace.copy(
        registered, over: out.appendingPathComponent("aligned_\(ChannelTag.of(filter)).fits"))
      return true
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return false
    }
  }
}

package import Foundation

/// Co-registers the channel masters onto one grid before the colour combine (`alignChannels`).
///
/// Parity first, then a joint two-pass registration; a channel that misses it gets a pair
/// rescue against an aligned channel; what a channel that still fails costs is decided by
/// `policy`. Every degradation is a warning, never silent.
package struct ChannelAligner: Sendable {
  package var runner: SirilRunner
  package var parity: ParityNormalizer

  /// An aligner running through `runner`.
  package init(runner: SirilRunner, coordinates: String? = nil) {
    self.runner = runner
    parity = ParityNormalizer(runner: runner, coordinates: coordinates)
  }

  /// The channels in canonical order (`orderedFilters`): the filter list first, the rest sorted.
  package static func ordered(_ filters: some Collection<String>) -> [String] {
    filters.sorted(by: Filter.less)
  }

  /// Aligns `masters` (filter → absolute master path) in `folder`, writing `out/aligned_<tag>.fits`;
  /// returns filter → the extension-less basename (in `out`) the combine loads.
  package func align(
    _ masters: [String: String], folder: URL, out: URL, journal: inout PreprocessJournal
  ) async throws -> [String: String] {
    let unaligned = Dictionary(
      uniqueKeysWithValues: masters.keys.map { ($0, "master_" + ChannelTag.of($0)) })
    guard masters.count >= 2 else { return unaligned }
    let ordered = Self.ordered(masters.keys)
    if let mismatch = Self.dimensionMismatch(masters, ordered: ordered) {
      journal.warn(mismatch)
      return unaligned
    }
    try await parity.normalize(masters, ordered: ordered, journal: &journal)
    do {
      try Self.link(ordered.map { masters[$0] ?? "" }, names: ordered, into: folder)
      _ = try await runner.run(SirilScripts.alignMasters(seq: "ch"), folder) { _ in }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      journal.warn(
        "cross-channel alignment failed, using unaligned channels: "
          + ChannelStacker.describe(error),
        live: false)
      return unaligned
    }
    var (aligned, failed) = Self.collect(
      folder: folder, out: out, ordered: ordered, journal: &journal)
    failed = try await rescue(
      failed, masters: masters, aligned: &aligned, work: folder.deletingLastPathComponent(),
      out: out)
    return Self.policy(aligned: aligned, unaligned: unaligned, failed: failed, journal: &journal)
  }

  /// What each still-unregistered channel costs (`applyAlignPolicy`): a failed R/G/B makes a true
  /// colour combine impossible (all unaligned); a failed L is dropped; any other channel omitted.
  static func policy(
    aligned: [String: String], unaligned: [String: String], failed: [String],
    journal: inout PreprocessJournal
  ) -> [String: String] {
    for filter in failed {
      switch filter {
      case "R", "G", "B":
        journal.warn("channel \(filter) could not be co-registered — combining unaligned channels")
        return unaligned
      case "L": journal.warn("L could not be co-registered — combining without luminance")
      default: journal.warn("\(filter) could not be co-registered — omitted from the composite")
      }
    }
    return aligned
  }

  /// A warning naming every master's size when they differ (`masterDimsMismatch`).
  static func dimensionMismatch(_ masters: [String: String], ordered: [String]) -> String? {
    let sizes = ordered.map { DimensionGuard.dimensions(masters[$0] ?? "") }
    guard Set(sizes.map { "\($0?.width ?? 0)×\($0?.height ?? 0)" }).count > 1 else { return nil }
    let listed = zip(ordered, sizes).map { "\($0) \($1?.width ?? 0)×\($1?.height ?? 0)" }
    return "channel masters have mixed dimensions (\(listed.joined(separator: ", "))) — "
      + "co-registration and the colour combine are impossible; combining unaligned channels"
  }

  /// `0_<F>.fits`, `1_<F>.fits`… so Siril's `link` numbers the sequence in channel order.
  static func link(_ paths: [String], names: [String], into folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (index, (path, name)) in zip(paths, names).enumerated() {
      let link = folder.appendingPathComponent("\(index)_\(name).fits")
      try? FileManager.default.removeItem(at: link)
      try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: path)
    }
  }
}

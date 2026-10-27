package import FilterKit
package import Foundation
internal import ImageKit

/// Separates a registered dual-band colour master into pseudo-Hα and pseudo-[OIII]
/// (`splitDuoband`, `dualSetChannels`).
///
/// Hα at 656 nm lands on the red pixels; [OIII] at 500.7 nm on the shoulder between green and
/// blue, so the per-pixel maximum keeps whichever pixel caught the line (a mean would fold the
/// weaker one in and cost SNR). The REGISTERED master is split: the layers are composited pixel
/// for pixel over the colour base — the broadband master, or the first line lane when the run
/// has none.
package enum DualbandSplit {
  /// The synthetic layer's file stem of a line (`syn_Ha`).
  private static func stem(_ line: Filter) -> String { "syn_" + line.rawValue }

  /// Why a master could not be split.
  package enum Failure: Error, CustomStringConvertible {
    case planes(Int)

    package var description: String {
      switch self {
      case .planes(let count):
        "colour master has \(count) plane(s), need 3 to separate the two lines"
      }
    }
  }

  /// Writes `out/syn_<red>.fits` (the red plane) and `out/syn_<greenBlue>.fits` (the per-pixel
  /// maximum of green and blue) from `master` (left untouched), with its descriptive header, for
  /// the clip's `lines` (`FilterSet.lines`, the one table), except the lines in `skipping`
  /// (another lane already wrote them); returns their basenames.
  package static func split(
    _ master: URL, out: URL, lines: FilterSet.Lines, skipping: Set<Filter> = []
  ) throws -> (red: String, greenBlue: String) {
    let file = try FITSFile.read(at: master)
    let image = try file.image()
    guard image.planes.count >= 3 else { throw Failure.planes(image.planes.count) }
    let oiii = zip(image.planes[1], image.planes[2]).map { $0 > $1 ? $0 : $1 }
    let names = (red: stem(lines.red), greenBlue: stem(lines.greenBlue))
    let planes = [
      (lines.red, names.red, image.planes[0]), (lines.greenBlue, names.greenBlue, oiii),
    ]
    for (line, name, plane) in planes where !skipping.contains(line) {
      try FITSFile.create(
        AstroImage(
          width: image.width, height: image.height, planes: [plane], metadata: image.metadata),
        keeping: file.header, at: out.appendingPathComponent(name + ".fits"))
    }
    return names
  }

  /// The channel map with every line-clip lane turned into its lines (`dualSetChannels`), and
  /// the note the run shows; the map unchanged (no note) when the run did not split.
  ///
  /// A lane leaves the map whatever happens: it is not a colour channel. When the line lanes are
  /// the only channels (`lineBase`) the first (`FilterSet` order) becomes the colour base itself,
  /// unsplit, and the other lanes' lines go over it; an unsplittable master, or one the alignment
  /// could not register (`registered`), costs only its emission layers. A line two lanes both
  /// carry — or that the base already holds — is kept from the first and the other's is noted.
  package static func channels(_ channels: [String: String], out: URL, registered: Bool = true)
    -> (
      channels: [String: String], note: String?
    )
  {
    var lanes = FilterSetLanes.lineLanes(in: channels.keys)
    guard let first = lanes.first, let base = channels[first] else { return (channels, nil) }
    var kept = channels.filter { !lanes.contains($0.key) }
    var notes: [String] = []
    // Lines a lane may not write: the base lane's own, when it stands in for the colour base.
    var taken: Set<Filter> = []
    if lanes.count == channels.count {
      // The first line lane is the colour base, its own lines inside it; the others go over it.
      kept[FilterSetLanes.baseFilter(of: first)] = base
      lanes.removeFirst()
      if let lines = FilterSetLanes.lineSet(of: first)?.lines {
        taken = [lines.red, lines.greenBlue]
      }
      notes.append(
        "no broadband master in this run — the \(first) stack is the colour base, unsplit, its "
          + "lines inside it; no continuum scale can be fitted without a broadband reference")
    }
    // Unregistered layers would sit offset from the base, every star doubled.
    guard registered else {
      return (
        kept,
        (notes + [
          "line-clip master not registered onto the base grid — emission layers skipped, "
            + "finishing on the colour base alone"
        ]).joined(separator: "; ")
      )
    }
    var added: [(lane: String, lines: [String])] = []
    for lane in lanes {
      guard let master = channels[lane], let set = FilterSetLanes.lineSet(of: lane) else {
        continue
      }
      let lines = splitLane(set, master: master, out: out, into: &kept, taken: taken, notes: &notes)
      if !lines.isEmpty { added.append((lane, lines)) }
    }
    return (kept, (lead(added) + notes).joined(separator: "; "))
  }

  /// Whether a line-clip lane stands in for the colour base.
  ///
  /// The line lanes are the only channels, so nothing else could be the base. The one predicate
  /// the split and the continuum fit share (a custom-named colour or mono channel beside the
  /// lanes keeps its place).
  package static func lineBase(in lanes: some Collection<String>) -> Bool {
    let lines = FilterSetLanes.lineLanes(in: lanes)
    return !lines.isEmpty && lines.count == lanes.count
  }

  /// What the lanes that added a layer became, each line with the plane it came from; nothing
  /// when no lane added one (the skip reasons say it all).
  private static func lead(_ added: [(lane: String, lines: [String])]) -> [String] {
    guard !added.isEmpty else { return [] }
    let words = added.map { entry in
      "the \(entry.lane) lane became " + entry.lines.joined(separator: " + ")
    }
    return ["mixed filter sets: " + words.joined(separator: ", ") + " over the colour base"]
  }

  /// Splits one line-clip lane's `master` into `kept`; returns what it added, each line with its
  /// plane.
  ///
  /// A line another lane already gave is not written again and is noted; a lane with nothing
  /// left to add is not read at all; a failed split costs only this lane's layers.
  private static func splitLane(
    _ set: FilterSet, master: String, out: URL, into kept: inout [String: String],
    taken held: Set<Filter>, notes: inout [String]
  ) -> [String] {
    guard let lines = set.lines else { return [] }
    // One table of the lines and their planes; a held line is the base's before any lane's.
    let pair = [(lines.red, "red pixels"), (lines.greenBlue, "max of green/blue")]
    let skipped = pair.compactMap { line, _ -> (Filter, String)? in
      if held.contains(line) { return (line, "the colour base already holds it") }
      if kept[line.rawValue] != nil { return (line, "another lane already gave it") }
      return nil
    }
    for (line, why) in skipped {
      notes.append("\(line.rawValue) of the \(set.rawValue) lane skipped: \(why)")
    }
    let taken = Set(skipped.map(\.0))
    guard taken.count < pair.count else { return [] }
    do {
      let names = try split(
        out.appendingPathComponent(master + ".fits"), out: out, lines: lines, skipping: taken)
      var added: [String] = []
      let written = [
        (lines.red, names.red, "red pixels"),
        (lines.greenBlue, names.greenBlue, "max of green/blue"),
      ]
      for (line, name, plane) in written where !taken.contains(line) {
        kept[line.rawValue] = name
        added.append("\(line.rawValue) (\(plane))")
      }
      if set.mixesLines {
        notes.append("multi-band clip: its Hα layer also carries [SII], its [OIII] layer Hβ")
      }
      return added
    } catch {
      notes.append(
        "\(set.rawValue) lane split skipped, finishing on the colour base alone: "
          + ChannelStacker.describe(error))
      return []
    }
  }
}

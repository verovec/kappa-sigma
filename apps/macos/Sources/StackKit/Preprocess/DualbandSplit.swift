package import FilterKit
package import Foundation
internal import ImageKit

/// Separates a registered dual-band colour master into pseudo-Hα and pseudo-[OIII]
/// (`splitDuoband`, `dualSetChannels`).
///
/// Hα at 656 nm lands on the red pixels; [OIII] at 500.7 nm on the shoulder between green and
/// blue, so the per-pixel maximum keeps whichever pixel caught the line (a mean would fold the
/// weaker one in and cost SNR). The REGISTERED master is split: the layers are composited pixel
/// for pixel over the broadband base.
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
  /// A lane leaves the map whatever happens: it is not a colour channel. With no broadband
  /// master left the first lane becomes the colour channel itself, unsplit (nothing to screen
  /// the lines onto); an unsplittable master, or one the alignment could not register
  /// (`registered`), costs only its emission layers. A line two lanes both carry is kept from
  /// the first lane (`FilterSet` order) and the other's is noted.
  package static func channels(_ channels: [String: String], out: URL, registered: Bool = true)
    -> (
      channels: [String: String], note: String?
    )
  {
    let lanes = FilterSetLanes.lineLanes(in: channels.keys)
    guard let first = lanes.first, let base = channels[first] else { return (channels, nil) }
    var kept = channels.filter { !lanes.contains($0.key) }
    guard !kept.isEmpty else {
      let dropped = lanes.dropFirst().map { "\($0) dropped" }
      return (
        [FilterSetLanes.baseFilter(of: first): base],
        "the broadband lane produced no master — finishing the \(first) stack as an ordinary "
          + "colour run (no broadband base to screen the emission lines onto)"
          + (dropped.isEmpty ? "" : "; " + dropped.joined(separator: ", "))
      )
    }
    // Unregistered layers would sit offset from the base, every star doubled.
    guard registered else {
      return (
        kept,
        "line-clip master not registered onto the broadband grid — emission layers skipped, "
          + "finishing on the broadband base alone"
      )
    }
    var notes: [String] = []
    for lane in lanes {
      guard let master = channels[lane], let set = FilterSetLanes.lineSet(of: lane) else {
        continue
      }
      splitLane(set, master: master, out: out, into: &kept, notes: &notes)
    }
    let added = kept.keys.filter { Filter.isNarrowband($0) }.sorted(by: Filter.less)
    let sets = lanes.compactMap { FilterSetLanes.lineSet(of: $0)?.rawValue }
    // The lead names what the lanes became; with nothing added, the skip reasons say it all.
    let plural = sets.count > 1 ? "s" : ""
    let lead =
      added.isEmpty
      ? []
      : [
        "mixed filter sets: the \(sets.joined(separator: " and ")) lane\(plural) became "
          + "\(added.joined(separator: " + ")) over the broadband base"
      ]
    return (kept, (lead + notes).joined(separator: "; "))
  }

  /// Splits one line-clip lane's `master` into `kept`: a line another lane already gave is not
  /// written again and is noted; a failed split costs only this lane's layers.
  private static func splitLane(
    _ set: FilterSet, master: String, out: URL, into kept: inout [String: String],
    notes: inout [String]
  ) {
    guard let lines = set.lines else { return }
    let taken = Set([lines.red, lines.greenBlue].filter { kept[$0.rawValue] != nil })
    do {
      let names = try split(
        out.appendingPathComponent(master + ".fits"), out: out, lines: lines, skipping: taken)
      for (line, name) in [(lines.red, names.red), (lines.greenBlue, names.greenBlue)] {
        if taken.contains(line) {
          notes.append(
            "\(line.rawValue) of the \(set.rawValue) lane skipped: another lane already gave it")
        } else {
          kept[line.rawValue] = name
        }
      }
      if set.mixesLines {
        notes.append("multi-band clip: its Hα layer also carries [SII], its [OIII] layer Hβ")
      }
    } catch {
      notes.append(
        "\(set.rawValue) lane split skipped, finishing on the broadband base alone: "
          + ChannelStacker.describe(error))
    }
  }
}

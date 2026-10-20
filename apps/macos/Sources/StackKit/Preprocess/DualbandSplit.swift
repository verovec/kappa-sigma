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
  package static let haBase = "syn_Ha"
  package static let oiiiBase = "syn_OIII"

  /// Why a master could not be split.
  package enum Failure: Error, CustomStringConvertible {
    case planes(Int)

    package var description: String {
      switch self {
      case .planes(let count):
        "colour master has \(count) plane(s), need 3 to separate Hα from [OIII]"
      }
    }
  }

  /// Writes `out/syn_Ha.fits` and `out/syn_OIII.fits` from `master` (left untouched), with its
  /// descriptive header; returns their basenames.
  package static func split(_ master: URL, out: URL) throws -> (ha: String, oiii: String) {
    let file = try FITSFile.read(at: master)
    let image = try file.image()
    guard image.planes.count >= 3 else { throw Failure.planes(image.planes.count) }
    let oiii = zip(image.planes[1], image.planes[2]).map { $0 > $1 ? $0 : $1 }
    for (name, plane) in [(haBase, image.planes[0]), (oiiiBase, oiii)] {
      try FITSFile.create(
        AstroImage(
          width: image.width, height: image.height, planes: [plane], metadata: image.metadata),
        keeping: file.header, at: out.appendingPathComponent(name + ".fits"))
    }
    return (haBase, oiiiBase)
  }

  /// The channel map with the dual-band lane turned into `Ha` + `OIII` (`dualSetChannels`), and
  /// the note the run shows; the map unchanged (no note) when the run did not split.
  ///
  /// The lane leaves the map whatever happens: it is not a colour channel. With no broadband
  /// master left it becomes the colour channel itself, unsplit (nothing to screen the lines
  /// onto); an unsplittable master, or one the alignment could not register (`registered`),
  /// costs only its emission layers.
  package static func channels(_ channels: [String: String], out: URL, registered: Bool = true)
    -> (
      channels: [String: String], note: String?
    )
  {
    guard let lane = FilterSetLanes.dualbandLane(in: channels.keys), let base = channels[lane]
    else { return (channels, nil) }
    var kept = channels.filter { $0.key != lane }
    guard !kept.isEmpty else {
      return (
        [FilterSetLanes.baseFilter(of: lane): base],
        "the broadband lane produced no master — finishing the dual-band stack as an ordinary "
          + "colour run (no broadband base to screen the emission lines onto)"
      )
    }
    // Unregistered layers would sit offset from the base, every star doubled.
    guard registered else {
      return (
        kept,
        "dual-band master not registered onto the broadband grid — emission layers skipped, "
          + "finishing on the broadband base alone"
      )
    }
    do {
      let (ha, oiii) = try split(out.appendingPathComponent(base + ".fits"), out: out)
      (kept["Ha"], kept["OIII"]) = (ha, oiii)
    } catch {
      return (
        kept,
        "dual-band lane split skipped, finishing on the broadband base alone: "
          + ChannelStacker.describe(error)
      )
    }
    return (
      kept,
      "mixed filter sets: the dual-band master was registered onto the broadband grid, then "
        + "separated into pseudo-Hα (red pixels) and pseudo-[OIII] (max of green/blue) — the "
        + "broadband stack is the colour base and the two emission lines screen over it"
    )
  }
}

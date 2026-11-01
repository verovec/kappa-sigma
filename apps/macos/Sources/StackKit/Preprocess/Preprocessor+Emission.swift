package import FilterKit
package import Foundation

extension Preprocessor {
  /// The assembly's emission step on the cropped combine inputs.
  ///
  /// `channels` maps a filter to its basename in `out`; `registered` says whether every line-clip
  /// lane to split landed on the base grid (the broadband master, or the first line lane when
  /// the run has none). Each line lane becomes its lines (`DualbandSplit`), then every emission
  /// layer gets its continuum scale (`ContinuumK`) — none with a line base. Each decision is a
  /// note; a scale that cannot be fitted costs only its `continuum_k`.
  package static func emission(
    _ channels: [String: String], out: URL, registered: Bool = true, notes: inout [String]
  ) -> (channels: [String: String], continuum: [String: Double]) {
    let (split, fits) = emissionFits(channels, out: out, registered: registered, notes: &notes)
    return (split, fits.mapValues(\.k))
  }

  /// `emission`, with each scale's fit: the reference plane the Studio subtracts (0051).
  package static func emissionFits(
    _ channels: [String: String], out: URL, registered: Bool = true, notes: inout [String]
  ) -> (channels: [String: String], continuum: [String: ContinuumK.Fit]) {
    let (split, note) = DualbandSplit.channels(channels, out: out, registered: registered)
    if let note { notes.append(note) }
    // A continuum is estimated against broadband light: when a line lane stands in for the
    // colour base, no scale is fitted at all (the split's note already says why).
    guard !DualbandSplit.lineBase(in: channels.keys) else { return (split, [:]) }
    let files = split.mapValues { out.appendingPathComponent($0 + ".fits") }
    var continuum: [String: ContinuumK.Fit] = [:]
    for line in ChannelAligner.ordered(split.keys) where ContinuumK.references(of: line) != nil {
      do {
        let fit = try ContinuumK.measure(line: line, layers: files)
        continuum[line] = fit
        notes.append(
          "\(line): continuum k = \(String(format: "%.4g", fit.k)) against \(fit.reference)")
      } catch {
        notes.append("\(line): continuum scale not fitted — \(ChannelStacker.describe(error))")
      }
    }
    return (split, continuum)
  }

  /// `soleClipLanes(_:clip:)` with the clip every light set of `inventory` carries.
  ///
  /// A clip verdict is a one-shot-colour rig's: a mono run's channels are never a clip's lane.
  static func soleClipLanes(_ channels: [String: String], inventory: Inventory)
    -> [String: String]
  {
    let clip = inventory.colorModel == .osc ? FilterSetLanes.soleVerdict(in: inventory) : nil
    return soleClipLanes(channels, clip: clip)
  }

  /// The channel map the emission step reads for a run of one line clip alone (`clip`, the
  /// verdict every light set carries — `FilterSetLanes.soleVerdict`): its one channel is that
  /// clip's lane, so `DualbandSplit` keeps it as the colour base and also writes its lines
  /// (card 0162); any other run unchanged.
  ///
  /// Such a run never splits its lanes (`FilterSetLanes.splits`): renamed here, after the crops,
  /// its Siril scripts and file names stay those of a plain run.
  package static func soleClipLanes(_ channels: [String: String], clip: FilterSet?)
    -> [String: String]
  {
    guard let clip, let suffix = FilterSetLanes.suffix(of: clip), channels.count == 1,
      let (filter, base) = channels.first, FilterSetLanes.lineSet(of: filter) == nil
    else { return channels }
    return [filter + suffix: base]
  }
}

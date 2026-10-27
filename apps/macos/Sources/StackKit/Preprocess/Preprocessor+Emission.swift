internal import FilterKit
package import Foundation

extension Preprocessor {
  /// The assembly's emission step on the cropped combine inputs.
  ///
  /// `channels` maps a filter to its basename in `out`; `registered` says whether the dual-band
  /// lane, if any, landed on the broadband grid. A split capture's dual-band lane becomes
  /// `Ha` + `OIII` (`DualbandSplit`), then every emission layer gets its continuum scale
  /// (`ContinuumK`). Each decision is a note; a scale that cannot be fitted costs only its
  /// `continuum_k`.
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
    // A continuum is estimated against broadband light: when a line lane stands in for the
    // colour base (no broadband master, no mono broadband filter), no scale is fitted at all.
    let lineBase =
      channels.keys.contains { FilterSetLanes.lineSet(of: $0) != nil }
      && !channels.keys.contains { lane in
        Filter.broadband.contains { $0.rawValue == lane }
          || (Filter.isColor(lane) && FilterSetLanes.lineSet(of: lane) == nil)
      }
    let (split, note) = DualbandSplit.channels(channels, out: out, registered: registered)
    if let note { notes.append(note) }
    let files = split.mapValues { out.appendingPathComponent($0 + ".fits") }
    var continuum: [String: ContinuumK.Fit] = [:]
    for line in ChannelAligner.ordered(split.keys) where ContinuumK.references(of: line) != nil {
      guard !lineBase else {
        notes.append("\(line): continuum scale not fitted — no broadband reference in this run")
        continue
      }
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
}

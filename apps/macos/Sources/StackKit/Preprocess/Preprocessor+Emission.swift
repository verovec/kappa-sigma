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
    let (split, note) = DualbandSplit.channels(channels, out: out, registered: registered)
    if let note { notes.append(note) }
    let files = split.mapValues { out.appendingPathComponent($0 + ".fits") }
    var continuum: [String: Double] = [:]
    for line in ChannelAligner.ordered(split.keys) where ContinuumK.references(of: line) != nil {
      do {
        let fit = try ContinuumK.measure(line: line, layers: files)
        continuum[line] = fit.k
        notes.append(
          "\(line): continuum k = \(String(format: "%.4g", fit.k)) against \(fit.reference)")
      } catch {
        notes.append("\(line): continuum scale not fitted — \(ChannelStacker.describe(error))")
      }
    }
    return (split, continuum)
  }
}

package import Foundation

extension Preprocessor {
  /// The assembly's emission step, on the cropped combine inputs (`channels`: filter → basename
  /// in `out`): a split capture's dual-band lane becomes `Ha` + `OIII` (`DualbandSplit`), then
  /// every emission layer gets its continuum scale (`ContinuumK`). Each decision is a note; a
  /// scale that cannot be fitted costs only its `continuum_k`.
  package static func emission(
    _ channels: [String: String], out: URL, notes: inout [String]
  ) -> (channels: [String: String], continuum: [String: Double]) {
    let (split, note) = DualbandSplit.channels(channels, out: out)
    if let note { notes.append(note) }
    let files = split.mapValues { out.appendingPathComponent($0 + ".fits") }
    var continuum: [String: Double] = [:]
    for line in ChannelAligner.ordered(split.keys) where ContinuumK.references(of: line) != nil {
      let measured: (fit: ContinuumK.Fit?, reason: String?)
      do {
        measured = try ContinuumK.measure(line: line, layers: files)
      } catch {
        measured = (nil, ChannelStacker.describe(error))
      }
      if let fit = measured.fit {
        continuum[line] = fit.k
        notes.append("\(line): continuum k = \(String(format: "%.4g", fit.k)) against \(fit.reference)")
      } else if let reason = measured.reason {
        notes.append("\(line): continuum scale not fitted — \(reason)")
      }
    }
    return (split, continuum)
  }
}

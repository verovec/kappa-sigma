package import Foundation

/// The linear colour composite (`postprocess.buildCombine` + the neutralization fallback):
/// `rgbcomp` of the combine inputs into `combined`, its sky flattened, then the green cast removed.
///
/// It is the run's first colour view; the bundle's layers stay the per-channel inputs.
package struct ChannelCombiner: Sendable {
  package var runner: SirilRunner
  package var settings: PreprocessSettings

  /// A combiner running through `runner`.
  package init(runner: SirilRunner, settings: PreprocessSettings = PreprocessSettings()) {
    self.runner = runner
    self.settings = settings
  }

  /// What the channels can make: L+R+G+B, R+G+B, or one colour master; nil otherwise (a mono or
  /// narrowband-only run has no colour composite to build here).
  package static func inputs(_ channels: [String: String]) -> SirilScripts.CombineInputs? {
    if let r = channels["R"], let g = channels["G"], let b = channels["B"] {
      return channels["L"].map { .lrgb(lum: $0, r: r, g: g, b: b) } ?? .rgb(r: r, g: g, b: b)
    }
    if channels.count == 1, let (filter, base) = channels.first, Filter.isColor(filter) {
      return .colour(base)
    }
    return nil
  }

  /// Builds `out/combined.fits`; returns its path, or nil when the channels make no composite.
  package func combine(_ channels: [String: String], out: URL) async throws -> URL? {
    guard let inputs = Self.inputs(channels) else { return nil }
    let degree = settings.backgroundDegree
    _ = try await runner.run(SirilScripts.combine(inputs, backgroundDegree: degree), out) { _ in }
    _ = try await runner.run(
      SirilScripts.neutralize(
        load: "combined", out: "combined", backgroundDegree: degree, scnr: settings.scnr),
      out
    ) { _ in }
    return out.appendingPathComponent("combined.fits")
  }
}

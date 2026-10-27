internal import FilterKit
package import Foundation

/// The linear colour composite (`postprocess.buildCombine` + the neutralization fallback):
/// `rgbcomp` of the combine inputs into `combined`, its sky flattened, then the green cast removed;
/// a run with no colour to build copies its one mono master instead (card 0137).
///
/// It is the run's first view; the bundle's layers stay the per-channel inputs.
package struct ChannelCombiner: Sendable {
  package var runner: SirilRunner
  package var settings: PreprocessSettings

  /// A combiner running through `runner`.
  package init(runner: SirilRunner, settings: PreprocessSettings = PreprocessSettings()) {
    self.runner = runner
    self.settings = settings
  }

  /// What the channels make: L+R+G+B, R+G+B, one colour master (emission layers beside it, a
  /// split capture's `syn_*`, set aside), else — no colour layer at all — the one mono master
  /// `Filter.monoSource` names (card 0137); nil for no channel, or a colour master beside
  /// anything else than lines (a mix the run refuses before it starts).
  package static func inputs(_ channels: [String: String]) -> SirilScripts.CombineInputs? {
    if let r = channels["R"], let g = channels["G"], let b = channels["B"] {
      return channels["L"].map { .lrgb(lum: $0, r: r, g: g, b: b) } ?? .rgb(r: r, g: g, b: b)
    }
    let colour = channels.filter { Filter.isColor($0.key) }
    if !colour.isEmpty {
      let others = channels.keys.filter { !Filter.isColor($0) }
      guard colour.count == 1, let base = colour.first?.value,
        others.allSatisfy({ LinearBundle.Role(filter: $0) == .line })
      else { return nil }
      return .colour(base)
    }
    guard let filter = Filter.monoSource(in: channels.keys), let master = channels[filter] else {
      return nil
    }
    return .mono(filter: filter, master: master)
  }

  /// What the journal says of a mono combined image, which master it is; nil for a composite.
  package static func note(_ inputs: SirilScripts.CombineInputs?) -> String? {
    guard case .mono(let filter, _) = inputs else { return nil }
    return "combined = \(filter) alone (mono: no colour composite to build)"
  }

  /// Builds `out/combined.fits` from `inputs(channels)`; returns its path, or nil when they make
  /// nothing.
  package func combine(_ channels: [String: String], out: URL) async throws -> URL? {
    guard let inputs = Self.inputs(channels) else { return nil }
    return try await combine(inputs, out: out)
  }

  /// Builds `out/combined.fits` from `inputs`; returns its path.
  package func combine(_ inputs: SirilScripts.CombineInputs, out: URL) async throws -> URL {
    let degree = settings.backgroundDegree
    _ = try await runner.run(SirilScripts.combine(inputs, backgroundDegree: degree), out) { _ in }
    // The green removal is a colour-composite step; the sky fit above applies to mono too.
    if case .mono = inputs { return out.appendingPathComponent("combined.fits") }
    _ = try await runner.run(
      SirilScripts.neutralize(
        load: "combined", out: "combined", backgroundDegree: degree, scnr: settings.scnr),
      out
    ) { _ in }
    return out.appendingPathComponent("combined.fits")
  }
}

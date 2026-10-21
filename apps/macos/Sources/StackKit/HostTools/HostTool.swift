/// A tool the app invokes but never bundles (CLAUDE.md « Host tools, invoked never bundled »).
package enum HostTool: String, CaseIterable, Sendable {
  /// Siril: calibration, registration, stacking.
  case siril
  /// GraXpert: background extraction and denoise.
  case graxpert
  /// StarNet2: star removal (user install, no public licence).
  case starnet

  /// The product name, never translated.
  package var productName: String {
    switch self {
    case .siril: "Siril"
    case .graxpert: "GraXpert"
    case .starnet: "StarNet2"
    }
  }
}

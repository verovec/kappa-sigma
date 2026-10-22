/// The masters (and cosmetic options) a `calibrate` command applies (`CalibMasters`).
package struct CalibrationMasters: Equatable, Sendable {
  /// Bias master path (with `.fits`).
  package var bias: String?
  /// Dark master path.
  package var dark: String?
  /// Flat master path.
  package var flat: String?
  /// Bad-pixel map for `-cc=bpm` (replaces dark-based cosmetic correction).
  package var badPixelMap: String?
  /// One-shot-colour frames: `-cfa`, `-equalize_cfa`, `-debayer`.
  package var cfa: Bool
  /// Scale a different-exposure dark (`-opt`, needs dark and bias).
  package var darkOptimize: Bool

  /// Masters; `nil` means not applied.
  package init(
    bias: String? = nil, dark: String? = nil, flat: String? = nil, badPixelMap: String? = nil,
    cfa: Bool = false, darkOptimize: Bool = false
  ) {
    // An empty path is no master, as the legacy `!= ""` tests had it.
    func present(_ path: String?) -> String? { path?.isEmpty == false ? path : nil }
    self.bias = present(bias)
    self.dark = present(dark)
    self.flat = present(flat)
    self.badPixelMap = present(badPixelMap)
    self.cfa = cfa
    self.darkOptimize = darkOptimize
  }

  /// The arguments between `calibrate <seq>` and `-prefix=pp_`, in the legacy order
  /// (`calibrateArgs`); empty means no `calibrate` line at all.
  package var arguments: [String] {
    var args: [String] = []
    if let dark { args.append("-dark=\(dark)") }
    if let flat { args.append("-flat=\(flat)") }
    if let bias, dark == nil || darkOptimize { args.append("-bias=\(bias)") }
    if let badPixelMap {
      // Two Siril words: the map path is quoted on its own when it has a space (card 0112).
      args += ["-cc=bpm", badPixelMap]
    } else if dark != nil {
      args.append("-cc=dark")
    }
    if darkOptimize, dark != nil, bias != nil { args.append("-opt") }
    if cfa {
      if !args.isEmpty {
        args.append("-cfa")
        if flat != nil { args.append("-equalize_cfa") }
      }
      args.append("-debayer")
    }
    return args
  }
}

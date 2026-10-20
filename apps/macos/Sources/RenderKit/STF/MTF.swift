/// The midtones transfer function (PixInsight / Siril / astrocomp `mtf`): maps [0, 1] onto itself,
/// sending `m` to 0.5 while keeping 0 and 1 fixed.
package enum MTF {
  /// MTF(m, x) = ((m − 1)·x) / ((2m − 1)·x − m), with the exact fixed points 0, m, 1.
  package static func apply(_ midtone: Double, _ x: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    if x == midtone { return 0.5 }
    return ((midtone - 1) * x) / ((2 * midtone - 1) * x - midtone)
  }
}

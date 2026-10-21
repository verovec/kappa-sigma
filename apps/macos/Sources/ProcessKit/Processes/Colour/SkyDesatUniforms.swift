/// What the sky-desat passes read, from the panel values, the bundle statistics and the scale.
struct SkyDesatUniforms {
  /// The sky level: the mean of the bundle's channel medians.
  let sky: Double
  /// The chroma noise σ: mean MADN · √(2/3), the σ of c − (R+G+B)/3 for independent channels.
  let sigmaC: Double
  /// σ of the coarse field, in working pixels (`scalePx / √3`, the legacy box-radius match).
  let coarseSigma: Double
  /// σ of the star-detail luminance, in working pixels.
  let starSigma: Double
  /// The star-weight kernel's `p[]`.
  let star: [Float]
  /// The final kernel's `p[]` (see SkyDesat.metal).
  let final: [Float]

  /// Uniforms for `params` with the bundle `stats`, at `scale` full-resolution pixels per
  /// working pixel; refuses a missing sky level and crossed bands, with the reason.
  init(params: ParamSet, stats: LayerStats, scale: Double) throws {
    guard stats.channels.count >= 3 else {
      throw ProcessError.invalidParameter(
        "the sky desaturation needs the bundle statistics of R, G and B")
    }
    let used = stats.channels.prefix(3)
    sky = used.map(\.median).reduce(0, +) / 3
    guard sky > 0 else {
      throw ProcessError.invalidParameter(
        "the sky desaturation needs a positive sky level (bundle median)")
    }
    sigmaC = used.map(\.madn).reduce(0, +) / 3 * (2.0 / 3).squareRoot()
    let bands = try ["star", "nebula", "floor"].map { id in
      let (low, high) = (params.number(id + "Low"), params.number(id + "High"))
      guard low < high else {
        throw ProcessError.invalidParameter("the \(id) band needs start < end")
      }
      return (low, high)
    }
    let working = { (px: Double) in px / max(scale, 1e-9) }
    coarseSigma = working(params.number("scalePx")) / 3.0.squareRoot()
    starSigma = working(params.number("starDetailPx"))
    star = [bands[0].0, bands[0].1, sky].map { Float($0) }
    final = [
      params.number("strength"), params.flag("keepCool") ? 1 : 0, sigmaC, sky, bands[1].0,
      bands[1].1, bands[2].0, bands[2].1, params.number("coreLevel"),
      working(params.number("coreGuardPx")).rounded(),
    ].map { Float($0) }
  }
}

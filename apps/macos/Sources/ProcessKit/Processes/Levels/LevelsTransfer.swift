internal import RenderKit

/// The levels' triples resolved once (card 0089): the CPU transfer the clipping readouts run
/// over the head's sample, in double, the kernel's order — each channel's own triple when
/// unlinked, then RGB/K, an identity skipped.
package struct LevelsTransfer: Sendable {
  /// Each channel's own triple, `nil` when it does not apply (linked, mono, identity).
  private let own: [STFParameters?]
  /// The RGB/K triple, `nil` at the identity.
  private let rgb: STFParameters?

  /// The transfer of `params` on `channels` planes.
  package init(_ params: ParamSet, channels: Int) {
    let unlinked = !params.flag("linked") && channels == 3
    own = LevelsProcess.triples.dropFirst().map { triple in
      let stf = LevelsProcess.stf(triple, of: params)
      return unlinked && stf != .identity ? stf : nil
    }
    let rgb = LevelsProcess.stf("rgb", of: params)
    self.rgb = rgb == .identity ? nil : rgb
  }

  /// `x` of `channel` through the triples.
  package func apply(_ x: Double, channel: Int) -> Double {
    var value = x
    if let own = own[min(channel, 2)] { value = own.display(value) }
    if let rgb { value = rgb.display(value) }
    return value
  }
}

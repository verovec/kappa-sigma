/// One channel's display stretch as the controls edit it (card 0085): shadows in σ of the noise,
/// the target background, the highlights, and the raw c0 / m / c1 beside them.
///
/// Every control is a `ParameterValue` whose default is the autostretch's number for it, so an
/// untouched row says « Default » and resets to the autostretch exactly. Each control moves one
/// parameter only (R2: nothing recomputed behind the user); the others read the result back.
package struct STFChannelControls: Equatable, Sendable {
  /// The six rows.
  package enum Control: CaseIterable, Sendable {
    /// c0 as σ of the MADN around the median.
    case shadowsSigma
    /// Where the median lands through m (Siril's meaning).
    case targetBackground
    /// c1.
    case highlights
    /// c0, the number applied.
    case rawShadows
    /// m, the number applied.
    case rawMidtone
    /// c1, the number applied.
    case rawHighlights
  }

  /// How close a derived row (σ, target) reads back to its default before it shows it exactly.
  ///
  /// The round trip through the MTF holds to about 1e-12 relative, not bit for bit; the number
  /// applied (c0, m) is shown bit for bit in the raw rows.
  package static let derivedTolerance = 1e-12

  /// The stretch applied.
  package var parameters: STFParameters
  /// The autostretch: every row's default.
  package let auto: STFParameters
  /// The channel's median and MADN.
  package let mapping: STFMapping

  /// Controls over `parameters`, defaulting to `auto`, through `mapping`.
  package init(parameters: STFParameters, auto: STFParameters, mapping: STFMapping) {
    self.parameters = parameters
    self.auto = auto
    self.mapping = mapping
  }

  /// What the slider and the field of `control` accept.
  package static func range(of control: Control) -> ClosedRange<Double> {
    switch control {
    case .shadowsSigma: -5...5
    case .targetBackground: 0.01...0.6
    case .highlights: 0.5...1
    case .rawShadows, .rawMidtone, .rawHighlights: 0...1
    }
  }

  /// One arrow press; ⇧-arrows and ⌥-drag move a tenth of it.
  package static func step(of control: Control) -> ParameterStep {
    switch control {
    case .shadowsSigma: ParameterStep(0.1)
    case .targetBackground, .highlights, .rawHighlights: ParameterStep(0.01)
    case .rawShadows: ParameterStep(0.0001)
    case .rawMidtone: ParameterStep(0.001)
    }
  }

  /// Decimals shown: enough for the fine step.
  package static func digits(of control: Control) -> Int {
    switch control {
    case .shadowsSigma: 2
    case .targetBackground, .highlights, .rawHighlights: 3
    case .rawShadows: 5
    case .rawMidtone: 4
    }
  }

  /// The target background has a meaning only while the median shows above black: with the black
  /// point at or above the median no midtone puts it anywhere, and the row is disabled.
  package var targetAvailable: Bool { mapping.median > parameters.shadows }

  /// The row of `control`: read from `parameters`, written back to the one parameter it edits.
  ///
  /// The range widens to the number shown when it lies outside the slider's, so the number on
  /// screen is always the number applied (a raw c1 of 0.3 shows 0.3 on the Highlights row).
  package subscript(control: Control) -> ParameterValue {
    get {
      let defaultValue = value(of: control, in: auto)
      var shown = value(of: control, in: parameters)
      if abs(shown - defaultValue) <= Self.derivedTolerance * max(1, abs(defaultValue)) {
        shown = defaultValue
      }
      let bounds = Self.range(of: control)
      let range =
        min(bounds.lowerBound, shown, defaultValue)...max(bounds.upperBound, shown, defaultValue)
      return ParameterValue(default: defaultValue, range: range, value: shown)
    }
    set {
      if newValue.isDefault {
        restore(control)
      } else {
        apply(newValue.value, to: control)
      }
    }
  }

  private func value(of control: Control, in stf: STFParameters) -> Double {
    switch control {
    case .shadowsSigma: mapping.sigma(ofShadows: stf.shadows)
    case .targetBackground: mapping.targetBackground(ofMidtone: stf.midtone, shadows: stf.shadows)
    case .highlights, .rawHighlights: stf.highlights
    case .rawShadows: stf.shadows
    case .rawMidtone: stf.midtone
    }
  }

  private mutating func apply(_ value: Double, to control: Control) {
    switch control {
    case .shadowsSigma: parameters.shadows = mapping.shadows(sigma: value)
    case .targetBackground:
      guard targetAvailable else { return }
      parameters.midtone = mapping.midtone(targetBackground: value, shadows: parameters.shadows)
    case .highlights, .rawHighlights: parameters.highlights = value
    case .rawShadows: parameters.shadows = value
    case .rawMidtone: parameters.midtone = value
    }
  }

  /// A reset lands on the autostretch's number bit for bit (a σ → c0 → σ round trip would not);
  /// the target keeps its own meaning when the black point moved and is recomputed then (read
  /// back within `derivedTolerance`).
  private mutating func restore(_ control: Control) {
    switch control {
    case .shadowsSigma, .rawShadows: parameters.shadows = auto.shadows
    case .highlights, .rawHighlights: parameters.highlights = auto.highlights
    case .rawMidtone: parameters.midtone = auto.midtone
    case .targetBackground:
      if parameters.shadows == auto.shadows {
        parameters.midtone = auto.midtone
      } else {
        apply(value(of: control, in: auto), to: control)
      }
    }
  }
}

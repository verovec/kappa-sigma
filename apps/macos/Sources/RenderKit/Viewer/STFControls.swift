internal import Foundation
package import SwiftUI

/// The display stretch of one channel, readable and precise (card 0085).
///
/// Shadows in σ of the noise, the target background and the highlights as rows with a slider, a
/// typed field, reset and a « why »; the raw c0 / m / c1 in a disclosure. Arrows move one step,
/// ⇧-arrows and ⌥-drag a tenth (each row's help says which). Display only (R2): the data never
/// changes.
package struct STFControls: View {
  private let name: String
  @Binding private var parameters: STFParameters
  private let auto: STFParameters
  private let mapping: STFMapping
  private let key: String
  @State private var rawShown = false
  @Environment(\.locale) private var locale

  /// The controls of channel `name` over `parameters`, defaulting to `auto`, through the
  /// channel's `mapping`; `key` prefixes the rows' ids (`fr.astrostack.parameter.<key>.<row>…`).
  package init(
    name: String, parameters: Binding<STFParameters>, auto: STFParameters, mapping: STFMapping,
    key: String
  ) {
    self.name = name
    _parameters = parameters
    self.auto = auto
    self.mapping = mapping
    self.key = key
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      Text(verbatim: name).font(.headline)
      row(.shadowsSigma)
      row(.targetBackground)
      row(.highlights)
      DisclosureGroup(isExpanded: $rawShown) {
        row(.rawShadows)
        row(.rawMidtone)
        row(.rawHighlights)
      } label: {
        Text(.renderKit("Raw numbers (c0, m, c1)"))
      }
    }
  }

  private var controls: STFChannelControls {
    STFChannelControls(parameters: parameters, auto: auto, mapping: mapping)
  }

  private func row(_ control: STFChannelControls.Control) -> some View {
    ParameterRow(
      Self.label(control),
      parameter: Binding(
        get: { controls[control] },
        set: { value in
          var edited = controls
          edited[control] = value
          parameters = edited.parameters
        }),
      why: Self.why(control), key: key + "." + Self.id(control),
      step: STFChannelControls.step(of: control),
      format: { Self.format($0, control: control, locale: locale) },
      parse: { Self.parse($0, locale: locale) }
    )
    // With the black point at or above the median no midtone places it: the row has no meaning.
    .disabled(control == .targetBackground && !controls.targetAvailable)
  }

  /// `value` with the decimals of `control`, in `locale`.
  nonisolated package static func format(
    _ value: Double, control: STFChannelControls.Control, locale: Locale
  ) -> String {
    let digits = STFChannelControls.digits(of: control)
    return LocaleNumber.decimal(
      value, locale: locale, maxFractionDigits: digits, minFractionDigits: digits)
  }

  /// A typed number in the notation of `locale` (`LocaleNumber.parse`).
  nonisolated package static func parse(_ text: String, locale: Locale) -> Double? {
    LocaleNumber.parse(text, locale: locale)
  }

  /// The row's stable id.
  nonisolated static func id(_ control: STFChannelControls.Control) -> String {
    switch control {
    case .shadowsSigma: "shadowsSigma"
    case .targetBackground: "targetBackground"
    case .highlights: "highlights"
    case .rawShadows: "c0"
    case .rawMidtone: "m"
    case .rawHighlights: "c1"
    }
  }

  nonisolated static func label(_ control: STFChannelControls.Control) -> LocalizedStringResource {
    switch control {
    case .shadowsSigma: .renderKit("Shadows (σ)")
    case .targetBackground: .renderKit("Target background")
    case .highlights, .rawHighlights: .renderKit("Highlights")
    case .rawShadows: .renderKit("Shadows")
    case .rawMidtone: .renderKit("Midtone")
    }
  }

  /// What the row means and its documented steps.
  nonisolated static func why(_ control: STFChannelControls.Control) -> LocalizedStringResource {
    switch control {
    case .shadowsSigma:
      .renderKit(
        "Black point in σ of the noise (MADN; auto −2.8 σ). Arrows ±0.1 σ, ⇧ or ⌥ ±0.01 σ."
      )
    case .targetBackground:
      .renderKit(
        "Where the median lands, Siril's meaning (auto 0.25). Arrows ±0.01, ⇧ or ⌥ ±0.001."
      )
    case .highlights:
      .renderKit(
        "White point c1: values above it show white. Arrows ±0.01, ⇧ or ⌥ ±0.001.")
    case .rawShadows:
      .renderKit("c0, the black point applied. Arrows ±0.0001, ⇧ or ⌥ ±0.00001.")
    case .rawMidtone:
      .renderKit("m, the midtone balance applied. Arrows ±0.001, ⇧ or ⌥ ±0.0001.")
    case .rawHighlights:
      .renderKit("c1, the white point applied. Arrows ±0.01, ⇧ or ⌥ ±0.001.")
    }
  }
}

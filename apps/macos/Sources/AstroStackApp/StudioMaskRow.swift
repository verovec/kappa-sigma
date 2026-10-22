package import ProcessKit
internal import RenderKit
package import SwiftUI

/// Where the chosen process acts (card 0087): everywhere, a luminosity range or the stars,
/// inverted or not, feathered — every value shown and adjustable (R2), applied by the kit after
/// the process, to the preview and Apply alike.
package struct StudioMaskRow: View {
  let model: StudioWorkspaceModel
  @Environment(\.locale) private var locale

  /// A mask value the row edits (its raw value names its parameter key).
  package enum Field: String, CaseIterable, Sendable {
    case low, high, softness, threshold, radius, feather
  }

  /// The mask sources the row offers, with their starting values.
  enum Source: String, CaseIterable {
    case none, luminosity, stars

    var mask: MaskSource? {
      switch self {
      case .none: nil
      case .luminosity: .luminosityRange(low: 0.2, high: 1, softness: 0.1)
      case .stars: .stars(threshold: 0.02, radiusPx: 8)
      }
    }

    var title: LocalizedStringResource {
      switch self {
      case .none: .app("No mask")
      case .luminosity: .app("Luminosity")
      case .stars: .app("Stars")
      }
    }

    init(_ mask: Mask?) {
      switch mask?.source {
      case nil: self = .none
      case .luminosityRange: self = .luminosity
      case .stars: self = .stars
      }
    }
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      HStack {
        Picker(selection: source) {
          ForEach(Source.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
          Text(.app("Mask"))
        }
        .accessible(.studioMaskSource, label: .app("Mask"))
        Toggle(isOn: inverted) { Text(.app("Invert")) }
          .disabled(model.mask == nil)
          .accessible(.studioMaskInvert, label: .app("Invert"))
      }
      if let mask = model.mask {
        values(of: mask)
      }
    }
  }

  @ViewBuilder private func values(of mask: Mask) -> some View {
    switch mask.source {
    case .luminosityRange(let low, let high, let softness):
      row(.app("Range start"), .low, low, 0...1)
      row(.app("Range end"), .high, high, 0...1)
      row(.app("Softness"), .softness, softness, 0...0.5)
    case .stars(let threshold, let radiusPx):
      row(.app("Star threshold"), .threshold, threshold, 0.001...0.5)
      row(.app("Star radius (px)"), .radius, radiusPx, 1...64)
    }
    ParameterRow(
      .app("Feather (px)"),
      parameter: Binding(
        get: { ParameterValue(default: 0, range: 0...64, value: mask.featherPx) },
        set: { model.mask?.featherPx = $0.value }),
      key: AccessibilityID.studioMaskKey(Field.feather.rawValue), format: format, parse: parse)
  }

  private func row(
    _ label: LocalizedStringResource, _ key: Field, _ value: Double,
    _ range: ClosedRange<Double>
  ) -> some View {
    let start = Source(model.mask).mask.flatMap { Self.value(key, of: $0) } ?? value
    return ParameterRow(
      label,
      parameter: Binding(
        get: { ParameterValue(default: start, range: range, value: value) },
        set: { moved in
          if let source = model.mask?.source {
            model.mask?.source = Self.moved(source, key, to: moved.value)
          }
        }),
      key: AccessibilityID.studioMaskKey(key.rawValue), format: format, parse: parse)
  }

  /// `source` with its `key` value set to `value`: a range end never crosses its start; a key
  /// the source has not leaves it as it is.
  nonisolated package static func moved(_ source: MaskSource, _ key: Field, to value: Double)
    -> MaskSource
  {
    switch (source, key) {
    case (.luminosityRange(_, let high, let softness), .low):
      .luminosityRange(low: value, high: max(value, high), softness: softness)
    case (.luminosityRange(let low, _, let softness), .high):
      .luminosityRange(low: min(low, value), high: value, softness: softness)
    case (.luminosityRange(let low, let high, _), .softness):
      .luminosityRange(low: low, high: high, softness: value)
    case (.stars(_, let radiusPx), .threshold): .stars(threshold: value, radiusPx: radiusPx)
    case (.stars(let threshold, _), .radius): .stars(threshold: threshold, radiusPx: value)
    default: source
    }
  }

  /// The starting value of `key` in `source` (the row's default badge and reset).
  nonisolated package static func value(_ key: Field, of source: MaskSource) -> Double? {
    switch (source, key) {
    case (.luminosityRange(let low, _, _), .low): low
    case (.luminosityRange(_, let high, _), .high): high
    case (.luminosityRange(_, _, let softness), .softness): softness
    case (.stars(let threshold, _), .threshold): threshold
    case (.stars(_, let radiusPx), .radius): radiusPx
    default: nil
    }
  }

  private func format(_ value: Double) -> String { AstroFormat(locale: locale).parameter(value) }
  private func parse(_ text: String) -> Double? {
    AstroFormat(locale: locale).parameter(parsing: text)
  }

  private var source: Binding<Source> {
    Binding(
      get: { Source(model.mask) },
      set: { choice in
        model.mask = choice.mask.map { Mask(source: $0, inverted: model.mask?.inverted ?? false) }
      })
  }

  private var inverted: Binding<Bool> {
    Binding(
      get: { model.mask?.inverted ?? false },
      set: { model.mask?.inverted = $0 })
  }
}

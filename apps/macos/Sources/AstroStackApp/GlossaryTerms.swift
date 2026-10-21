package import StackKit

// The glossary's term ids, derived from the catalogs that own each vocabulary (card 0074): a
// case added there without its term fails `GlossaryTests`.

extension FrameType {
  /// The term id, `frame.light` or `frame.darkflat` for instance.
  package nonisolated var termID: String { "frame." + rawValue.lowercased() }
}

extension Filter {
  /// The term id, `filter.ha` for instance.
  ///
  /// The short name (`Ha`) is the same in every language; the term is the long one.
  package nonisolated var termID: String { "filter." + rawValue.lowercased() }
}

extension FilterSet {
  /// The term id, `filterSet.dualband` for instance.
  package nonisolated var termID: String { "filterSet." + rawValue }
}

extension ColorChoice {
  /// The term id, `colorModel.osc` for instance.
  package nonisolated var termID: String { "colorModel." + rawValue }
}

extension ColorModel {
  /// The term id: the scan's verdict is worded like the choice it answers.
  package nonisolated var termID: String { "colorModel." + rawValue }
}

extension CalibrationRole {
  /// The frames a master of this role is stacked from: the role is worded as its frames.
  package nonisolated var frameType: FrameType {
    switch self {
    case .dark: .dark
    case .flat: .flat
    case .bias: .bias
    }
  }
}

extension LinearBundle.Role {
  /// The term id of a bundle layer: the filter it carries, or the colour / emission-line layer.
  package nonisolated var termID: String {
    switch self {
    case .rgb: "layer.rgb"
    case .line: "layer.line"
    case .lum: Filter.luminance.termID
    case .red: Filter.red.termID
    case .green: Filter.green.termID
    case .blue: Filter.blue.termID
    }
  }
}

extension JourneyStage {
  /// The term id, `stage.data` for instance.
  package nonisolated var termID: String { "stage." + rawValue }
}

extension Knob {
  /// The term id of knob `id` in the knobs glossary, `knob.fwhm_sigma` for instance.
  package nonisolated static func termID(_ id: String) -> String { "knob." + id }

  /// The term id of one choice of knob `id`, `knob.stack_reject.winsorized` for instance.
  package nonisolated static func termID(_ id: String, option: String) -> String {
    termID(id) + "." + option
  }
}

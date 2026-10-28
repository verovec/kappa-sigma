/// One parameter of a process: what the panel shows, the bounds a value is clamped into, its
/// unit and its level.
package struct ParamSpec: Equatable, Sendable {
  /// What a value of this parameter is.
  package enum Kind: Equatable, Sendable {
    /// A number clamped into `bounds`.
    case number(default: Double, bounds: ClosedRange<Double>)
    /// On or off.
    case flag(default: Bool)
    /// One of `options`.
    case choice(default: String, options: [String])
    /// Between 2 and `maxCount` control points of a curve.
    case points(default: [CurvePoint], maxCount: Int)
    /// Free text, at most `maxLength` characters.
    case text(default: String, maxLength: Int)
    /// A bundle layer's plane (card 0138): a token well-formed by `LayerPlane.isWellFormed`,
    /// named by the bundle (the panel lists `LayerPlane.options`), a `.choice` on the wire.
    case layer(default: String, allowsNone: Bool, allowsProduct: Bool)
  }

  /// Stable identifier, used by recipes and history (never renamed once shipped).
  package let id: String
  /// Panel label.
  package let title: String
  /// How the value is read; `.px` values are divided by the preview scale inside `render`.
  package let unit: ParamUnit
  /// Where the panel shows it.
  package let level: ParamLevel
  /// Kind, default and bounds.
  package let kind: Kind
  /// For a choice: whether no option (`""`, shown « Choose… ») is a value — the default of a
  /// choice the user must make, never one made for them (card 0140).
  package let allowsUnset: Bool
  /// The bundle layer this parameter is about (a line's rows, card 0135): the panel hides the
  /// row while that layer is absent and the values do not ask for it; `nil` for every other row.
  package private(set) var needsLayer: String?

  /// A number parameter.
  package init(
    id: String, title: String, unit: ParamUnit, level: ParamLevel, number: Double,
    in bounds: ClosedRange<Double>
  ) {
    self.init(
      id: id, title: title, unit: unit, level: level, kind: .number(default: number, bounds: bounds)
    )
  }

  /// An on/off parameter.
  package init(id: String, title: String, level: ParamLevel, flag: Bool) {
    self.init(id: id, title: title, unit: .none, level: level, kind: .flag(default: flag))
  }

  /// A parameter naming a bundle layer's plane, `none` or a product `A*B` when allowed.
  package init(
    id: String, title: String, level: ParamLevel, layer: String, allowsNone: Bool,
    allowsProduct: Bool
  ) {
    self.init(
      id: id, title: title, unit: .none, level: level,
      kind: .layer(default: layer, allowsNone: allowsNone, allowsProduct: allowsProduct))
  }

  /// A parameter choosing one of `options`, or none yet when `allowsUnset` (`choice: ""`).
  package init(
    id: String, title: String, level: ParamLevel, choice: String, of options: [String],
    allowsUnset: Bool = false
  ) {
    self.init(
      id: id, title: title, unit: .none, level: level,
      kind: .choice(default: choice, options: options), allowsUnset: allowsUnset)
  }

  /// A curve of 2 to `maxCount` control points.
  package init(
    id: String, title: String, level: ParamLevel, points: [CurvePoint], maxCount: Int
  ) {
    self.init(
      id: id, title: title, unit: .none, level: level,
      kind: .points(default: points, maxCount: maxCount))
  }

  /// A free-text parameter (empty by default: not given until the user types or accepts one).
  package init(id: String, title: String, level: ParamLevel, text: String, maxLength: Int) {
    self.init(
      id: id, title: title, unit: .none, level: level,
      kind: .text(default: text, maxLength: maxLength))
  }

  /// A parameter of any kind; `about(layer:)` makes it a layer's row.
  package init(
    id: String, title: String, unit: ParamUnit, level: ParamLevel, kind: Kind,
    allowsUnset: Bool = false
  ) {
    self.id = id
    self.title = title
    self.unit = unit
    self.level = level
    self.kind = kind
    self.allowsUnset = allowsUnset
  }

  /// True for a choice.
  package var isChoice: Bool {
    if case .choice = kind { true } else { false }
  }

  /// This spec, about the bundle layer `layer` (a copy: every other field as it was).
  package func about(layer: String) -> Self {
    var copy = self
    copy.needsLayer = layer
    return copy
  }

  /// The default value.
  package var defaultValue: ParamValue {
    switch kind {
    case .number(let value, _): .number(value)
    case .flag(let value): .flag(value)
    case .choice(let value, _): .choice(value)
    case .points(let value, _): .points(value)
    case .text(let value, _): .text(value)
    case .layer(let value, _, _): .choice(value)
    }
  }

  /// `value` made valid for this parameter: numbers clamped into the bounds; NaN/±Inf, a value
  /// of the wrong kind or an unknown option is refused.
  package func validated(_ value: ParamValue) throws -> ParamValue {
    switch (kind, value) {
    case (.number(_, let bounds), .number(let number)):
      guard number.isFinite else { throw ParamError.notFinite(id: id) }
      return .number(min(max(number, bounds.lowerBound), bounds.upperBound))
    case (.flag, .flag):
      return value
    case (.choice(_, let options), .choice(let option)):
      guard options.contains(option) || (allowsUnset && option.isEmpty) else {
        throw ParamError.unknownOption(id: id, option: option)
      }
      return value
    case (.layer(_, let allowsNone, let allowsProduct), .choice(let token)):
      guard LayerPlane.isWellFormed(token, allowsNone: allowsNone, allowsProduct: allowsProduct)
      else { throw ParamError.unknownOption(id: id, option: token) }
      return value
    case (.points(_, let maxCount), .points(let points)):
      return .points(try Self.validated(points, maxCount: maxCount, id: id))
    // A stored string comes back as a choice (`ParamValue` decoding): the text it was.
    case (.text(_, let maxLength), .text(let text)), (.text(_, let maxLength), .choice(let text)):
      guard text.count <= maxLength else { throw ParamError.tooLong(id: id) }
      // Kept as typed (a field binds every keystroke: « 00 » then a space); readers trim.
      return .text(text)
    default:
      throw ParamError.wrongKind(id: id)
    }
  }
}

extension ParamSpec {
  /// `points` clamped into [0, 1] and sorted by x; refuses fewer than 2 or more than `maxCount`
  /// points, a non-finite coordinate or two points at the same x (a curve has one output per input).
  static func validated(_ points: [CurvePoint], maxCount: Int, id: String) throws -> [CurvePoint] {
    guard (2...max(2, maxCount)).contains(points.count) else {
      throw ParamError.invalidPoints(id: id)
    }
    guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
      throw ParamError.notFinite(id: id)
    }
    let unit = { (value: Double) in min(max(value, 0), 1) }
    let sorted = points.map { CurvePoint(unit($0.x), unit($0.y)) }.sorted { $0.x < $1.x }
    guard zip(sorted, sorted.dropFirst()).allSatisfy({ $0.x < $1.x }) else {
      throw ParamError.invalidPoints(id: id)
    }
    return sorted
  }
}

/// How a parameter's value is read.
package enum ParamUnit: String, Codable, Sendable {
  /// A plain number.
  case none
  /// Image pixels at full resolution: divided by the preview scale inside `render`.
  case px
  /// Standard deviations of the background noise.
  case sigma
  /// 0 (none) to 1 (all).
  case opacity
}

/// Where a panel shows a parameter (design §2 display rule).
package enum ParamLevel: String, Codable, Sendable {
  /// Shown by default.
  case simple
  /// Behind the "Avancé" disclosure unless a profile promotes it.
  case advanced
}

/// Why a value was refused.
package enum ParamError: Error, Equatable, Sendable {
  /// No parameter has this id.
  case unknown(id: String)
  /// NaN or ±Inf.
  case notFinite(id: String)
  /// A number for a flag, a flag for a choice…
  case wrongKind(id: String)
  /// A choice outside the parameter's options.
  case unknownOption(id: String, option: String)
  /// Too few or too many curve points, or two at the same x.
  case invalidPoints(id: String)
  /// A text longer than the parameter allows.
  case tooLong(id: String)
}

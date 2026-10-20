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

  /// A parameter choosing one of `options`.
  package init(id: String, title: String, level: ParamLevel, choice: String, of options: [String]) {
    self.init(
      id: id, title: title, unit: .none, level: level,
      kind: .choice(default: choice, options: options))
  }

  /// A parameter of any kind.
  package init(id: String, title: String, unit: ParamUnit, level: ParamLevel, kind: Kind) {
    self.id = id
    self.title = title
    self.unit = unit
    self.level = level
    self.kind = kind
  }

  /// The default value.
  package var defaultValue: ParamValue {
    switch kind {
    case .number(let value, _): .number(value)
    case .flag(let value): .flag(value)
    case .choice(let value, _): .choice(value)
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
      guard options.contains(option) else {
        throw ParamError.unknownOption(id: id, option: option)
      }
      return value
    default:
      throw ParamError.wrongKind(id: id)
    }
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
}

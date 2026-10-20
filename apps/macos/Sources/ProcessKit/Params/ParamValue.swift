/// A parameter's value.
package enum ParamValue: Equatable, Sendable {
  /// A number (already clamped when it comes from a `ParamSet`).
  case number(Double)
  /// On or off.
  case flag(Bool)
  /// One of the parameter's options.
  case choice(String)
}

/// JSON: a number, a boolean or a string — the kind is the JSON type.
extension ParamValue: Codable {
  /// Decodes from the JSON type.
  package init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let flag = try? container.decode(Bool.self) {
      self = .flag(flag)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else {
      self = .choice(try container.decode(String.self))
    }
  }

  /// Encodes as the matching JSON type.
  package func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .number(let number): try container.encode(number)
    case .flag(let flag): try container.encode(flag)
    case .choice(let option): try container.encode(option)
    }
  }
}

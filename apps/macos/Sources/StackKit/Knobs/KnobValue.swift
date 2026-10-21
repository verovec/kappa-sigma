/// One knob's value: a number, an on/off flag or one of a list's ids — as it travels in a patch.
package enum KnobValue: Equatable, Hashable, Sendable {
  case number(Double)
  case flag(Bool)
  case choice(String)
}

extension KnobValue: Codable {
  /// A bare JSON value: `3.5`, `true` or `"sigma"`, as the legacy params patch carried them.
  package init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let flag = try? value.decode(Bool.self) {
      self = .flag(flag)
    } else if let number = try? value.decode(Double.self) {
      self = .number(number)
    } else {
      self = .choice(try value.decode(String.self))
    }
  }

  package func encode(to encoder: any Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .number(let number): try value.encode(number)
    case .flag(let flag): try value.encode(flag)
    case .choice(let id): try value.encode(id)
    }
  }
}

extension KnobValue: CustomStringConvertible {
  package var description: String {
    switch self {
    case .number(let number): "\(number)"
    case .flag(let flag): "\(flag)"
    case .choice(let id): id
    }
  }
}

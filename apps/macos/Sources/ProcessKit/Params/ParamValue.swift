/// A parameter's value.
package enum ParamValue: Equatable, Sendable {
  /// A number (already clamped when it comes from a `ParamSet`).
  case number(Double)
  /// On or off.
  case flag(Bool)
  /// One of the parameter's options.
  case choice(String)
  /// Control points of a curve, sorted by x (already validated when they come from a `ParamSet`).
  case points([CurvePoint])
  /// Free text (a coordinate as typed); empty: not given.
  case text(String)
}

/// A control point of a curve, both coordinates in [0, 1].
package struct CurvePoint: Equatable, Sendable {
  /// Input value.
  package let x: Double
  /// Output value.
  package let y: Double

  /// The point (`x`, `y`).
  package init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }
}

/// JSON: a number, a boolean, a string or an array of `[x, y]` pairs — the kind is the JSON type
/// (a string decodes as a choice; a text parameter takes it as its text).
extension ParamValue: Codable {
  /// Decodes from the JSON type.
  package init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let flag = try? container.decode(Bool.self) {
      self = .flag(flag)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let pairs = try? container.decode([[Double]].self) {
      // A point that is not an [x, y] pair empties the curve: validation refuses it as one
      // parameter, never the whole recipe.
      self = .points(
        pairs.allSatisfy { $0.count == 2 } ? pairs.map { CurvePoint($0[0], $0[1]) } : [])
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
    case .points(let points): try container.encode(points.map { [$0.x, $0.y] })
    case .text(let text): try container.encode(text)
    }
  }
}

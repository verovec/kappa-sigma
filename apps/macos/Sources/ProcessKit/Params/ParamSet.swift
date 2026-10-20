/// The values of a process's parameters, one per schema entry, in schema order: what the panel
/// shows is exactly what `render` reads (R2: values applied = values shown).
package struct ParamSet: Equatable, Sendable {
  /// One stored value.
  package struct Entry: Equatable, Sendable, Codable {
    /// The parameter's id.
    package let id: String
    /// Its value.
    package let value: ParamValue

    /// The value `value` of parameter `id`.
    package init(id: String, value: ParamValue) {
      self.id = id
      self.value = value
    }
  }

  /// The values, in schema order.
  package private(set) var entries: [Entry]
  private let schema: ParamSchema?

  /// The defaults of `schema`.
  package init(schema: ParamSchema) {
    self.schema = schema
    entries = schema.specs.map { Entry(id: $0.id, value: $0.defaultValue) }
  }

  /// `stored` values onto `schema`'s defaults: each one validated (clamped); those naming no
  /// parameter or refused are returned, never silently dropped.
  package static func loading(
    _ stored: [Entry], onto schema: ParamSchema
  ) -> (params: Self, rejected: [Entry]) {
    var params = Self(schema: schema)
    var rejected: [Entry] = []
    for entry in stored {
      do {
        try params.set(entry.id, entry.value)
      } catch {
        rejected.append(entry)
      }
    }
    return (params, rejected)
  }

  /// The ids, in schema order.
  package var ids: [String] { entries.map(\.id) }

  /// The value of `id`.
  package subscript(id: String) -> ParamValue? {
    entries.first { $0.id == id }?.value
  }

  /// Sets `id` to `value` made valid by the schema (numbers clamped); refuses NaN/±Inf, a wrong
  /// kind, an unknown option or id, leaving the set unchanged.
  package mutating func set(_ id: String, _ value: ParamValue) throws(ParamError) {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { throw .unknown(id: id) }
    let valid = try schema?.spec(id)?.validated(value) ?? value
    entries[index] = Entry(id: id, value: valid)
  }

  /// The number `id` (0 when it is not a number: a process reads its own schema).
  package func number(_ id: String) -> Double {
    if case .number(let value) = self[id] { return value }
    return 0
  }

  /// The flag `id` (`false` when it is not a flag).
  package func flag(_ id: String) -> Bool {
    if case .flag(let value) = self[id] { return value }
    return false
  }

  /// The option chosen for `id` (empty when it is not a choice).
  package func choice(_ id: String) -> String {
    if case .choice(let value) = self[id] { return value }
    return ""
  }

  /// Sets compare values only: two sets with the same values are equal whatever their schema
  /// object (a decoded set carries none until `loading` puts it on one).
  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.entries == rhs.entries
  }
}

/// JSON: an ordered array of `{ "id": …, "value": … }`, so a recipe lists parameters in panel
/// order. A decoded set has no schema; `loading(_:onto:)` validates it against one.
extension ParamSet: Codable {
  /// Decodes the stored entries as they are.
  package init(from decoder: any Decoder) throws {
    entries = try [Entry](from: decoder)
    schema = nil
  }

  /// Encodes the entries in order.
  package func encode(to encoder: any Encoder) throws {
    try entries.encode(to: encoder)
  }
}

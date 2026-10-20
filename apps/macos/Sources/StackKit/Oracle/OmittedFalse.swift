/// A boolean the legacy engine writes with Go's `omitempty`: an absent key means `false`.
@propertyWrapper
package struct OmittedFalse: Decodable, Equatable, Sendable {
  /// The decoded value, `false` when the key was absent.
  package var wrappedValue: Bool

  /// `false`.
  package init() { wrappedValue = false }

  /// Decodes the present value.
  package init(from decoder: any Decoder) throws {
    wrappedValue = try decoder.singleValueContainer().decode(Bool.self)
  }
}

extension KeyedDecodingContainer {
  /// An absent key decodes as `false` instead of failing.
  package func decode(_ type: OmittedFalse.Type, forKey key: Key) throws -> OmittedFalse {
    try decodeIfPresent(type, forKey: key) ?? OmittedFalse()
  }
}

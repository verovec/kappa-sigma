/// The knobs a run changes from its preset, by id.
///
/// What the Stacking panel writes and what a stack records; an empty patch is the preset itself.
package struct KnobPatch: Equatable, Sendable {
  package var values: [String: KnobValue]

  /// A patch setting `values`.
  package init(values: [String: KnobValue] = [:]) {
    self.values = values
  }
}

extension KnobPatch: Codable {
  /// A flat JSON object under the legacy wire keys: `{"fwhm_sigma": 3.5, "stack_reject": "sigma"}`.
  package init(from decoder: any Decoder) throws {
    values = try [String: KnobValue](from: decoder)
  }

  package func encode(to encoder: any Encoder) throws {
    try values.encode(to: encoder)
  }
}

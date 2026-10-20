/// The stacking recipe of each master type (`stackalg.MasterOptions`): bias and darks keep their
/// pedestal (no normalization), flats are levelled multiplicatively.
package struct MasterRecipes: Equatable, Sendable {
  package var bias = StackOptions.bias
  package var dark = StackOptions.dark
  package var darkFlat = StackOptions.dark
  package var flat = StackOptions.flat

  /// The legacy defaults: masters built with them keep their library names.
  package init() {}

  /// The recipe of `type`.
  package func options(_ type: MasterType) -> StackOptions {
    switch type {
    case .bias: bias
    case .dark: dark
    case .darkFlat: darkFlat
    case .flat: flat
    }
  }
}

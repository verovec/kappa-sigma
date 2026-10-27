package import FilterKit

extension FilterSet {
  /// A wire value as the inspection reads it: an unknown one is an `InspectError`, the error the
  /// import and the app's wording know (FilterKit's own `ParseError` stays inside the kit).
  package init(inspecting raw: String) throws {
    do {
      try self.init(parsing: raw)
    } catch ParseError.unknownFilterSet(let value) {
      throw InspectError.unknownFilterSet(value)
    }
  }
}

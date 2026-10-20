/// A process's parameters, in panel order.
package struct ParamSchema: Equatable, Sendable {
  /// The parameters, in the order the panel and recipes list them.
  package let specs: [ParamSpec]

  /// A schema of `specs`; ids must be unique (a duplicate is a programming error).
  package init(_ specs: [ParamSpec]) {
    precondition(Set(specs.map(\.id)).count == specs.count, "ParamSchema: duplicate parameter id")
    self.specs = specs
  }

  /// The parameter `id`, if any.
  package func spec(_ id: String) -> ParamSpec? {
    specs.first { $0.id == id }
  }

  /// Display rule (design §2): `simple` parameters always; `advanced` ones when the disclosure
  /// is open or a profile promotes them — schema order kept.
  package func visible(disclosed: Bool, promoted: Set<String> = []) -> [ParamSpec] {
    specs.filter { $0.level == .simple || disclosed || promoted.contains($0.id) }
  }

  /// Whether the panel needs the "Avancé" disclosure.
  package var hasAdvanced: Bool {
    specs.contains { $0.level == .advanced }
  }

  /// The ids of the parameters in pixels.
  package var pixelParameters: [String] {
    specs.filter { $0.unit == .px }.map(\.id)
  }
}

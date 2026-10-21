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

  /// What makes a spec unusable: non-finite bounds, or a default the spec itself would refuse
  /// or clamp (an untouched default must be a value `set` accepts unchanged).
  package var problems: [String] {
    specs.compactMap { spec -> String? in
      switch spec.kind {
      case .number(let value, let bounds):
        guard bounds.lowerBound.isFinite, bounds.upperBound.isFinite else {
          return "\(spec.id): bounds must be finite"
        }
        return bounds.contains(value) ? nil : "\(spec.id): default \(value) outside \(bounds)"
      case .choice(let value, let options):
        return options.contains(value) ? nil : "\(spec.id): default \(value) not among its options"
      case .flag:
        return nil
      case .points(let value, let maxCount):
        let valid = try? ParamSpec.validated(value, maxCount: maxCount, id: spec.id)
        return valid == value
          ? nil : "\(spec.id): default points are not sorted, unique and in [0, 1]"
      }
    }
  }

  /// The ids of the parameters in pixels.
  package var pixelParameters: [String] {
    specs.filter { $0.unit == .px }.map(\.id)
  }
}

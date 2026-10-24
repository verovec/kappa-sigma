internal import Foundation

/// Type-ahead over the whole catalogue (legacy `search.go`).
extension SkyCatalogue {
  /// The objects matching `query` by name, common name or alias, best first, at most `limit`.
  ///
  /// Exact before prefix before contains, then the field (name, common name, alias), then Messier →
  /// NGC → IC → Sh2 → LDN, then a known magnitude before none, the brighter first, then merge order.
  /// A blank query or a limit ≤ 0 finds nothing.
  package func search(_ query: String, limit: Int) -> [SkyObject] {
    let key = Self.normalize(query)
    guard !key.isEmpty, limit > 0 else { return [] }
    let hits = objects.indices.compactMap { position in
      Self.rank(objects[position], key).map { (position: position, rank: $0) }
    }
    let sorted = hits.sorted { lhs, rhs in
      if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
      let (left, right) = (objects[lhs.position], objects[rhs.position])
      if left.source != right.source { return Self.order(left.source) < Self.order(right.source) }
      switch Self.magnitudeOrder(left, right) {
      case .orderedAscending: return true
      case .orderedDescending: return false
      case .orderedSame: return lhs.position < rhs.position
      }
    }
    return sorted.prefix(limit).map { objects[$0.position] }
  }

  /// The match: how (exact, prefix, contains) then which field; lowest wins, nil for none.
  ///
  /// Exactness dominates, then the primary name over a common name over an alias — but a
  /// contained common name outranks a contained name (the legacy buckets).
  private static func rank(_ object: SkyObject, _ key: String) -> Int? {
    // Per field: its tokens and its exact, prefix and contains buckets.
    let fields: [(tokens: [String], buckets: [Int])] = [
      ([object.name], [0, 3, 7]), (object.commonNames, [1, 4, 6]), (object.aliases, [2, 5, 8]),
    ]
    return fields.flatMap { field in
      field.tokens.compactMap { token -> Int? in
        let normalised = normalize(token)
        if normalised.isEmpty { return nil }
        if normalised == key { return field.buckets[0] }
        if normalised.hasPrefix(key) { return field.buckets[1] }
        return normalised.contains(key) ? field.buckets[2] : nil
      }
    }.min()
  }

  /// The list's rank: Messier objects are the famous ones, then NGC/IC, then the surveys.
  private static func order(_ source: SkyObject.Source) -> Int {
    SkyObject.Source.allCases.firstIndex(of: source) ?? 0
  }

  /// `lhs` against `rhs` on magnitude: a known one before none, the brighter first.
  private static func magnitudeOrder(_ lhs: SkyObject, _ rhs: SkyObject) -> ComparisonResult {
    switch (lhs.magnitude, rhs.magnitude) {
    case (let left?, let right?):
      left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
    case (.some, nil): .orderedAscending
    case (nil, .some): .orderedDescending
    case (nil, nil): .orderedSame
    }
  }
}
